# Data layout — the Entity model

> **Status:** design spec, **all §8 decisions locked** — ready to implement.
> Language-neutral on purpose — it says *what* the data is, not *how* to declare it
> in Odin. Bill writes the Odin.
>
> **Provenance:** derived empirically from the Fandom MediaWiki API
> (`eldenring.fandom.com`). Sampled ~80 pages across every entity
> family and tabulated infobox parameters + section headings. Sample sizes noted
> per section. Re-runnable via the scripts in `scratchpad/` (`wiki_field_analysis.py`,
> `wiki_item_analysis.py`, `wiki_misc_analysis.py`, `wiki_catfield.py`).

---

## 0. The shape in one breath

Every searchable thing is an **Entity**. An Entity has a **shared spine** (fields
present on *everything*) plus **one variant** of type-specific data held in a
**tagged union**. The variant that's active *is* the entity's kind — there's no
separate "kind" field; the union tag carries it.

```
Entity = shared spine  +  (optionally) one of:
           CharacterData | LocationData              (world entities)
           WeaponData | ArmorData | ItemData          (items)
           — or NO variant (nil): a pure lore/concept page (§8.2)
```

Five variants total, **plus the nil case** — an Odin union is nil-able by default,
so a spine-only lore/concept entity (e.g. "Blackflame") needs no special variant;
its union is simply `nil`. The split into "world" vs "items" mirrors how the wiki itself
organizes its infobox templates. **Bosses and NPCs are one variant** (`CharacterData`)
— the wiki stores both on a shared `Infobox Character` template, so "boss" vs "NPC"
is not a type but a **facet** of a character (see §4a).

---

## 1. Field-type vocabulary (used throughout)

| Notation | Meaning |
|---|---|
| `text` | a string (may be multi-paragraph for prose) |
| `text[]` | list of strings |
| `number` | numeric; **beware** the wiki stores some as strings (`"???"`, `"2200"`), but this needs to be normalized |
| `enum` | one of a fixed, known value set (defined per variant below) |
| `ref` | a reference to *another Entity* (by stable id — see §7) |
| `ref[]` | list of entity references |
| `bool` | true/false |
| *(opt)* | may be absent/empty; renderer must tolerate missing |

---

## 2. The shared spine (on every Entity)

Evidence: `name` is never an infobox field — it's the **page title**, so it's the
one truly universal field and it comes from page metadata, not the infobox.
`image` and `type` appear on every infobox. The prose fields are normalized from
differently-named sections (see §6).

| Field | Concept | Source | Notes |
|---|---|---|---|
| `id` | `text` | slug of page title | stable key for lookup **and** for references (§7) |
| `name` | `text` | **page title** | display name, e.g. "Mohg, Lord of Blood" |
| `image` | `text` *(opt)* | infobox `image=` | filename/URL of the card image |
| `description` | `text` *(opt)* | normalized (§6) | the one distinguished **always-shown** blurb (implicitly `Basic` tier) |
| `sections` | `Section[]` *(opt)* | all other prose | tagged, spoiler-tiered prose — see §2a |
| `found_at` | `ref[]` *(opt)* | `location=` / `== Acquisition ==` | where to encounter/acquire (§7) |

Everything else lives in the variant.

### 2a. Prose & spoiler tiers (RESOLVED, §8.4)

Prose is **not** a fixed set of fields (`notes`/`trivia`/…). Apart from the one
distinguished `description`, all prose is a **list of tagged sections**:

```
Section = { heading: text, tier: SpoilerTier, body: text }
SpoilerTier :: enum { Basic, Lore, LateGame }   // extensible; start with Basic/Lore
```

- **Why a list, not fields:** it does double duty — (1) **spoiler-gating** is just
  "render sections where `tier ≤ allowed`"; (2) it captures the **long-tail
  sections** (`Characteristics`, `The Night of Black Knives`, …) generically
  instead of needing a named field each. Solves the "pull everything, discard
  chrome" problem from §6b at the same time.
- **Tier is assigned by section name** in the normalizer (§6b): `Description`,
  stats, `Acquisition` → `Basic`; `Background`, `Game Events`, `Questline
  Progression`, `Dialogue` → `Lore`/`LateGame`. (`Category:Lore` is a page-level
  hint only, too coarse to tier a chunk.)
