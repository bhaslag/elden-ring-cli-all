#!/usr/bin/env python3
"""
Elden Ring CLI — build-time data extractor.

Pulls pages from the Fandom MediaWiki API (eldenring.fandom.com), normalizes them
into the Entity shape defined in docs/data-layout.md, and writes ONE combined JSON
file that the Odin program will bundle via #load.

This is the messy half of the pipeline (network, wikitext parsing, normalization),
run once by Bill at build time — never by end users. Odin only ever sees clean JSON.

Usage:
    uv run --python 3.11 tools/extract.py                 # full crawl (uses cache)
    uv run --python 3.11 tools/extract.py --limit 15      # 15 pages/category (fast test)
    uv run --python 3.11 tools/extract.py --refresh       # ignore cache, re-crawl
    uv run --python 3.11 tools/extract.py --normalize-only # re-normalize from cache

Stdlib only — no external deps, so plain `python3 tools/extract.py` also works.

Coverage & limits: this is a solid first pass, not perfect. Wikitext is dirty;
heuristics won't catch every edge case. Sections default to the `Lore` tier when
unrecognized (spoiler-safe). See the stats printed at the end.
"""
from __future__ import annotations
import argparse, json, os, re, sys, time, unicodedata, urllib.parse, urllib.request

API = "https://eldenring.fandom.com/api.php"
UA = "elden-ring-cli-extractor/0.1 (learning project; contact bhaslag@gmail.com)"
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache", "raw_pages.json")
ALIAS_CACHE = os.path.join(HERE, "cache", "aliases.json")
DEFAULT_OUT = os.path.join(os.path.dirname(HERE), "data", "entities.json")
RATE = 0.12  # seconds between API calls (be polite)

# ── what to crawl ────────────────────────────────────────────────────────────
# Category name on the wiki -> nothing; classification is by the page's OWN
# categories + infobox template (see classify()). Missing categories are skipped.
SOURCE_CATEGORIES = [
    # characters
    "Bosses", "NPCs",
    # locations
    "Locations", "Legacy Dungeons",
    # items
    "Weapons", "Shields", "Armor", "Ashes of War", "Spirit Ashes",
    "Talismans", "Sorceries", "Incantations", "Tools", "Key Items",
    "Bolstering Materials", "Crafting Materials",
    # lore / concept (spine-only, nil variant)
    "Lore",
]

# ── section heading -> spoiler tier (docs/data-layout.md §2a) ─────────────────
CHROME = {  # discarded, never stored
    "gallery", "references", "navigation", "see also", "external links",
    "notes & tips",  # keep 'notes' though
}
TIER_BASIC = {
    "description", "overview", "notes", "acquisition", "effect", "effects",
    "skills", "skill", "upgrades", "upgrading", "upgrade information",
    "sites of grace", "notable loot", "enemies", "npcs", "characters",
    "walkthrough", "requirements", "shop inventory", "moveset", "boss fight",
    "combat information", "character information", "stats", "location", "locations",
    "required items", "landmarks", "objects", "items", "materials", "map fragments",
}
TIER_LORE = {
    "background", "game events", "game progress", "questline progression",
    "dialogue", "characteristics", "lore", "story", "role in the story", "quests",
}
# unrecognized headings default to Lore (spoiler-safe)

# infobox templates -> entity kind. "Skip" = not a game entity (nav/list/hub page).
def classify(templates: list[str], categories: set[str]) -> str:
    t = " ".join(templates).lower().replace("_", " ")  # unify Infobox_X / Infobox X
    if "infobox weapon" in t:
        return "Weapon"
    if "infobox armor" in t:
        return "Armor"
    if "infobox item" in t:
        return "Item"
    if "infobox character" in t or "infobox boss" in t:
        return "Character"
    if any(k in t for k in ("infobox location", "infobox region",
                            "infobox subregion", "infobox legacy dungeon")):
        return "Location"
    # no recognized entity infobox -> lean on categories (precedence Location > Character)
    if "locations" in categories or "legacy dungeons" in categories:
        return "Location"
    if categories & {"bosses", "npcs", "characters", "demigods"}:
        return "Character"
    if "lore" in categories:
        return "Concept"   # spine-only, nil variant (genuine lore/concept page)
    return "Skip"          # list/hub/nav page ("Weapons", "Chest", "Armor") — drop it

