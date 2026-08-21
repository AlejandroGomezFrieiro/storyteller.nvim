# Migrating to storyteller schema v1.2.0 / v1.3.0

What changed in the standard, what this plugin must do about it, and in what
order. Nothing here is implemented yet; this document is the plan.

## Background: what the standard gained

- **Axes** — timelines are now ordered dimensions. A timeline card may declare
  `unit` (display label), `origin` (numeric offset vs main), `order` (an
  explicit ordinal sequence making free-text coordinates comparable), and
  `parent` (nested frame time). `at:` joins `day:`/`time:` as the
  unit-neutral coordinate field.
- **Placements** — a scene may hold secondary placements in an `also:` list
  (`- { timeline: Past, at: 40 }`): one scene on several axes at different
  coordinates.
- **Sync anchors** — relation edges carry payloads; timeline cards relate
  through `{ to: Past, kind: syncs_with, here: 12, there: 40 }`.
- **Plotlines** — new reference type (`references/plotlines/`); scenes advance
  them via the list-valued `plotlines:` field, with an optional `stage:`
  validated against the plotline card's `stages:` sequence.
- **Events** — new reference type (`references/events/`); scenes depict shared
  events via `events:`.
- **New diagnostics** — `sync_conflict`, `stage_regression`, `orphan_plotline`,
  `uncovered_stage`, `event_conflict` (on); `timeline_gap`, `bilocation` (off
  by default).
- **Narrative modes** — the default enum grew from four to ten (`frame`,
  `simultaneous`, `time_skip`, `dream`, `mythic`, `circular` added).
- **Compilation excludes shelved work** — scenes with `status: unused` and
  whole chapters with frontmatter `status: unused` are left out of the
  compiled manuscript. Previously it was verbatim.
- **Card fields as headings (v1.3.0)** — a card field may be a
  `- **Key:** value` bullet *or* a `### Key` heading section; both forms are
  always equivalent. New types may declare `"style": "headings"` for
  new-card templates.

## Architecture finding (shapes everything below)

This plugin is **dual-path**: a thin LSP command-bus client (`lua/storyteller/
lsp.lua` — in practice only `statusCycle` uses it; `compile`/`manuscript` are
supported but bypassed by the views) sitting next to **full Lua
reimplementations** of the standard (`index.lua`, `compile.lua`,
`relations.lua`, `meta/`, and a bundled `schema.json`), plus a third parser in
the Rust `tui/`.

Nothing the plugin reads was removed in v1.2/v1.3, so nothing hard-breaks
today. The work is **parity drift** first, then **feature adoption**.

Three properties of the current tree constrain the design:

- **The meta layer does not parse flow maps.** `meta/read.lua` reads `key:`
  lists as plain strings, so an `also:` entry arrives as
  `"{ timeline: Past, at: 40 }"`. This is the right shape to keep:
  `meta/serde.lua::encode_map` writes list items with `tostring()`, so any
  flow map parsed into a Lua table would corrupt the YAML on write-back.
  Views must parse placement strings themselves (the same discipline
  `relations.lua` already applies to edge maps).
- **Everything downstream of compilation comes for free once Tier 0 lands.**
  Fountain export (`import.lua`) and every manuscript view route through
  `compile.manuscript`, so the unused-scene exclusion propagates without
  further work.
- **Two newer modules are natural adoption points**: `templates.lua`
  scaffolds story structures as chapter files (Kindling-style beats), and
  `collections.lua` filters scenes through a `key:value` query grammar. Both
  extend naturally onto v1.2 concepts (see Tier 2).

## Tier 0 — correctness parity (do first)

| # | Item | Files | Change |
| --- | --- | --- | --- |
| 1 | Bundled schema is frozen at **v1.1.0** (4 narrative modes, no `plotline`/`event` types, missing `also`/`plotlines`/`stage`/`events`/`at` and the new gates) while the server defaults to 1.3.0 — plugin-side field validation diverges from server diagnostics | `lua/storyteller/schema.json` | Replace with the canonical `crates/core/schema.json` verbatim; `schema.lua` merges it with project overrides, so this is a single-file fix |
| 2 | **Compile divergence**: the server excludes `status: unused` scenes and chapters; `strip_metadata` here is verbatim, so plugin-rendered manuscripts and word totals disagree with `storyteller.compile` on any project that shelves work. Everything downstream (`ui/views.lua`, `ui/dashboard.lua`, `commands.lua`, Fountain export in `import.lua`) inherits the fix through `compile.manuscript` | `lua/storyteller/compile.lua` (strip_metadata ~107, manuscript assembly ~184–190) | Port the exclusion into scene-range stripping; keep the `include_statuses` preset as an additional filter on top |
| 3 | TUI parses only `day` (not `at`/`time`), includes unused scenes, and sorts a single implicit axis | `tui/src/project.rs` (field parse ~101, `timeline()` ~186) | Same two fixes; add `at` fallback after `day`. (`theme.rs`/expanded `ui.rs` are presentation-only — no model coupling) |

