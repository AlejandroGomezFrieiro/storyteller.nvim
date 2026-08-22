# Joint Rework Plan — storyteller.nvim + storyteller-tui on schema v1.3

> Status: **complete (0.4.0)**. All phases A–I landed; nothing deferred.
> See `PROGRESS.md` "Schema 1.2/1.3 rework" for the closing summary and
> `docs/interaction.md` / `docs/projections.md` for the contracts as built.
> Supersedes the deferred lane sketched in `docs/tui-visual-plan.md` §5–§14
> header and the tiered `MIGRATION.md` (now a pointer). Nothing is parked:
> every previously deferred item has a phase below. We are building toward a final version meant to keep.

The standard (storyteller schema v1.2.0/v1.3.0) generalized timelines into
axes (`unit`/`order`/`origin`/`parent`, `at:` coordinates), added secondary
placements (`also:`), sync anchors (`syncs_with` edges with payloads),
plotline cards with declared `stages:`, events, seven new diagnostics, ten
narrative modes, unused-scene compile exclusion, and heading-form card
fields equal to bullets. This plan migrates both frontends onto it and
completes every interactive surface the visual plan sketched.

## Locked design decisions

1. **storyteller-core as a git dependency** of the TUI. Placement,
   ordinal-rank, and sync-projection resolution stay single-sourced with the
   standard (conformance-pinned). The standard repo gets a `v1.3.0` tag to
   pin against.
2. **Axes land now.** The old note that Timeline's `t` key "dims until
   timeline cards land" is obsolete — Tier-A schema sync makes them real;
   the TUI renders axes from day one.
3. **Unified Plotlines tab.** Plotline-card lanes are primary; projects with
   no cards degrade to the setup/payoff threads view unchanged; `v` toggles
   modes explicitly; `p` toggles a read-only plot grid.
4. **Full staged editing** through one `store.rs` engine serving Timeline,
   Relations, and Plotlines alike.
5. **Placement strings stay opaque through round-trips.** `meta/read.lua`
   does not parse flow maps and `meta/serde.lua::encode_map` writes list
   items with `tostring()`; parsing `{ timeline: Past, at: 40 }` into tables
   would corrupt YAML on write-back. Views parse placement strings; meta
   stores them verbatim (the same discipline `relations.lua` applies).

## The staged-edit engine (`store.rs`)

```rust
enum Op {
    SetField { scene: SceneRef, key: String, value: Option<String> },
    // Generalizes the old SetDay sugar: rewrites whichever of at:/day:/time:
    // holds the coordinate (default day); None clears scheduling.
    SetCoord { scene: SceneRef, coord: Option<String> },
    // One also: entry, written as a flow-map string.
    AddPlacement { scene: SceneRef, axis: String, coord: String },
    RemovePlacement { scene: SceneRef, axis: String },
    // Sugar for SetField("stage").
    SetStage { scene: SceneRef, stage: Option<String> },
    AttachPlotline { scene: SceneRef, name: String },
    DetachPlotline { scene: SceneRef, name: String },
    // Add/remove one setup:/payoff: item — never whole-value SetField,
    // which would clobber sibling entries.
    AttachThread { scene: SceneRef, side: Side, key: String },
    DetachThread { scene: SceneRef, side: Side, key: String },
    AddEdge { card: CardRef, to: String, kind: String },
    RemoveEdge { card: CardRef, to: String },
    RenameEdge { card: CardRef, to: String, kind: String },
}
```

### Write semantics