- **Chrome is still discarded, never stored** (`Gallery`, `References`, …).

---

## 3. Type tagging — how a page becomes a variant

The variant is **derived from the page's Fandom categories** (`prop=categories`),
*not* from the infobox template alone (templates are aliased and many-to-one).

- `Category:Bosses` **or** `Characters` **or** `NPCs` → `CharacterData`
  (which facets it gets is decided *within* the variant — see below)
- `Category:Locations` (+ Region/Legacy Dungeon/Subregion) → `LocationData`
- item templates → item variants, refined by the infobox `type=` value (§5)

**The Boss/NPC overlap is dissolved, not prioritized.** Margit ∈ Bosses *and*
Characters *and* Demigods — all map to the *same* `CharacterData`. Category
membership then decides which **facets** to populate:

- in `Category:Bosses` (or has combat infobox fields) → attach the **combat facet**
- has a `== Questline ==` / merchant role → attach the **quest facet**

So a character can carry both facets at once (Blaidd), and no data is lost to a
precedence tiebreak. The only residual precedence is the rare cross-family case
(a page that is somehow both a Character and a Location); default order:
`Location > Character > items`.

---

## 4. World variants

Evidence: 14 bosses, 11 NPCs, 10 locations. Infobox fields diverge sharply by
type (this is *why* a union is needed); prose sections are largely shared and get
folded into the spine (§6).

### 4a. `CharacterData`  (NPCs, demigods, **and** bosses/monsters — one variant)
Any named being. "Boss" and "NPC" are not separate types — they are **optional
facets** attached based on category/fields (§3). A character may have neither, one,
or both. Godfrey = combat only; Kalé = quest only; Blaidd = both; Fire Giant =
combat only, no identity/dialogue (the degenerate "pure monster" case).

**Identity (on the character directly):**
| Field | Concept | Notes |
|---|---|---|
| `title` | `text` *(opt)* | epithet, e.g. "The Fell Omen" |
| `aka` | `text[]` *(opt)* | also-known-as |
| `role` | `text` *(opt)* | "Merchant", "Blacksmith" |
| `race` / `affiliation` / `classification` | `text` *(opt)* | infobox identity fields |
| `voice` | `text` *(opt)* | voice actor |
| `relations` | reference cluster | the genealogy web (§7) |

**Combat facet** *(opt sub-struct — present iff fightable; this *is* "boss-ness")*:
| Field | Concept | Notes |
|---|---|---|
| `hp` | `number` *(opt)* | number-or-absent (§6b) |
| `poise` | `number` *(opt)* | |
| `resistances` | struct *(opt)* | `res_*`: standard/slash/strike/pierce + magic/fire/lightning/holy + poison/rot/bleed/frost/sleep/madness/death |
| `weaknesses` | `text[]` *(opt)* | `weakness=`, `weak spot=` |
| `phases` | `number` *(opt)* | multi-phase fight count |
| `moveset` | `text[]` *(opt)* | `== Boss Fight ==` / `== Moveset ==` |
| `drops` | `ref[]` *(opt)* | items awarded (§7) |
| `runes` | `number` *(opt)* | rune reward |
| `stats` | struct *(opt)* | RPG line `str/dex/int/fai/arc/vig/mnd/end`, `class` |

**Quest facet** *(opt sub-struct — present iff the character has NPC content)*:
| Field | Concept | Notes |
|---|---|---|
| `questline` | `text[]` *(opt)* | `== Questline Progression ==` |
| `shop` | `ref[]` *(opt)* | `== Shop Inventory ==` items (§7) |

> The two facets being *optional sub-structures* (may be absent) is exactly the
> nil/optionality question of §8.2 — resolve them together.

> **Quests are NOT a separate entity/variant.** The wiki has no `Category:Quests`
> and no standalone quest pages — a quest lives as sections (`== <NPC>'s Quest ==`,
> `== Questline Progression ==`) *inside the quest-giver's page*, captured by the
> quest facet's `questline`. Quests are cross-cutting (Ranni's involves
> Blaidd/Iji/Seluvis + locations), but the canonical text sits on one page.
> Synthesizing a standalone `Quest` entity for direct `eldr <quest>` lookup is a
> possible v2 derived-entity step, not something the source provides.