## Reevaluated against the current tree

Verified unchanged since this plan was drafted: bundled schema still v1.1.0,
compile still verbatim, `M.timeline` still single-axis numeric, relations
still discard edge payloads, card parsing still ignores both bullets and
headings. Newer modules (`compose.lua`, `notes.lua`, `track.lua`,
`tui/src/theme.rs`) carry no project-model coupling. The plan above already
reflects the additions: flow-map handling constraints, the import/export
inheritance path, and the templates/collections adoption options.

## Tier 1 — adopt axes & placements

4. `index.lua::M.timeline` (~line 332): currently one implicit axis reading
   `day`/`time` with a global numeric sort → build **per-axis placement
   lists** (primary placement plus each `also:` flow-map), coordinate
   resolution `at` › `day` › `time`, regression flag computed per axis.
   Keep `also:` entries as opaque strings in scene meta; parse them only in
   the projection layer (see the flow-map caveat above).
5. Ordinals & offsets: reference cards already keep their full frontmatter
   (`parse_reference` → `meta`), so timeline cards' `order`/`origin`/`unit`
   are available — use them for sorting (rank) and display (`unit`).
6. `projections/timeline.lua`: the `day` column becomes a coordinate column
   (`raw`); sorting is rank-then-manuscript, grouped or tagged per axis.
   `ui/storyboard.lua::shift_day` stays numeric-only — guard it: refuse to
   shift non-numeric coordinates instead of mis-shifting silently.
7. `relations.lua::parse_relation_item`: capture extra edge attributes
   (`attrs`), and **filter `kind: syncs_with` edges out of the character
   graph** — they connect timelines, not people.

## Tier 2 — plotlines & events surfaces

8. New projection sheet: plotlines (declared `stages`, attached scenes with
   their `stage`, `unreached` stages) mirroring the server's
   `storyteller.plotlines` payload shape — shaped so it can later delegate to
   `lsp.command("storyteller.plotlines")` when a client is attached.
9. Meta form needs no structural change (it iterates live schema), but verify
   `meta/serde.encode_map` round-trips the three new list fields (`also`,
   `plotlines`, `events`) as string/scalar lists — they must stay
   table-free for the reason above.
10. Optional: surface `story_health`-style findings from the new gates
    (`stage_regression`, `orphan_plotline`, `uncovered_stage`) — or simply
    rely on server diagnostics when attached.
11. Optional — `templates.lua`: when scaffolding a beat-sheet structure,
    also emit a matching `references/plotlines/<name>.md` card whose
    `stages:` sequence is the template's beats, so scaffolded chapters land
    on a real track instead of bare chapter names.
12. Optional — `collections.lua`: extend the query grammar with
    `plotline:` / `stage:` / `timeline:` keys (they are ordinary scene-meta
    lookups once Tier 0's schema sync lands).

## Tier 3 — heading-form cards

11. `parse_reference` (`index.lua`:173) reads neither bullets nor headings
    today — nothing breaks. Adopt `fields` extraction (mirroring the core
    rules: bullets normalized, heading sections after the title, first
    occurrence wins) only if the references UI should display card data.
12. New-card templates (`templates.lua` / `references.lua` creation paths):
    honor `"style": "headings"` from the type's schema entry.

## Non-goals for this move

- Consolidating the dual path (delegating timeline/relationships/compile to
  the LSP bus when attached). Worthwhile, but a separate refactor with its own
  fallback story.
- The TUI keeping its own parser (it stays; Tier 0 item 3 keeps it honest).

## Suggested sequencing

- **Tier 0 as one commit** — pure parity, immediately testable against the
  `examples/odyssey` project from the main repo.
- Tiers 1, 2, 3 as individual commits, each updating `tests/` alongside.