- **Scene fields**: locate `## <title>` → ` ```yaml ` fence → replace,
  insert, or remove the single `key:` line. Unknown lines, comments, and
  prose untouched byte-for-byte. Removal uses nil semantics (matching the
  Lua `vim.NIL` fix).
- **Item-list ops** mutate exactly one entry of a YAML list.
- **Edges**: port `relations.lua::add_edge/remove_edge` line-surgery.
  Removal matches by `to:` regardless of syntax (flow/block/shorthand);
  new edges append block-map form. One documented exception: renaming the
  kind of a shorthand entry (`- spouse: X`) converts it to block-map form —
  shorthand encodes the kind as its key, so preservation is impossible.
- **Atomicity**: group ops by file → transform every affected file fully in
  memory → only then write each via temp-file + rename. A transform failure
  aborts before any disk write; a disk-level failure across files degrades
  to snapshot recovery, so a git snapshot always precedes multi-file
  applies (existing `storyteller:snapshot` convention).
- **Stale guard**: fingerprint = sorted `(path, mtime_ns, size)` over project
  `*.md`; re-stat immediately before apply; mismatch aborts with
  "files changed — R to reload" and clears nothing.
- **Staging UX**: every keystroke stages an op; footer gains right-aligned
  `N pending · S apply` in the warning slot; `u`/`Esc` drops staging
  (confirm when non-empty); `R` confirms when pending.

## Phase A — Parity (plugin Tier 0)

| Stage | Work | Files |
| --- | --- | --- |
| A1 | Replace bundled schema (frozen v1.1.0) with canonical v1.3.0 verbatim | `lua/storyteller/schema.json` |
| A2 | Compile excludes `status: unused` scenes and whole chapters; Fountain export and all views inherit via `compile.manuscript` | `lua/storyteller/compile.lua` |
| A3 | TUI parser parity: `at`/`time` coordinate fallback, unused exclusion, word totals | `tui/src/project.rs` |
| A4 | Verify `meta/serde.encode_map` round-trips `also`/`plotlines`/`events` as scalar/string lists | `lua/storyteller/meta/serde.lua` |

## Phase B — Contracts & fixtures

- B1 `docs/interaction.md`: verb-scoping line (`a` = add on Relations /
  Plotlines surfaces, matching how the grammar scopes verbs); TUI-added
  keys documented: `t` axis cycle, `o` reading/story order, `w` swimlanes,
  `s` swap marked rows, `v` lanes/threads mode, `p` plot grid.
- B2 `docs/projections.md`: timeline projection gains axis + coordinate
  columns (rank-aware); the **plotlines projection format is specified**
  (previously a §13 "planned" note): lanes with stage pills, shared-scene
  markers, unreached-stage ghosts — shared between frontends.
- B3 Shared fixture schema under `tests/projections/`:
  `{ name, files, ops, expect }` JSON; expectations captured once from the
  Lua engine (the reference implementation), then asserted identically by
  `cargo test` — render/apply byte-parity pinned across frontends.

## Phase C — store.rs implementation

- C1 All ops + surgical writes per the semantics above (including placement
  flow-map strings and the shorthand-rename exception).
- C2 Atomicity, stale guard, git snapshot integration.
- C3 Tests: golden Lua parity, atomicity (failing op leaves files
  untouched), stale-guard abort, relation-syntax round-trips (all three
  forms), placement round-trips (opaque strings in, identical bytes out).

## Phase D — Staging UX wiring

Footer segment; `S` apply / `u` drop flows; `?` grammar overlay via popups.
Dependencies per visual-plan §3.1: `tui-popup`, `tui-prompts` (isolated
behind the modal layer, swappable).

## Phase E — TUI model & Timeline v2

### E1 Model extension (`project.rs`)

Per-scene placements (`at`/`day`/`time` + parsed `also:` flow-maps →
`Vec<Placement>`); timeline cards (`unit`/`order`/`origin`/`parent`,
`syncs_with` edges with payloads); plotline cards (`stages:`, `arc_of`);
event counts; `narrative_mode`; relations edges + attrs; mention counts
from chapter-prose scans; thread grouping data.

### E2 Core dependency

`tui/Cargo.toml` git-dep on storyteller-core @ v1.3.0 tag; `Axes::collect`
feeds axis metadata + rank/projection to all views.

### E3 Timeline read-only v2

```
 ╭─ Timeline · Present · days · story order ──────────────────────────╮
 │ ▌  12  The crossing        Odysseus    412 w                       │
 │ ▒  ~40  The omen           Athena       95 w   ← also: Past       │
 │     ·   Unplaced draft     —            30 w                       │
```

- `t` cycles axes (`main` + each card; header shows the card's `unit`);
  `o` toggles Reading order ⇄ Story order (both first-class);
  `w` cycles swimlane grouping off / pov / location / chapter.
- Rows sort by coordinate rank (numeric, or ordinal position in the axis's
  `order:` list) then manuscript; unplaced rows sort last with `·`.
- Warning tints, recomputed locally after each stage: per-axis regression
  among linear-mode scenes, same-coordinate overlap, intra-scene
  `sync_conflict` (primary projected via anchors/origins ≠ a secondary
  placement). Non-linear narrative modes get a dim `~` badge and are
  exempt from ordering checks.
- Responsive: day separators ≥80 cols; compact <50 hides pov/words.

### E4 Staged retiming & placement editing

| Key | Action |
| --- | --- |
| `h` / `l` | Stage coordinate −1 / +1 (numeric); ordinal coords **cycle** the axis's `order:` list |
| `H` / `L` | Absolute coordinate prompt (numeric input; picker when ordinal) |
| `d` | Clear scheduling (`SetCoord(None)`) |
| `s` | Mark two rows, swap their coordinates |
| `a` | Add a secondary placement: axis picker → coordinate prompt (`AddPlacement`) |
| `x` | Remove the focused secondary placement (`RemovePlacement`) |
| `<CR>` | Open the scene in `$EDITOR` |

Staged rows carry a `▒` left-margin marker; footer shows pending count.

## Phase F — Relations canvas

- F1 `relations.rs`: ports `relations.lua` verbatim-in-semantics — node/edge
  build with mention counts, deterministic layouts (circle ≤14 nodes with
  the 0.62 ellipse squash, columns-by-type above), grid renderer producing
  lines + node rects. Read-only two-pane tab: graph left, inspector right
  (edges `→`/`←` with kinds, type, mentions). `h/j/k/l` walk nearest node
  rect, `Tab` panes, `/` name filter, `f` type filter, `o` orphan toggle,
  `<CR>` opens the card. Compact (<80) collapses to inspector-less graph.
  `syncs_with` edges are filtered from the character graph — they connect
  timelines, not people (authoring them stays in `$EDITOR`).
- F2 Editing through the store: `a` target picker → kind input
  (completes from existing kinds; free text allowed), `e` rename kind,
  `x` delete focused edge. Requires `project.rs` card parsing from E1.

## Phase G — Plotlines unified view

### G1 Read-only

```
 ╭─ Plotlines · 3 tracks ────────────────────────╮ ╭─ The crossing ────────╮
 │ ▌ Telemachy ·→ arc_of Telemachus              │ │ stage  helpless       │
 │ │  ○ helpless    Book I — Visit of Pallas     │ │ plots  Telemachy      │
 │ │  ● companion   Book III — The prince        │ │ time   Present @12    │
 │ │  ░ gathering   (unreached)                  │ │ also   Past @40       │
 │ ▌ Suitors                                     │ │ words  412 · draft    │
 │ │  ◆ emboldened  Book I  (shared with above)  │ ╰───────────────────────╯