### 4b. `LocationData`
| Field | Concept | Notes |
|---|---|---|
| `region` | `ref` *(opt)* | parent region (§7) |
| `sub_regions` | `ref[]` *(opt)* | child areas |
| `graces` | `text[]` *(opt)* | sites of grace |
| `is_legacy_dungeon` | `bool` *(opt)* | from template variant / `legacy-dungeon=` |
| `is_optional` | `bool` *(opt)* | `optional=` |
| `map_fragment` | `text` *(opt)* | |
| `bosses` | `ref[]` *(opt)* | bosses found here (§7) |
| `npcs` | `ref[]` *(opt)* | NPCs found here (§7) |
| `notable_loot` | `ref[]` *(opt)* | `== Notable Loot ==` (§7) |

---

## 5. Item variants

Evidence: 5 weapons, 4 shields, 4 armor, plus ashes/talismans/pots/spells/spells
and ~13 misc items. The wiki uses **exactly three item templates**, and the
`type=` field is the **fine discriminator** — *per family*, with its own vocabulary.

### 5a. `WeaponData`  (template `Infobox Weapon` — **weapons + shields**)
| Field | Concept | Notes |
|---|---|---|
| `class` | `enum WeaponClass` | from `type=` — see §6a for values |
| `attack_type` | `enum` *(opt)* | `Standard / Slash / Pierce` — a **second** axis, don't conflate with `class` |
| `weight` | `number` | |
| `attack` | struct | `physical/magic/fire/lightning/holy_power` |
| `guard` | struct | `*_guarded`, `guard_boost` (shields lean on these) |
| `scaling` | struct | `str/dex/int/fai/arc_scale` (grades A–E) |
| `requirements` | struct | `str/dex/int/fai/arc_req` |
| `skill` | `text` *(opt)* | `skills=` (Ash of War equipped) |
| `crit` | `number` *(opt)* | `critical=` |
| `passive_effects` | `text[]` *(opt)* | `effects=` (bleed, frost, …) |

> Shields share this variant; `class` distinguishes them (§6a).

### 5b. `ArmorData`  (template `Infobox Armor`)
| Field | Concept | Notes |
|---|---|---|
| `slot` | `enum ArmorSlot` | from `type=` — `Head / Body / Arms / Legs` |
| `weight` | `number` | |
| `defense` | struct | `physical/magic/fire/lightning/holy` |
| `resistance` | struct | `vs_slash/strike/pierce`, `immunity`, `robustness`, `focus`, `vitality`, `poise` |
| `has_altered` | `bool` *(opt)* | `altered=` (cloth-stripped variant exists) |
| `passive_effects` | `text[]` *(opt)* | `effects=` |

### 5c. `ItemData`  (template `Infobox_Item` — the catch-all)
Everything not a weapon/shield/armor. Distinguished by a `category` enum.

| Field | Concept | Notes |
|---|---|---|
| `category` | `enum ItemCategory` | from `type=` — see §6a |
| `effect` | `text` *(opt)* | `item_effect=` |
| `fp_cost` | `number` *(opt)* | spells, some tools |
| `slots_used` | `number` *(opt)* | spells |
| `spell_reqs` | struct *(opt)* | `int/fai/arc_req` for spells |
| `weight` | `number` *(opt)* | talismans |
| `required_items` | `ref[]` *(opt)* | crafting inputs (pots) |
| `buy_price` / `sell_price` | `number` *(opt)* | |
| `tiers` | `Tier[]` *(opt)* | stackable/combined pages (§8.6): `Tier = {label, detail}`, e.g. Golden Rune `[1..20]`, Smithing Stone `[1..8]` |

> **Bare-spine case (RESOLVED, §8.2):** a Key Item (Stonesword Key, Dectus
> Medallion) has almost no payload — but it *is* an item, so it stays a **thin
> `ItemData`** (`category = KeyItem` + `description`), *not* a nil variant. The nil
> variant is reserved for genuine non-{character,location,item} concept/lore pages
> (§0, §2).

---

## 6. The category enums (from the wiki's `type=` values)

**Per-variant, not global.** Each variant's discriminator is its own value set.
The wiki's raw strings are dirty (casing, spacing) — the normalizer maps them to
clean members (§6b).