# ── HTTP ─────────────────────────────────────────────────────────────────────
def api_get(params: dict) -> dict:
    params = {**params, "format": "json", "formatversion": "2"}
    url = f"{API}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def list_category(cat: str, visited: set[str], depth: int = 0, max_depth: int = 3) -> set[str]:
    """Recursively enumerate ns0 page titles under a category, following subcategories."""
    if cat in visited or depth > max_depth:
        return set()
    visited.add(cat)
    titles: set[str] = set()
    subcats: list[str] = []
    cont: dict = {}
    while True:
        params = {"action": "query", "list": "categorymembers",
                  "cmtitle": f"Category:{cat}", "cmlimit": "500",
                  "cmtype": "page|subcat", **cont}
        try:
            d = api_get(params)
        except Exception as e:
            print(f"    ! {cat}: {e}")
            break
        for m in d.get("query", {}).get("categorymembers", []):
            if m["ns"] == 14:
                subcats.append(m["title"].removeprefix("Category:"))
            elif m["ns"] == 0:
                titles.add(m["title"])
        cont = d.get("continue", {})
        time.sleep(RATE)
        if not cont:
            break
    for sc in subcats:
        titles |= list_category(sc, visited, depth + 1, max_depth)
    return titles

def fetch_pages(titles: list[str]) -> dict[str, dict]:
    """Batch-fetch content + categories for page titles (50 per request)."""
    out: dict[str, dict] = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        cont: dict = {}
        while True:
            params = {"action": "query", "titles": "|".join(batch),
                      "prop": "revisions|categories", "rvprop": "content",
                      "rvslots": "main", "cllimit": "max", "redirects": "1", **cont}
            try:
                d = api_get(params)
            except Exception as e:
                print(f"    ! batch @{i}: {e}")
                break
            for p in d.get("query", {}).get("pages", []):
                title = p.get("title")
                revs = p.get("revisions") or []
                if not title or not revs:
                    continue
                wt = revs[0].get("slots", {}).get("main", {}).get("content", "")
                cats = {c["title"].removeprefix("Category:").lower()
                        for c in p.get("categories", [])}
                if title in out:
                    out[title]["categories"] = sorted(set(out[title]["categories"]) | cats)
                else:
                    out[title] = {"title": title, "wikitext": wt, "categories": sorted(cats)}
            cont = d.get("continue", {})
            time.sleep(RATE)
            if not cont:
                break
        print(f"    fetched {min(i + 50, len(titles))}/{len(titles)}", end="\r", flush=True)
    print()
    return out

def fetch_aliases(titles: list[str]) -> dict[str, str]:
    """Map every redirect title -> its canonical page title (prop=redirects)."""
    alias: dict[str, str] = {}
    for i in range(0, len(titles), 50):
        batch = titles[i:i + 50]
        cont: dict = {}
        while True:
            params = {"action": "query", "titles": "|".join(batch),
                      "prop": "redirects", "rdlimit": "max", "rdnamespace": "0", **cont}
            try:
                d = api_get(params)
            except Exception as e:
                print(f"    ! aliases @{i}: {e}")
                break
            for p in d.get("query", {}).get("pages", []):
                canon = p.get("title")
                for r in p.get("redirects", []) or []:
                    alias[r["title"]] = canon
            cont = d.get("continue", {})
            time.sleep(RATE)
            if not cont:
                break
        print(f"    aliases {min(i + 50, len(titles))}/{len(titles)}", end="\r", flush=True)
    print()
    return alias

