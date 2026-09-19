# tools/ — build-time data extractor

`extract.py` is the **build-time** half of the pipeline (see `docs/data-layout.md`).
It is run by Bill occasionally, **never by end users**. It pulls pages from the
Fandom MediaWiki API, normalizes them into the Entity shape, and writes one
combined JSON that the Odin program bundles via `#load`.

## Run it

```fish
uv run --python 3.11 tools/extract.py               # full crawl (uses cache if present)
uv run --python 3.11 tools/extract.py --refresh     # ignore cache, re-crawl from the wiki
uv run --python 3.11 tools/extract.py --normalize-only   # re-run normalization on cached raw pages
uv run --python 3.11 tools/extract.py --limit 200   # cap total pages (quick tests)
```

Stdlib only, so `python3 tools/extract.py` works too. Output → `data/entities.json`.

## Pipeline

1. **Enumerate** every source category (and its **subcategories**, recursively) →
   set of page titles.
2. **Fetch** each page's wikitext + categories (batched 50/request), cached to
   `tools/cache/raw_pages.json` so re-runs are offline and instant.
3. **Aliases** — fetch every page's redirects (`prop=redirects`) → a
   `redirect-title → canonical-title` map, cached to `tools/cache/aliases.json`.
   Lets `[[Malenia]]` resolve to `malenia-blade-of-miquella`.
4. **Normalize** each page → an Entity: classify the variant (by infobox template,
   then categories), parse the infobox, split & spoiler-tier sections, coerce
   numbers, resolve `[[links]]` to canonical entity slugs via the alias map (else
   literal).

`--normalize-only` re-runs step 3 alone against the cache — use this while
iterating on the normalization logic (no network).

## Output shape

A JSON array of entities matching `docs/data-layout.md`:

```jsonc
{
  "id": "moonveil",                    // page-title slug: lookup + reference key
  "name": "Moonveil",
  "image": "ER Icon weapon Moonveil.png",
  "description": "…",                  // always-shown blurb (Basic tier)
  "sections": [{"heading","tier","body"}],  // spoiler-tiered prose; tier ∈ Basic|Lore|LateGame
  "found_at": ["magma-wyrm", "gael-tunnel"],// refs: slug if resolved, else literal text
  "variant": { "kind": "Weapon", … }   // or null for lore/concept (nil variant)
}
```

`variant.kind ∈ { Character, Location, Weapon, Armor, Item }` or `null`.
References anywhere (`found_at`, `relations`, `drops`, …) are **slug-or-literal**
strings: the Odin loader looks each up in the id→index map — hit ⇒ handle, miss ⇒
literal (`docs/data-layout.md` §7a).

## Known limitations (honest list)

This is a solid first pass over deliberately dirty data, not a perfect parse.

- **Unresolved refs fall back to literal.** ~30% of references don't resolve to an
  ingested entity — genuine non-entities (races like "Numen", concepts, quantities)
  or pages outside the crawled categories. The `Ref` union's literal fallback covers
  these by design. (Redirects like `[[Malenia]]` **are** now resolved via the alias
  map from step 3.)
- **Some lead/description gaps.** Pages whose intro is built from templates can lose
  a word or link ("are Trees in."). Cosmetic.
- **Multi-variant "tabber" enemy pages** (e.g. Beastman) have messier section
  bodies — level-3 subheads and tab markers are flattened, not fully structured.
- **Multiline infobox fields** (e.g. `affiliation`, `classification`) are kept as
  `\n`-joined text, not split into lists. `affiliation` also appears both as identity
  text and as `relations.affiliation` refs (minor redundancy).
- **Item `tiers`** (stackable `[1..N]` pages) are not yet parsed into a tier table.
- Sections default to the `Lore` tier when the heading is unrecognized (spoiler-safe).

None of these break the shape — they're data-quality edges, and most illustrate
cases the Odin model already handles (literal refs, nil variants, optional fields).
