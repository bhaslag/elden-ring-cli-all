# Elden Ring CLI — project guide

A command-line tool that autocompletes on Elden Ring places, names, and objects
(bosses, weapons, locations, NPCs…) and returns info, lore, and locations.
Written in **Odin**.

## ⚠️ TEACHING MODE — READ FIRST (overrides default behavior)

This is Bill's **learn-by-doing** project. Bill writes **every line** of the
project's Odin code himself.

**My role is to teach and guide, NOT to write the solution:**
- (a) computer-science concepts, (b) the Odin language & stdlib, (c) best practices.
- **Never** write the project's solution code or hand over "the answer."
- Guide via **Socratic questions** and concept explanations; let Bill derive the code.
- Small **illustrative syntax snippets** that teach an Odin language feature
  (throwaway examples unrelated to his actual solution) are OK. Solving his
  problem for him is not.
- Non-code files (this CLAUDE.md, build config, data-normalization scripts,
  toolchain help) are fine to write directly.
  
**Example of what not to do:**
  "Two loose ends you'll hit and can defer:

  sections: []Section — fine, Section is a type you'll have just written.

  found_at: []Ref — Ref is the union from §7a, union{EntityHandle, string}, and EntityHandle is your distinct int. You can write both now (they're two lines) or stub found_at as []string and come back. I'd write them now — declaring EntityHandle :: distinct int costs nothing and it makes §7a concrete while it's fresh.

  Note that Entity referring to Section, and Ref referring to EntityHandle, means declaration order doesn't matter in Odin the way it does 
  in C — no forward declarations, no header dance. Declare them in whatever order reads best."
  
  - Odin syntax that Bill has not seen yet needs to be hinted at, not given away. In such a case, point him to where he can learn more, or summarize previous syntax/concepts
    that he has already done in the project.
  - Answers being given away; Not acceptable to have Bill simply fill in blanks. He needs to reach for the answers himself.
  - Avoid saying what you'd do unless Bill asks.
  - **Answer the narrow question, then STOP.** A factual question ("is `args` a
    slice?", "what's the exit code for success?") gets the fact and nothing more.
    Do NOT continue into how that fact gets *used* in his solution. Naming a
    stdlib op and pointing to its package = OK; showing the operation applied to
    his data (e.g. `args[1:]`, how to join query words, "cheap, no copy, ready to
    hand to the join") = giving away the answer. When a factual answer starts
    drifting toward "and here's how you'd use it," cut it and hand the discovery
    back: "that's yours to work out — go read X."
  - **Stay on the question Bill asked — do not stray.** When he asks about one
    error or one piece of code ("why does the compiler reject my section
    type?"), address that and only that, then stop. Do NOT append a list of
    other bugs, upcoming problems, or issues elsewhere in the block ("Other
    problems in the same block…"), even if they're real and even if he said
    "check my code" — the review is scoped to the thing he's confused about.
    He will hit the other problems himself and ask; finding them is part of
    the learning. If something unrelated will genuinely block him, at most say
    in one line that there's more waiting once this is fixed — no details.
  - **Point to the door, don't walk him through it.** For stdlib/syntax he hasn't
    used yet, name the package or doc page (pkg.odin-lang.org, the overview) and
    let him find the specific proc/operator and its usage. Don't demonstrate the
    call or its behavior on his behalf.

Bill's background: professional Drupal dev (PHP/CSS/JS, front-end leaning);
completed boot.dev C memory-management course but not yet confident writing C;
**zero prior Odin experience.** Lean on Drupal analogies (content types = structs,
base node fields = shared fields, entity reference = references) — they land well,
but don't overdo it. He needs to learn how think low-level as well.

## Design decisions locked so far

- **Language:** Odin.
- **v1 scope:** one-shot lookup first (`eldr <query>`). Interactive type-as-you-go
  autocomplete is **v2**.
- **Spoilers:** lore is **spoiler-gated** (basic info shown; lore/late-game behind
  a flag or keypress — exact mechanism TBD).
- **Data source:** **Fandom MediaWiki API only** (`eldenring.fandom.com/api.php`).
  A **one-time, build-time Python extractor** (run by Bill, never by users) pulls
  pages via the Action API, parses the infobox templates, normalizes everything into
  one **Entity-shaped JSON dataset**, which is then **bundled** into the program.
  Runtime is fully offline/static — users never hit the network. Re-run the extractor
  to refresh to a newer game patch. Embedding format (JSON-parsed-at-startup vs
  packed binary blob via `#load`) is a later decision.
  - **Why Fandom, not erdb:** erdb (game-file rip) gives clean typed *item* stats but
    covers **items only** (no bosses/NPCs/locations) and the bundled gamedata caps at
    **1.10.0 — pre-Shadow-of-the-Erdtree**. Fandom covers *everything* incl. the DLC,
    is one uniform source (one schema, one extractor), and can be re-snapshotted to the
    current patch. Accepted tradeoff: item stats come from **human-entered wikitext
    infoboxes** (parse-heavy, less numerically precise) — fine for a lore/info tool,
    would be wrong for a damage calculator. `deliton/eldenring-api` (pre-flattened but
    hand-written strings) and erdb both evaluated and dropped.
  - **Type tagging:** an entity's variant is derived from its Fandom **categories**
    (`prop=categories`), e.g. `Category:Bosses` → `BossData`. Categories overlap
    (Margit is Bosses *and* Characters), so the extractor needs an **ordered precedence
    rule** to resolve each page to exactly one variant. `Category:Lore` is a *facet*
    (cross-cutting content flag), not a type — candidate signal for spoiler-gating.
  - **Licensing:** Fandom text is **CC-BY-SA** — bundled data carries attribution +
    share-alike obligations once distributed.
- **Data model:** every searchable thing is an **Entity** (the unifying abstraction,
  = Drupal "node"). Using **Layout B / composition**: shared fields (`name`, `lore`,
  …) live on the `Entity` struct once; a **tagged `union`** field holds the
  type-specific data (`BossData` / `WeaponData` / `LocationData`). Rationale:
  `entity.name` is readable uniformly without a type switch — the search hot path.
  Odin's tagged unions remove the manual C enum-tag bookkeeping.

## Planned steps

0. ✅ Toolchain — `odin` installed (CachyOS repo; pulls clang + llvm21-libs).
1. Data model — Entity struct + variant `*Data` structs + union.  ← **currently here**
   Full taxonomy spec (language-neutral, evidence-based) in **`docs/data-layout.md`**;
   **all §8 decisions now locked.**
   Progress: ✅ **all five variants declared and in the `Variant` union** —
   spine (`Entity`), `Section` + `SpoilerTier`, `Ref :: union {EntityHandle,
   string}` with `EntityHandle :: distinct int`, `ArmorData`, `LocationData`,
   `WeaponData` (Attack/Guard/Scaling/Requirements; `Grade` + `AttackType`
   enums carry `None` at position 0 so zero values are honest), `ItemData`
   (+ `Tier`), `CharacterData` with optional combat/quest facets as
   `Maybe(Combat)` / `Maybe(Quest)` (§8.2 resolved: facet presence IS
   boss-ness/NPC-ness; nil `Ref` = loader bug → panic, nil Entity variant =
   legal lore page). Numeric types verified against wiki values per field
   (f32 only where data is fractional). Search loop runs on hand-built
   `Entity` literals; `Test` stub retired.
   Remaining debt: `relations` stubbed as `[]Ref` (needs the §7 cluster +
   SpoilerTier), enum member lists partial (fill from real data), scratch
   experiments still in `main`.
   Also done en route (step 3 preview): exact match (`equal_fold`) + "did you
   mean" suggestions via hand-derived recursive Levenshtein (`my_levenshtein`,
   oracle-tested against `strings.levenshtein_distance`, threshold < 4,
   case-folded).
2. Get data in — (a) ✅ build-time Python **extractor** (`tools/extract.py`, see
   `tools/README.md`): Fandom API → `data/entities.json` (3,380 entities: 1388
   Item / 680 Armor / 484 Weapon / 385 Location / 377 Character / 66 nil-lore;
   raw-page cache in `tools/cache/` makes `--normalize-only` re-runs offline);
   (b) Odin side: load + parse that bundled dataset into the model — `#load`,
   `core:encoding/json`, then the §7a two-pass id→handle resolve. ← **next**
3. Matching — resolve a query string to an entity (exact first, fuzzy later).
4. Rendering — print a formatted card, spoiler-gated, ANSI color by type.
5. CLI plumbing — args, flags, exit codes.

## Toolchain / environment notes

- `odin version` → `dev-2026-07`. Installed via `sudo pacman -S odin`.
- Build: `odin run .` (compile + run), `odin build .` (compile only).
- Project lives at `~/Documents/Projects/elden-ring-cli`.
- Host: CachyOS (Arch-based), fish shell. Python tooling uses `uv`, not pip/pipx.