# ── wikitext parsing ─────────────────────────────────────────────────────────
def split_top(s: str) -> list[str]:
    parts, buf, db, dbr, i = [], [], 0, 0, 0
    while i < len(s):
        two = s[i:i + 2]
        if two == "{{": db += 1; buf.append(two); i += 2; continue
        if two == "}}": db -= 1; buf.append(two); i += 2; continue
        if two == "[[": dbr += 1; buf.append(two); i += 2; continue
        if two == "]]": dbr -= 1; buf.append(two); i += 2; continue
        c = s[i]
        if c == "|" and db == 0 and dbr == 0:
            parts.append("".join(buf)); buf = []; i += 1; continue
        buf.append(c); i += 1
    parts.append("".join(buf))
    return parts

def all_infobox_templates(wt: str) -> list[str]:
    return [m.group(1).strip() for m in re.finditer(r"\{\{\s*(Infobox[ _][^\n|}]*)", wt, re.I)]

def parse_infobox(wt: str) -> tuple[str | None, dict]:
    m = re.search(r"\{\{\s*Infobox", wt, re.I)
    if not m:
        return None, {}
    idx, i, depth = m.start(), m.start() + 2, 1
    while i < len(wt) and depth > 0:
        if wt[i:i + 2] == "{{": depth += 1; i += 2; continue
        if wt[i:i + 2] == "}}": depth -= 1; i += 2; continue
        i += 1
    params = split_top(wt[idx + 2:i - 2])
    name = params[0].strip().replace("\n", " ")
    name = re.sub(r"<!--.*?-->", "", name).strip()
    kv: dict[str, str] = {}
    for p in params[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            k = re.sub(r"\s+", "_", k.strip().lower())
            v = v.strip()
            if k:
                kv[k] = v
    return name, kv

def strip_templates(s: str) -> str:
    out, depth, i = [], 0, 0
    while i < len(s):
        two = s[i:i + 2]
        if two == "{{": depth += 1; i += 2; continue
        if two == "}}": depth = max(0, depth - 1); i += 2; continue
        if depth == 0: out.append(s[i])
        i += 1
    return "".join(out)

def strip_tables(s: str) -> str:
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\{\|(?:[^{}]|\{\{[^{}]*\}\})*?\|\}", "", s, flags=re.S)
    return s

def clean_text(s: str) -> str:
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<ref[^>]*/>", "", s, flags=re.S)
    s = re.sub(r"<ref[^>]*>.*?</ref>", "", s, flags=re.S)
    s = strip_templates(s)
    s = strip_tables(s)
    # links: drop File/Image/Category; [[a|b]]->b ; [[a]]->a
    s = re.sub(r"\[\[(?:File|Image|Category):[^\]]*\]\]", "", s, flags=re.I)
    s = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"\[\[([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"\[https?://\S+\s+([^\]]*)\]", r"\1", s)
    s = re.sub(r"\[https?://\S+\]", "", s)
    s = s.replace("'''", "").replace("''", "")
    s = s.replace("|-|", "\n")                          # tabber separators
    s = re.sub(r"={2,}\s*(.*?)\s*={2,}", r"\1:", s)     # leftover ===subheads=== -> "x:"
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = re.sub(r"^[\*\#:;]+\s*", "", s, flags=re.M)     # list/def markers
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\s+([.,;:!?])", r"\1", s)              # space before punctuation
    s = re.sub(r"\(\s*\)", "", s)                       # empty parens from stripped links
    s = re.sub(r"\b(in|from|at|of)\s+(and|\.|,)", r"\2", s)  # "found in ." -> "found."
    s = re.sub(r"[ \t]{2,}", " ", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()

def parse_links(s: str) -> list[tuple[str, str]]:
    out = []
    for m in re.finditer(r"\[\[([^\]|]+)(?:\|([^\]]*))?\]\]", s):
        target = m.group(1).strip()
        if re.match(r"(File|Image|Category):", target, re.I):
            continue
        out.append((target, (m.group(2) or target).strip()))
    return out

HEADING_RE = re.compile(r"^==\s*([^=].*?)\s*==\s*$", re.M)

def split_sections(wt: str) -> tuple[str, list[dict]]:
    """Return (lead_text, [{heading, level2_body_raw}])."""
    matches = list(HEADING_RE.finditer(wt))
    lead = wt[:matches[0].start()] if matches else wt
    secs = []
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(wt)
        secs.append({"heading": m.group(1).strip(), "raw": wt[start:end]})
    return lead, secs

def tier_for(heading: str) -> str:
    h = heading.lower()
    if h in TIER_BASIC:
        return "Basic"
    if h in TIER_LORE:
        return "Lore"
    return "Lore"  # spoiler-safe default

# ── value helpers ────────────────────────────────────────────────────────────
def coerce_number(raw: str):
    if raw is None:
        return None
    s = clean_text(raw)
    s = s.replace(",", "")
    m = re.search(r"-?\d+(?:\.\d+)?", s)
    return None if not m else (float(m.group()) if "." in m.group() else int(m.group()))

def slugify(t: str) -> str:
    t = t.split("#")[0].strip()
    t = re.sub(r"\s*\[\d+\]$", "", t)  # strip stackable [N] suffix
    t = unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()
    t = re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")
    return t

def resolve_slug(target: str, id_set: set[str], alias: dict[str, str]) -> str | None:
    """Link target -> canonical entity slug (via redirect alias map), or None."""
    s = slugify(target)
    if s in id_set:
        return s
    a = alias.get(s)
    if a and a in id_set:
        return a
    return None

def refs_from(raw: str, id_set: set[str], alias: dict[str, str]) -> list[str]:
    """[[links]] -> canonical slug if resolvable (incl. redirects) else literal text."""
    if not raw:
        return []
    links = parse_links(raw)
    out = []
    if links:
        for target, disp in links:
            r = resolve_slug(target, id_set, alias)
            out.append(r if r else clean_text(disp))
    else:  # no links: split plain text on <br>/commas as literals
        for piece in re.split(r"<br\s*/?>|,|\n", raw):
            p = clean_text(piece)
            if p:
                out.append(p)
    # dedup preserve order
    seen, uniq = set(), []
    for r in out:
        if r and r not in seen:
            seen.add(r); uniq.append(r)
    return uniq

def sec_link_refs(raw: str, id_set: set[str], alias: dict[str, str]) -> list[str] | None:
    """Resolve all [[links]] in a section body to canonical slugs / literals."""
    out = [resolve_slug(t, id_set, alias) or clean_text(d) for t, d in parse_links(raw)]
    return out or None

def clean_field(raw: str | None):
    if raw is None:
        return None
    v = clean_text(raw)
    return v or None

def list_field(raw: str | None):
    if raw is None:
        return None
    parts = [clean_text(p) for p in re.split(r"<br\s*/?>|\n", raw)]
    parts = [p for p in parts if p]
    return parts or None

def body_to_text(raw: str) -> str:
    return clean_text(raw)

def prune(d: dict) -> dict:
    return {k: v for k, v in d.items() if v not in (None, [], {}, "")}

# ── per-variant normalization ────────────────────────────────────────────────
RES_KEYS = ["standard", "slash", "strike", "pierce", "magic", "fire", "lightning",
            "holy", "poison", "rot", "bleed", "frost", "sleep", "madness", "death"]
STAT_KEYS = ["str", "dex", "int", "fai", "arc", "vig", "mnd", "end"]

def build_character(kv, sections, id_set, alias):
    identity = prune({
        "title": clean_field(kv.get("title")),
        "aka": list_field(kv.get("aka")),
        "role": clean_field(kv.get("role")),
        "race": clean_field(kv.get("race")),
        "affiliation": clean_field(kv.get("affiliation")),
        "classification": clean_field(kv.get("classification")),
        "voice": clean_field(kv.get("voice")),
    })
    # relations (spoiler-gated group)
    rel = {}
    for key in ("parents", "siblings", "children", "descendants", "ancestors",
                "predecessors", "successors", "partners", "relatives",
                "allegiance", "affiliation"):
        if key in kv:
            r = refs_from(kv[key], id_set, alias)
            if r:
                rel[key] = r
    relations = {"tier": "Lore", **rel} if rel else None

    # combat facet
    resistances = prune({k: coerce_number(kv.get(f"res_{k}")) for k in RES_KEYS})
    stats = prune({k: coerce_number(kv.get(k)) for k in STAT_KEYS})
    drops_raw = kv.get("drops", "")
    runes = None
    rm = re.search(r"([\d,]+)\s*Runes?", drops_raw, re.I)
    if rm:
        runes = int(rm.group(1).replace(",", ""))
    drops_raw = re.sub(r"[\d,]+\s*Runes?", "", drops_raw, flags=re.I)
    moveset = None
    for s in sections:
        if s["heading"].lower() in ("boss fight", "moveset"):
            moveset = list_field(s["raw"]) or [body_to_text(s["raw"])]
            break
    combat = prune({
        "hp": coerce_number(kv.get("hp")),
        "poise": coerce_number(kv.get("poise")),
        "resistances": resistances or None,
        "weaknesses": list_field(kv.get("weakness")) or list_field(kv.get("weak_spot")),
        "phases": coerce_number(kv.get("phases")),
        "moveset": moveset,
        "drops": refs_from(drops_raw, id_set, alias) or None,
        "runes": runes,
        "stats": stats or None,
    })
    # quest facet
    questline = None
    shop = None
    for s in sections:
        h = s["heading"].lower()
        if "questline" in h or h.endswith("'s quest") or h == "quests":
            questline = list_field(s["raw"]) or [body_to_text(s["raw"])]
        if "shop" in h:
            shop = sec_link_refs(s["raw"], id_set, alias)
    quest = prune({"questline": questline, "shop": shop})

    v = {"kind": "Character", **identity}
    if combat:
        v["combat"] = combat
    if quest:
        v["quest"] = quest
    if relations:
        v["relations"] = relations
    return v

def build_location(kv, sections, id_set, alias):
    def sec_refs(*names):
        for s in sections:
            if s["heading"].lower() in names:
                return sec_link_refs(s["raw"], id_set, alias)
        return None
    return prune({
        "kind": "Location",
        "region": (refs_from(kv["region"], id_set, alias) or [None])[0] if "region" in kv else None,
        "sub_regions": refs_from(kv.get("sub-regions", kv.get("sub_regions", "")), id_set, alias) or None,
        "graces": list_field(kv.get("graces")) or sec_refs("sites of grace"),
        "is_legacy_dungeon": True if kv.get("legacy-dungeon") or kv.get("legacy_dungeon") else None,
        "is_optional": True if str(kv.get("optional", "")).strip().lower() in ("yes", "true", "1") else None,
        "map_fragment": clean_field(kv.get("map_fragment")),
        "bosses": refs_from(kv.get("bosses", ""), id_set, alias) or sec_refs("bosses"),
        "npcs": refs_from(kv.get("npcs", ""), id_set, alias) or sec_refs("npcs", "characters"),
        "notable_loot": sec_refs("notable loot"),
    })

def struct(kv, keys):
    return prune({out: coerce_number(kv.get(src)) for out, src in keys})

def scale_struct(kv, keys):
    return prune({out: clean_field(kv.get(src)) for out, src in keys})

def build_weapon(kv, sections, id_set, alias):
    return prune({
        "kind": "Weapon",
        "weapon_class": clean_field(kv.get("type")),
        "attack_type": clean_field(kv.get("attack_type")),
        "weight": coerce_number(kv.get("weight")),
        "attack": struct(kv, [("physical", "physical_power"), ("magic", "magic_power"),
                              ("fire", "fire_power"), ("lightning", "lightning_power"),
                              ("holy", "holy_power"), ("critical", "critical")]),
        "guard": struct(kv, [("physical", "physical_guarded"), ("magic", "magic_guarded"),
                             ("fire", "fire_guarded"), ("lightning", "lightning_guarded"),
                             ("holy", "holy_guarded"), ("boost", "guard_boost")]),
        "scaling": scale_struct(kv, [("str", "str_scale"), ("dex", "dex_scale"),
                                     ("int", "int_scale"), ("fai", "fai_scale"),
                                     ("arc", "arc_scale")]),
        "requirements": struct(kv, [("str", "str_req"), ("dex", "dex_req"),
                                    ("int", "int_req"), ("fai", "fai_req"),
                                    ("arc", "arc_req")]),
        "skill": clean_field(kv.get("skills")),
        "passive_effects": list_field(kv.get("effects")),
    })

def build_armor(kv, sections, id_set, alias):
    return prune({
        "kind": "Armor",
        "slot": (clean_field(kv.get("type")) or "").capitalize() or None,
        "weight": coerce_number(kv.get("weight")),
        "defense": struct(kv, [("physical", "physical"), ("magic", "magic"),
                               ("fire", "fire"), ("lightning", "lightning"), ("holy", "holy")]),
        "resistance": struct(kv, [("slash", "vs_slash"), ("strike", "vs_strike"),
                                  ("pierce", "vs_pierce"), ("immunity", "immunity"),
                                  ("robustness", "robustness"), ("focus", "focus"),
                                  ("vitality", "vitality"), ("poise", "poise")]),
        "has_altered": True if kv.get("altered") else None,
        "passive_effects": list_field(kv.get("effects")),
    })

def build_item(kv, sections, id_set, alias):
    # tiers for stackable/combined pages: rows like "* [1] ..." are hard to parse
    # reliably; capture a light tier table only if an obvious list is present.
    return prune({
        "kind": "Item",
        "category": clean_field(kv.get("type")),
        "effect": clean_field(kv.get("item_effect")),
        "fp_cost": coerce_number(kv.get("fp_cost")),
        "slots_used": coerce_number(kv.get("slots_used")),
        "spell_reqs": struct(kv, [("int", "int_req"), ("fai", "fai_req"), ("arc", "arc_req")]),
        "weight": coerce_number(kv.get("weight")),
        "required_items": refs_from(kv.get("required_items", ""), id_set, alias) or None,
        "buy_price": coerce_number(kv.get("buy_price")),
        "sell_price": coerce_number(kv.get("sell_price")),
    })

BUILDERS = {
    "Character": build_character, "Location": build_location,
    "Weapon": build_weapon, "Armor": build_armor, "Item": build_item,
}

# ── entity assembly ──────────────────────────────────────────────────────────
def normalize(page: dict, id_set: set[str], alias: dict[str, str]) -> dict | None:
    title, wt = page["title"], page["wikitext"]
    if ":" in title and title.split(":")[0] in ("Category", "Template", "File", "User"):
        return None
    wt = re.sub(r"\{\{\s*(?:subst:)?PAGENAME\s*\}\}", title, wt, flags=re.I)
    cats = set(page.get("categories", []))
    templates = all_infobox_templates(wt)
    kind = classify(templates, cats)
    if kind == "Skip":
        return None
    name_kv, kv = parse_infobox(wt)
    lead, secs = split_sections(wt)

    # description: prefer lead paragraph, else Description/Overview section
    desc = clean_text(lead)
    if not desc:
        for s in secs:
            if s["heading"].lower() in ("description", "overview"):
                desc = body_to_text(s["raw"]); break

    used_headings = {"description", "overview"}
    sections_out = []
    for s in secs:
        h = s["heading"]
        hl = h.lower()
        if hl in CHROME or hl in used_headings:
            continue
        body = body_to_text(s["raw"])
        if body:
            sections_out.append({"heading": h, "tier": tier_for(h), "body": body})

    found_at = refs_from(kv.get("location", ""), id_set, alias)
    for s in secs:
        if s["heading"].lower() == "acquisition":
            found_at += sec_link_refs(s["raw"], id_set, alias) or []
    if kv.get("obtained"):
        found_at += refs_from(kv["obtained"], id_set, alias)

    entity = {
        "id": slugify(title),
        "name": title,
        "image": clean_field(kv.get("image")),
        "description": desc or None,
        "sections": sections_out or None,
        "found_at": list(dict.fromkeys(found_at)) or None,
        "variant": None if kind == "Concept" else BUILDERS[kind](kv, secs, id_set, alias),
    }
    return prune(entity) | {"variant": entity["variant"]}  # keep variant even if None

# ── main ─────────────────────────────────────────────────────────────────────
def load_cache() -> dict | None:
    if os.path.exists(CACHE):
        with open(CACHE) as f:
            return json.load(f)
    return None

def save_cache(pages: dict):
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as f:
        json.dump(pages, f)

def load_alias_cache() -> dict | None:
    if os.path.exists(ALIAS_CACHE):
        with open(ALIAS_CACHE) as f:
            return json.load(f)
    return None

def save_alias_cache(alias: dict):
    os.makedirs(os.path.dirname(ALIAS_CACHE), exist_ok=True)
    with open(ALIAS_CACHE, "w") as f:
        json.dump(alias, f)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None, help="max pages per category (testing)")
    ap.add_argument("--refresh", action="store_true", help="ignore cache, re-crawl")
    ap.add_argument("--normalize-only", action="store_true", help="skip crawl, use cache")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    pages = None if args.refresh else load_cache()
    if pages is None and not args.normalize_only:
        visited: set[str] = set()
        all_titles: set[str] = set()
        for cat in SOURCE_CATEGORIES:
            print(f"  enumerating Category:{cat} (+subcats) ...", flush=True)
            got = list_category(cat, visited)
            all_titles |= got
            print(f"    {len(got)} pages (total {len(all_titles)})")
        titles = sorted(all_titles)
        if args.limit:
            titles = titles[:args.limit]
        print(f"  fetching content for {len(titles)} pages ...", flush=True)
        pages = fetch_pages(titles)
        save_cache(pages)
    elif pages is None:
        sys.exit("No cache found; run without --normalize-only first.")
    else:
        print(f"  using cached {len(pages)} pages")

    # redirect alias map: {redirect-title-slug -> canonical-title-slug}
    raw_alias = None if args.refresh else load_alias_cache()
    if raw_alias is None and not args.normalize_only:
        print(f"  fetching redirect aliases for {len(pages)} pages ...", flush=True)
        raw_alias = fetch_aliases(sorted(pages))
        save_alias_cache(raw_alias)
    raw_alias = raw_alias or {}
    alias = {slugify(a): slugify(c) for a, c in raw_alias.items()}
    print(f"  {len(alias)} redirect aliases loaded")

    id_set = {slugify(t) for t in pages}
    entities, by_kind = [], {}
    for page in pages.values():
        e = normalize(page, id_set, alias)
        if e is None:
            continue
        entities.append(e)
        k = e["variant"]["kind"] if e["variant"] else "Concept(nil)"
        by_kind[k] = by_kind.get(k, 0) + 1

    entities.sort(key=lambda e: e["id"])
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        json.dump(entities, f, ensure_ascii=False, indent=2)

    print(f"\n  wrote {len(entities)} entities -> {args.out}")
    for k in sorted(by_kind):
        print(f"    {k:16} {by_kind[k]}")

if __name__ == "__main__":
    main()