### 6a. Value sets
- **`WeaponClass`** (~30): Dagger, Straight Sword, Greatsword, Colossal Sword,
  Thrusting Sword, Heavy Thrusting Sword, Curved Sword, Curved Greatsword, Katana,
  Twinblade, Axe, Greataxe, Hammer, Great Hammer, Flail, Spear, Great Spear,
  Halberd, Reaper, Whip, Fist, Claw, Colossal Weapon, Light Bow, Bow, Greatbow,
  Crossbow, Ballista, Glintstone Staff, Sacred Seal, Torch, **Small/Medium/Greatshield** (shields).
- **`ArmorSlot`** (4): Head, Body, Arms, Legs.
- **`ItemCategory`**: Tool, Talisman, Key Item, Bolstering Material, Spirit Ash,
  Ash of War, Sorcery, Incantation, Crafting Material, Consumable, Cookbook,
  Info Item, Great Rune, Ammunition. *(extend as the extractor discovers more)*
- **`SpoilerTier`** (§2a, §8.4): Basic, Lore, LateGame. Cross-cutting — tags each
  `Section` and the `relations` cluster; the renderer filters by threshold.

### 6b. Normalizer canonicalization duties (observed in raw data)
- **Numbers must become numbers, not strings.** The wiki stores numerics as text,
  often decorated: `"6.5"` (weight), `"13,000 Runes"` (drops/runes), `"2200"` (hp).
  The extractor strips units/commas/markup and emits a real JSON number, so the Odin
  side never parses digits out of prose. **Caveat (ties to §8.5):** some values are
  genuinely non-numeric — boss `hp` is sometimes `"???"`. So a "numeric" field is
  really *number-or-absent*: coerce when it's a number, else drop to empty/optional
  (never store the literal `"???"`). The renderer then shows a placeholder for
  unknowns. This keeps the model's number fields honest — the emitted JSON either
  has a number or omits the field.
- **Casing drift:** `tool`→`Tool`, `head`→`Head`, `Legs`/`arms` mixed.
- **Section-name unification (prose → spine `description`):**
  `Overview` / `Background` (world) **and** `Description` (items) all → `description`.
  `Acquisition` (items) / `location=` (world) → `found_at`.
- **Chrome to discard, never model:** `Gallery`, `References`, `Navigation`,
  `See Also`, disambiguation headers.
- **Polluted values:** HTML comments bleed into fields (`Infobox Item <!-- ... -->`).
- **Combined/stackable pages (RESOLVED, §8.6):** `Golden Rune [1]`, `Smithing
  Stone [1]` aren't standalone pages — one wiki page covers all tiers. **One entity
  per page**, with the per-tier data in `ItemData.tiers` (§5c) — *not* fanned into N
  entities. Tiered references (`[[Smithing Stone [3]]]`) strip the `[N]` suffix and
  resolve to the base entity's handle, else fall back to literal via `Ref` (§7a).

---

## 7. References — the relationship web

Many fields point at *other entities*, not scalars. Evidence: boss genealogy
(`relatives, parents, siblings, children, descendants, ancestors, predecessors,
successors, partners, allegiance`), `drops`, location `bosses`/`npcs`, NPC `shop`.

**In the JSON, a reference is another Entity's `id`** (page-title slug — unique,
one page per title, so `id → entity` is strictly 1:1: no name-collision ambiguity).

- **`relations`** (characters): a small named set of `ref[]` — parents, siblings,
  children, allies, etc. Consider a single "relations" structure rather than a
  dozen fields. **Spoiler-gated (§8.4):** genealogy reveals *are* the plot twists,
  so `relations` carries a `SpoilerTier` (§2a) and is hidden as a group below the
  spoiler threshold — the one structured (non-prose) field that gets tiered.
- **`drops` / `notable_loot` / `shop` / `required_items`**: `ref[]` to items.
- **`region` / `sub_regions` / `bosses` / `npcs`**: `ref` / `ref[]` for geography.

### 7a. Runtime form (RESOLVED, §8.3): resolved handles + a ref-or-literal union

Chosen: **array-index handles**, resolved once at load (the low-level exercise),
**not** id-strings or pointers (pointers dangle on array realloc).

- **Two-pass load.** Pass 1: create every entity, build an `id → index` map.
  Pass 2: replace each reference's id with its `int` index (handle).