```

- One lane per plotline card; attached scenes in manuscript order with
  stage pills; `◆` marks scenes attached to more than one lane; unreached
  declared stages append as dim ghost rows; stage regressions along
  manuscript order tint `warning`.
- **Degradation**: a project with no plotline cards renders today's
  setup/payoff threads view unchanged (states ✓ complete, ○ needs payoff,
  △ needs setup). `v` switches Lanes ⇄ Threads even when cards exist.
- `p` toggles the read-only plot grid: scenes × plotlines matrix, `●`
  member, `◆` multi-track member.
- Two-pane at ≥80 cols (inspector: stage, plots, placements, words,
  status); collapses below.

### G2 Staged editing

| Key | Action |
| --- | --- |
| `a` | Attach a picked scene to the focused lane (picker excludes already-attached) |
| `x` | Detach the focused scene reference |
| `i` | Edit the stage cell: picker fed by the lane's `stages:` sequence, free text allowed |
| `<CR>` | Open the focused scene |

Threads-mode editing mirrors this with `AttachThread`/`DetachThread`;
attaching to a new free-text key creates a thread. Dangling references
tint `warning` and reconcile on refresh.

## Phase H — Neovim-side migration (nothing optional left)

| Stage | Work | Files |
| --- | --- | --- |
| H1 | Per-axis placements + ordinal ranks + `unit` display in the timeline projection; storyboard `shift_day` refuses non-numeric coords instead of mis-shifting | `lua/storyteller/index.lua` (~332), `projections/timeline.lua`, `ui/storyboard.lua` |
| H2 | Plotlines sheet mirroring `storyteller.plotlines` shape; `story_health` findings from the new gates (`stage_regression`, `orphan_plotline`, `uncovered_stage`) | `lua/storyteller/index.lua`, projections |
| H3 | `templates.lua` emits a matching `references/plotlines/<name>.md` card whose `stages:` sequence is the template's beats; `collections.lua` query grammar gains `plotline:` / `stage:` / `timeline:` keys | `lua/storyteller/templates.lua`, `collections.lua` |
| H4 | Card heading fields: `parse_reference` extracts `### Key` sections ∪ `- **Key:**` bullets into a unified fields view (first occurrence wins, case-insensitive); card creation honors `"style": "headings"` | `lua/storyteller/index.lua` (:173), `references.lua`, `templates.lua` |

## Phase I — Chrome, glyphs, release

- I1 Nerd glyph tier behind `--glyphs nerd` (status/tab icon tables);
  contrast preset degrades to the safe tier.
- I2 Tapes: refresh `08-timeline`, `19-tui` (five tabs, one staging moment,
  narrow-width beat); new `20-relations.tape`, `21-plotlines.tape`;
  preset-gallery collage asset; user-guide TUI section (staging model,
  concurrency guidance); `nixvim.nix` option comments; PROGRESS and
  CHANGELOG release notes; plugin version bump.

## Explicit non-goals (documented, not deferred)

Events editor UI (the standard models events; no editor surface yet),
horizontal timeline canvas, sync-anchor authoring in the TUI, prose editing
in the TUI, consolidating the plugin's dual-path execution model.

## Sequencing

Each phase lands green before the next begins:

A → B → C → D → E → F → G → H → I

Phases E/F/G share E1/E2 foundations and the D staging layer; H is
independent of E–G except for A/B prerequisites and can interleave after C
if Lua-side work blocks on nothing else.

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Popup-crate youth | Isolated behind the modal layer, swappable |
| Cross-file atomicity limits | In-memory transform + git snapshots before multi-file applies |
| Relations layout drift vs Lua | Port `relations.lua` semantics; golden fixtures pin render parity |
| Core dependency churn | Pin the standard repo's `v1.3.0` tag |
| Flow-map round-trip corruption | Opaque-string rule (decision 5) enforced by fixtures |

## Estimate

~4–4.5k lines Rust, ~800 test lines, ~12 projection fixtures, plus the
Lua-side H-work (~600 lines incl. tests). Docs/tapes/gallery additional.