- **Many-to-one is fine.** Ten characters dropping the same item just hold the
  same handle — an index is a plain int, shared freely.
- **A reference isn't always an entity.** A `drops` value may be a literal
  ("5000 Runes") or a dangling `[[link]]` to an un-ingested page. So a reference
  element is modeled as a **union**: `Ref :: union { EntityHandle, string }` —
  a resolved handle *or* literal text (so the card still prints something).
- **Split known literals into typed fields first.** "5000 Runes" is not a
  reference — the normalizer routes rune amounts to the combat facet's
  `runes: number`, leaving `drops` to genuine item references.
- **Resolver signal = wiki `[[links]]`.** In raw wikitext, real references are
  `[[Target]]` (link target = exact page title = unique id); unlinked text is a
  literal. Pass 2 resolves linked → handle (dangling link → literal fallback),
  unlinked → literal/typed field.

---

## 8. Open decisions (Bill's calls, still to lock)

1. ✅ **RESOLVED — Boss/NPC merged into `CharacterData` with optional facets.**
   Chose "Character with facets" (Option B) over a precedence order: bosses & NPCs
   share the wiki's `Infobox Character`, so "boss" and "NPC" are optional *facets*
   (combat / quest), not separate variants. Overlap dissolves; no data lost. Monsters
   (Fire Giant) = combat-facet-only characters. Union is now 5 variants. Residual
   cross-family precedence `Location > Character > items` (§3). See §4a.
2. ✅ **RESOLVED — nil variant for concept/lore pages; Key Items stay thin `ItemData`.**
   Odin unions are nil-able by default, so a spine-only lore/concept page (e.g.
   "Blackflame") is just an Entity with a `nil` variant — no `EmptyData` invented.
   Concept/lore pages **are in scope**. Key Items remain `ItemData` (`category =
   KeyItem`). Optional facets/fields use `Maybe(T)`. Rule: *nil = not a
   character/place/thing, just a concept.*
3. ✅ **RESOLVED — array-index handles (2-pass load) + `Ref :: union{EntityHandle, string}`.**
   Chose handles as the low-level exercise (not id-strings/pointers). References
   resolve id→index at load; unresolved/literal values fall back to text via the
   union; known literals (runes) split into typed fields. Resolver keys off wiki
   `[[links]]`. See §7a.
4. ✅ **RESOLVED — tagged section list + `SpoilerTier` enum.** Prose (beyond the
   always-shown `description`) is `Section[]` where `Section = {heading, tier, body}`
   and `SpoilerTier :: enum{Basic, Lore, LateGame}` (extensible). Tier assigned by
   **section name** in the normalizer (not `Category:Lore`, too coarse). Gating =
   filter `tier ≤ allowed`; also captures long-tail sections generically.
   **`relations` is spoiler-gated too** (genealogy = plot twists). See §2a, §7.
5. ✅ **RESOLVED — Number-or-string fields.** A numeric field is *number-or-absent*:
   the extractor coerces real numbers (stripping commas/units/markup) and **omits**
   the field when the source is non-numeric (`"???"`). The literal `"???"` never
   enters the model; the renderer shows a placeholder for missing values. (See §6b.)
6. ✅ **RESOLVED — one entity per page + `ItemData.tiers`** (not fanned into N).
   Matches the source and the query; tiered refs strip `[N]` → base handle, else
   literal. See §5c, §6b, §7a.
7. ✅ **RESOLVED — one combined JSON, embedded via `#load`, parsed at startup.**
   Single file (the CLI loads everything every run anyway); baked into the binary
   with `#load` for a self-contained executable. Per-invocation startup parse is
   trivial at this scale. Packed zero-parse blob deferred as a v2 optimization —
   made *easy* by the handle choice (§3): indices serialize position-independently,
   pointers wouldn't. *(Delivery half defaulted to `#load`; revisit if shipping the
   JSON beside the binary is preferred.)*

---

## 9. What the evidence does *not* cover (limits)

- Sampled ~80 of thousands of pages — the **long tail** (unique one-off sections,
  rare templates) will surface more edge cases during real extraction.
- DLC (Shadow of the Erdtree) pages included in spirit but not exhaustively sampled.
- Multiplayer/ammo/cookbook/gesture minor types only lightly touched — folded into
  `ItemData` categories for now; revisit if any needs its own stat block.
```
