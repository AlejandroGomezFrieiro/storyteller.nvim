# TUI Visual Overhaul — Plan

> Status: **visuals lane implemented (§16 steps 1–4)**. `theme.rs` (slots,
> presets, `termprofile` adaptation, glyph tiers), the frame skeleton
> (rounded block, tab strip, footer key strip), per-view polish for
> Dashboard/Corkboard/Timeline, CLI flags, responsive breakpoints, and the
> Neovim spawn contract (`--background` from `vim.o.background`,
> `tui_theme`/`tui_glyphs` options) have landed. Note: `coolor` was folded
> into `termprofile`'s own conversion feature — one dependency covers both
> detection and degradation. Steps 5–8 (staged editing: `store.rs`, timeline
> retiming, Relations canvas, Plotlines board) remain planned. The Neovim
> storyboard buffers mirror the same palette via extmarks; see the appendix.

## Appendix — Neovim palette mapping

The editor's storyboards style themselves with extmarks over the canonical
text (`lua/storyteller/ui/board_hl.lua`). Slot ↔ highlight-group mapping:

| Slot (theme.rs) | Neovim group |
| --- | --- |
| `text` | default foreground / `StorytellerScene` |
| `text_dim` | `StorytellerMuted` |
| `accent` | `StorytellerAccent` (day cells, focused) |
| `border` | `StorytellerDivider` |
| `surface` | `StorytellerSurface` (card header bands) |
| `selection_bg` | `StorytellerSelection` + `cursorline` |
| `success` | `StorytellerDone` / `StorytellerMetric` (counts) |
| `warning` | `StorytellerRevision` |
| `error` | `StorytellerUnused` |
| `info` | `StorytellerOutline` |
| `draft` | `StorytellerDraft` |
| keys | `StorytellerKey`; card titles → `StorytellerCardTitle`; chapter headings → `StorytellerSection` |

Retuning a preset hue should touch `tui/src/theme.rs` and the matching
`Storyteller*` group in `lua/storyteller/ui/init.lua` together.

---

## 1. Goals

1. Make `storyteller-tui` look like a modern ratatui app (yazi / lazygit /
   television class) instead of a debug view: semantic color, rounded borders,
   contextual footer, real widgets.
2. Look intentional **both standalone and inside a Neovim terminal buffer**
   (`:Story tui`): palette follows the editor's light/dark background when
   spawned from the plugin, with sane auto-detection otherwise.
3. Degrade gracefully: usable at 16 colors and 40 columns, beautiful at
   truecolor and full width.
4. Extend coverage from three read-only tabs to five views that include the
   project's *relational* state: the character graph, story-time ordering,
   and setup→payoff plotlines.
5. Enable **structured editing in the TUI** without breaking the frozen
   contracts: edits stage as operations and apply atomically on `S`, exactly
   the TUI half of the `:w`/`S` pair in `docs/interaction.md`. Prose stays
   with `$EDITOR`.
6. Keep the frozen key grammar (`docs/interaction.md`) intact — verbs may be
   scoped to surfaces; none are redefined.

## 2. Design Principles

Drawn from how flagship ratatui apps are built:

- **One semantic palette, zero hardcoded colors.** Every style derives from a
  central palette of meaning-named slots. No `Style::default().fg(Color::Cyan)`
  literals anywhere outside `theme.rs`.
- **Three-tier color discipline**: truecolor → indexed-256 → ANSI16. Each tier
  must remain readable; hierarchy comes from modifiers (bold/dim/reversed) as
  much as from hue, so the 16-color tier still communicates state.
- **Color as information, not decoration.** Status colors mean one thing each;
  accent marks focus/interaction; nothing else gets saturated color.
- **Progressive disclosure**: secondary columns and hints appear only when
  width allows; the footer always shows what is possible *right now*.
- **Determinism beats flourish**: no animation, no shader effects, no
  flicker-prone redraws; same project state renders identically frame to
  frame. This is also what keeps VHS demo GIFs reproducible.
- **Views mirror the editor's model.** The TUI renders the same data the
  Neovim projections show (`docs/projections.md`); where Neovim has a canvas
  view (`:Story relations`), the TUI mirrors its semantics rather than
  inventing new ones.

## 3. Library Candidates

Evaluated against this plan via [awesome-ratatui]. Policy: small additive
dependencies only, each isolated behind internals (`theme.rs`, modal layer)
so they can be swapped without touching views. No framework rewrites.

[awesome-ratatui]: https://github.com/ratatui/awesome-ratatui

### 3.1 Adopt

| Crate | Role | Isolation |
| --- | --- | --- |
| [`coolor`](https://crates.io/crates/coolor) | Truecolor ↔ ANSI-256 ↔ ANSI-16 conversion. Replaces hand-maintained per-tier color tables: presets store truecolor hex; conversion happens once at startup per detected capability | Only inside `theme.rs` |
| [`termprofile`](https://github.com/aschey/termprofile) | Terminal color/styling capability detection with Ratatui color support; more reliable than raw `COLORTERM`/`TERM` sniffing, especially inside nvim `:terminal` | Only at startup |
| [`tui-popup`](https://github.com/joshka/tui-popup) | Modal widget for add-edge target/kind pickers, absolute-day prompts (`H`/`L`), and the `?` grammar-help overlay | Modal layer helper |
| [`tui-textarea`](https://crates.io/crates/tui-textarea) (single-line mode) or [`tui-prompts`](https://crates.io/crates/tui-prompts) | Headless single-field input for the grammar's `i`/`a` edit modals (kind rename, thread attach) — implements interaction.md's "single-field editor" clause without hand-built cursor handling | Modal layer helper |

### 3.2 Evaluate before deciding

- **[`tui-nodes`](https://crates.io/crates/tui-nodes)** — node-graph widget.
  Directly targets the Relations canvas, but likely drag/mouse-oriented with
  its own layout model. We need *deterministic* layouts matching the plugin's
  `relations.render_grid` for cross-frontend parity. Default: port our own
  renderer from `relations.lua`; borrow edge-routing ideas if useful.
- **[`tui-scrollview`](https://crates.io/crates/tui-scrollview)** — adopt when
  a view (relations graph, large dashboards) outgrows the viewport; cheap add.
- **[`opaline`](https://crates.io/crates/opaline)** — theme engine with 20
  built-in themes + selector widget. Kept as prior art for preset schema;
  not adopted (own module decision).
- **`ratatui-comfy-tabs` / `tui-tabs`** — built-in `Tabs` suffices for five
  tabs; revisit only if individually-boxed tabs are ever wanted.

### 3.3 Study, don't depend

Patterns worth reading before implementing, not dependencies:

- [`lottie`](https://github.com/coignard/lottie) — terminal screenwriting
  editor for Fountain; the closest existing app to storyteller-tui. Study its
  prose-editing UX and `$EDITOR` boundaries.
- [`serie`](https://github.com/lusingander/serie) — git commit graph in
  terminal cells; best-in-class reference for drawing edges between nodes
  (Relations canvas).
- Kanban boards (`Rust-Kanban`, `fulsomenko/kanban`, `basilk`) — lane-based
  layouts = the Plotlines board pattern.
- [`Gitside`](https://github.com/dev-bhaskar8/gitside) — explicitly designed
  for "full terminals and narrow tmux panes"; same responsive problem as our
  inside-Nvim breakpoint behavior.
- `glues` / `kimün` / `rucola` — Markdown-note TUIs with Git integration;
  sanity-check their file-handling against our stale-guard design.

### 3.4 Skip

`tachyonfx` and all effect/shimmer/throbber/splash widgets (violates the
determinism principle), `edtui` / `ratatui-code-editor` (editing belongs to
Neovim per the contracts), component frameworks (`ratatui-kit`, `tui-realm`,
`rat-salsa` — the app is deliberately three files plus new modules),
image protocols, web/embedded backends, language bindings.

## 4. Theme Architecture

New module `tui/src/theme.rs` owns all styling. Nothing else imports
`ratatui::style::Color` directly.

### 4.1 Palette slots

| Slot | Used for |
| --- | --- |
| `text` | Primary prose/list content |
| `text_dim` | Hints, secondary metadata (POV, word counts, day numbers unscheduled) |
| `accent` | Active tab, focused border, selection edge, focus node, day numbers |
| `border` | Inactive block borders |
| `border_active` | Border of the focused pane (reserved for future split layouts) |
| `surface` | Card/panel background tint (subtle) |
| `selection_bg` | Selected-row background |
| `success` | `done` status, positive deltas, complete threads |
| `warning` | `revision` status, timeline regressions, dangling edges, unpaired threads |
| `error` | `unused` status, failed applies |
| `info` | `outline` status, neutral highlights |
| `draft` | `draft` status (separate slot: most common state, deserves its own hue) |

Status→slot mapping preserves today's `status_color()` semantics (done=green
family, revision=yellow family, draft=magenta family, unused=red family,
outline=blue family) expressed through slots so presets can retune hues
without touching views.

### 4.2 Built-in presets

Curated, small set; own module, no external theme crates. Starting values
below are truecolor hex; indexed/ANSI values are computed at startup via
`coolor` (see §4.3). Values are a starting point — tuning welcome, structure
is the contract.

| Preset id | Background | Character |
| --- | --- | --- |
| `dark` (default) | dark | calm slate; cyan-teal accent (one-dark flavored) |
| `light` | light | warm paper tones; darker accents for contrast |
| `midnight` | dark | deep blue-violet (tokyo-night flavored) |
| `forest` | dark | muted green surfaces; amber accent |
| `contrast` | any | pure ANSI-16 mapping, accessibility fallback |

Preset drafts:

| Slot | dark | light | midnight | forest |
| --- | --- | --- | --- | --- |
| `text` | `#d3d6de` | `#3b3a36` | `#c0c8d8` | `#cbd5bd` |
| `text_dim` | `#767c88` | `#8a857c` | `#5c6478` | `#7d887a` |
| `accent` | `#56b6c2` | `#0e7490` | `#7aa2f7` | `#d19a66` |
| `border` | `#3a3f4b` | `#d6d0c4` | `#33395a` | `#3a463a` |
| `border_active` | `#56b6c2` | `#0e7490` | `#7aa2f7` | `#d19a66` |
| `surface` | `#262a33` | `#f4efe6` | `#1b2036` | `#222b22` |
| `selection_bg` | `#2d3340` | `#e9e2d4` | `#242b48` | `#2c382c` |
| `success` | `#98c379` | `#4a7c37` | `#9ece6a` | `#8fb573` |
| `warning` | `#e5c07b` | `#a16207` | `#e0af68` | `#d7b56d` |
| `error` | `#e06c75` | `#b3403a` | `#f7768e` | `#cc6b60` |
| `info` | `#61afef` | `#2563a8` | `#7dcfff` | `#6ea3a0` |
| `draft` | `#c678dd` | `#8a4fb0` | `#bb9af7` | `#a68bc9` |

`contrast` maps slots to ANSI names instead of hex: text=default fg,
`text_dim`/`border`=gray, accent=cyan, success=green, warning=yellow,
error=red, info=blue, draft=magenta, surface/reset backgrounds, selection=
reversed style. It bypasses conversion entirely and works everywhere.

Preset selection order:

1. Explicit flag wins (`--theme <id>`).
2. Else `--background` maps to `dark`/`light`.
3. Else if `$NVIM` is set (running inside nvim `:terminal`) default to `dark`.
4. Else default `dark`.

### 4.3 Capability detection & degradation

At startup, detect once via `termprofile`:

- TrueColor when the profile reports it (`COLORTERM=truecolor|24bit` et al.).
- Indexed256 when `TERM` advertises `256color` and nothing better.
- ANSI16 otherwise; monochrome (`TERM=dumb`) reduces to modifiers only.

Presets store truecolor hex only; `coolor` converts each slot to the best
representable color for the detected capability at startup. Degradation is
therefore automatic and consistent — no hand-maintained triple tables to
drift. Inside Neovim terminals `termguicolors` governs what actually renders;
hence detection runs on the environment rather than trusting `$NVIM` implies
truecolor.

## 5. Frame Skeleton & Shared Chrome

Every tab renders inside the same three-region skeleton:

```
╭─ ✦ storyteller · The Odyssey ────────────────────────────────╮
│ 1 Dashboard   2 Corkboard   3 Timeline   4 Relations   5 Plotlines │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                       (tab body)                             │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ o open  j/k move  1..5 tabs  R refresh  q quit               │
╰──────────────────────────────────────────────────────────────╯
```

- One outer rounded block (`BorderType::Rounded`).
- Title row carries the brand glyph `✦`, project name, chapter/scene count.
- Tab strip uses the `Tabs` widget: active tab `accent` + bold, inactive
  `text_dim`; number prefixes since both `Tab` and digits switch.
- Footer is a new **key strip widget**: bold key + dim description pairs,
  filtered per active tab, rendered from a static per-tab binding table so it
  can never drift from actual handlers. When ops are staged, the right side
  shows `N pending · S apply` in `warning` until applied.
- `?` opens a grammar overlay (popup) listing the keys valid in the current
  context.

## 6. View Specifications

Tab order and identity after the overhaul:

| # | View | Status today | Becomes |
| --- | --- | --- | --- |
| 1 | Dashboard | read-only paragraph | gauges + bar chart |
| 2 | Corkboard | read-only list | polished read-only list |
| 3 | Timeline | read-only list | **staged retiming editor** |
| 4 | Relations | *(absent)* | **graph canvas + edge editing** |
| 5 | Plotlines | *(absent)* | **thread lanes + scene attach/detach** |

### 6.1 Dashboard

```
 PROJECT                                    12 chapters · 84 scenes · 148k words

 Ithaca            ▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░  6,120 / 8,000
 The Harbor        ▇▇▇▇▇▇▇▇░░░░░░░░░░  3,980 / 7,000
 ...
```

- Header line: project name (bold), totals right-aligned in `text_dim`,
  separated by `·`.
- Per chapter: title column (truncating), progress bar toward target using
  half-block glyphs (`▇` fill, `░` track) — `LineGauge` or custom bar line,
  colored `accent` below target, `warning` over target.
- Chapters without targets render a plain word bar scaled to max, keeping
  today's comparative shape but in palette colors.
- Hint/status line moves to the shared footer (removed from the body).
- Empty project: centered dim message with the `✦` glyph, no error styling.

### 6.2 Corkboard

Read-only polish; editing scenes happens in Neovim storyboards or via
`$EDITOR`.

```
 ╭─ Corkboard · 84 scenes ─────────────────────────────────────╮
 │ ▌ ● draft    The warning          Odysseus          412 w   │
 │   ○ outline  The council argues   Telemachus        380 w   │
 │   ✔ done     Storm lands          —                 1.1k w  │
```

- Selection becomes an **accent left-edge indicator** (`▌` highlight symbol)
  plus `selection_bg`; bare `bg(DarkGray)` goes away.
- Status glyphs (`●` draft, `○` outline, `✔` done, `↻` revision, `×` unused)
  share the status slot color — scannable by shape even in monochrome.
- POV column dims to `text_dim`; missing values render `—` not blanks.
- Word counts right-aligned with `w` suffix; `1.1k` compaction above 999.

### 6.3 Timeline (staged retiming editor)

Adopts roadmap item #1's editing semantics in the current single-day-column
list form (horizontal canvas deferred):

```
 ╭─ Timeline · main ───────────────────────────────────────────╮
 │ ▌   1  The warning           Odysseus    412 w              │
 │ ▒   2  The storm             Odysseus    380 w              │
 │     ·  The omen              Athena       95 w              │
```

Keys (staged, applied on `S`):

| Key | Action |
| --- | --- |
| `h` / `l` | Stage `set_day` −1 / +1 on the focused row (column repaints instantly) |
| `H` / `L` | Prompt an absolute day (popup input) |
| `d` | Clear scheduling — removes numeric ordering |
| `s` | Swap days of two marked rows |
| `t` | Cycle timelines: implicit `main` + each card in `references/timelines/` |
| `<CR>` | Open the scene in `$EDITOR` |

- Rows regressing below their manuscript predecessor, or overlapping a
  same-day sibling on one timeline, tint `warning` (local re-check of the
  LSP's `timeline_regression` / `timeline_overlap` diagnostics).
- Staged-but-unapplied rows show a subtle marker (`▒` in the left margin);
  `Esc`/`u` drops staging.

### 6.4 Relations (graph canvas + edge editing)

Mirrors the plugin's `:Story relations` view and `relations.lua`
(build/layout/render_grid semantics; circular layout under ~12 nodes,
columns-by-reference-type above). Deterministic layouts only.

Two panes: graph left, inspector right.

```
 ╭─ Relations · 9 nodes · 14 edges ───────────╮ ╭─ Odysseus ◆ ───────────╮
 │      Penelope ───── spouse ───┐            │ │ spouse    → Penelope   │
 │         │                     │            │ │ parent    → Telemachus │
 │    Telemachus        Odysseus ●│           │ │ rival     ← Poseidon   │
 │         │              │       │           │ │ mentor    ← Athena     │
 │      Athena ───────────┘  Poseidon          │ │ 12 mentions · character│
 ╰─────────────────────────────────────────────╯ ╰────────────────────────╯
```

- Focus node styled `accent`; `j/k/l/h` walk nodes, `Tab` cycles panes.
- Inspector lists the focused node's edges (`→` outgoing, `←` incoming) with
  kinds, node type, mention count.
- Unresolved edge targets render dim with a warning glyph; containment edges
  (`kind: contains`) draw as nesting hints rather than plain lines.
- Orphan toggle (`o`) dims/hides cards with no edges; `/` filters names;
  `f` filters by reference type.

Editing keys (all staged through the op engine, §7):

| Key | Action |
| --- | --- |
| `a` | Add an edge from the focused node: target picker → kind (completes from existing kinds; free text allowed) |
| `e` | Edit the focused edge's kind |
| `x` | Delete the focused edge |
| `<CR>` | Open the card in `$EDITOR` |
| `R` | Re-read from disk, discard staging (with confirm when ops pending) |

Verb-scope note: the frozen grammar assigns `a` = cycle-status *on cards*;
the Relations canvas has no status, so contextual reuse for add-edge matches
how the grammar scopes verbs to surfaces. One clarifying line gets added to
`docs/interaction.md` (§13).

Writes land as `add_edge` / `remove_edge` / kind-rename ops against card
frontmatter `relations:` blocks, preserving each card's existing entry syntax
(flow map / block map / shorthand) when editing existing entries; newly added
edges use the block-map form. Degrees-of-separation queries stay out of scope
v1.

### 6.5 Plotlines (thread lanes)

Canvas-first v1: TUI-only view over `setup:`/`payoff:` thread keys, matching
`index.plot_threads` semantics and the nvim threads view's states. A shared
`threads` projection format is documented as a follow-up in
`docs/projections.md` (§13), not implemented now.

```
 ╭─ Plotlines · 6 threads ─────────────────────────────────────╮
 │ ✓ the-bow            setup:  Hidden in storeroom            │
 │                      payoff: Stringing it again             │
 │ ○ the-scar           setup:  Boar hunt            (needs payoff)
 │ △ suitors            payoff: Slaughter            (needs setup) │
```

- State glyphs/colors mirror nvim: `✓` complete, `○` needs payoff,
  `△` needs setup.
- Lane navigation: `j/k` across thread rows; `h/l` or `Tab` between setup and
  payoff sides; `<CR>` opens the focused scene in `$EDITOR`.
- Editing (staged):
  - `a` attaches the focused scene (picked from a scene picker) to the
    focused thread side — stages a `set_field` op adding the `setup:`/
    `payoff:` value.
  - `x` detaches the focused scene reference — stages removal.
  - Creating a thread = attaching any scene to a new free-text key.
- Dangling references (scene renamed/deleted under a thread) tint `warning`
  and reconcile on refresh.

## 7. Staged-Edit Engine (`store.rs`)

The TUI is read-only today because `project.rs` only parses. Structured
editing requires a small write engine:

```rust
enum Op {
    SetField { scene: SceneRef, key: String, value: Option<String> },
    SetDay { scene: SceneRef, day: Option<i64> },
    AddEdge { card: CardRef, to: String, kind: String },
    RemoveEdge { card: CardRef, to: String, kind: Option<String> },
}
```

Semantics, mirroring `lua/storyteller/projections/` and `meta/write.lua`:

- **Surgical writes**: rewrite only changed YAML lines; preserve unknown
  frontmatter, comments, and body verbatim. Relation edits keep each card's
  existing entry syntax; additions use block-map form.
- **Atomic apply**: temp-file + rename per file; either every staged op lands
  or none does. Failed applies surface the reason and leave files untouched.
- **Git snapshot** before any apply touching more than one file (existing
  `storyteller:snapshot` convention), git projects only.
- **Stale guard**: project mtimes fingerprinted at load/refresh; apply aborts
  if anything changed underneath ("R to reload") rather than guessing.
- **Staging UX**: every edit keystroke stages an op; footer shows
  `N pending · S apply`; `Esc`/`u` drops staging (with confirm when non-empty).
- **Parity fixtures**: golden fixtures shared with the Lua projection engine
  pin render/apply byte-compatibility, extending the conformance-fixture
  pattern already used against the standard repo. This is the seam where
  `storyteller-core` (the future Rust library) will absorb this code.

Prose-level work never moves into the TUI: `<CR>` hands off to `$EDITOR`
exactly as today.

## 8. Responsive Layout

Breakpoint set evaluated every frame on `frame.area().width`:

| Width | Behavior |
| --- | --- |
| < 50 | Compact: hide footer descriptions (keys only), truncate titles aggressively, dashboard hides bars, lists show status glyph + title only, relations collapses to inspector-less graph, plotlines hide side labels |
| 50–79 | Standard: current column sets, footer full |
| ≥ 80 | Comfortable: timeline day separators, wider title columns, dashboard gauge labels fully expanded, relations two-pane |

This matters most inside Neovim where the terminal buffer often shares the
window with splits. No horizontal scrolling ever.

## 9. Glyph Strategy

Two tiers, compile-time tables in `theme.rs` (or a sibling `glyphs.rs`):

- **Safe tier (default)**: box-drawing + widely supported symbols only —
  `▌ ● ○ ✔ ↻ × · ┈ ░ ▇ ✦ ▒ ◆ → ←`. All render in any modern terminal font;
  degrade to ASCII (`>`, `o`, `x`, `-`) automatically when monochrome/`dumb`
  is detected.
- **Nerd tier (opt-in)**: `--glyphs nerd` swaps status/tab icons for Nerd Font
  glyphs. Never auto-enabled (fonts are undetectable); documented opt-in.
  No behavior difference otherwise.

## 10. CLI Flags & Neovim Spawn Contract

Flags (hand-parsed `std::env::args`; no heavy arg crates):

```
storyteller-tui [--theme <id>] [--background dark|light] [--glyphs safe|nerd] [path]
```

Plugin-side contract (wiring lands with the code change):

- `:Story tui` passes `--background` derived from `vim.o.background`, and
  `--theme`/`--glyphs` from new `setup()` options (`tui_theme`,
  `tui_glyphs`), falling back to auto-detect when absent.
- `$NVIM` presence remains the manual-launch fallback signal (defaults to
  dark preset) so users spawning it by hand inside nvim still get a sane
  palette.

## 11. Concurrency Rules (Neovim ↔ TUI)

Both frontends can hold the same project open; structural edits make this a
real hazard, addressed explicitly:

1. **Stale guard** (§7) protects the TUI's writes: no apply over files that
   changed since load.
2. Files written by the TUI do **not** trigger nvim's `detect_on_save` (it
   fires on nvim `BufWritePost`), so nvim views/buffers can go stale after a
   TUI apply. Documented guidance: run structural edits in one frontend at a
   time; `:checktime` / reopen projections in nvim after TUI applies. An fs-
   watch auto-refresh is a noted future improvement, out of scope here.
3. Inside `:Story tui` everything runs in the embedded terminal buffer — no
   extra plumbing; the existing `$EDITOR` handoff round-trips through nvim.

## 12. Test Matrix

`TestBackend`-based assertions on buffer content and styles, never pixels:

- Each tab at widths 40 / 60 / 100: correct breakpoint branch, no panics, key
  strings present.
- Theme degradation: presets rendered under TrueColor vs ANSI16 capability —
  identical structure; conversion snapshots stable.
- Footer strip reflects the active tab's binding table and staged-op count.
- Status glyph/color mapping table-driven over all schema statuses.
- Store engine: golden-fixture parity with the Lua projection engine
  (render/apply byte-compat), atomicity (failed multi-op apply leaves files
  untouched), stale-guard abort, relation-syntax preservation on edit.
- Layout determinism: same fixture project → identical frame bytes.
- Existing `project.rs` parser tests untouched and green.

Verification commands: `cargo test` in `tui/`;
`nvim --headless -u NONE -l tests/storyteller_spec.lua` for the plugin suite.

## 13. Contract Deltas & Documentation Touchpoints

The frozen contracts need only additive clarifications, shipped in the same
release as the features they describe:

- `docs/interaction.md`: one line noting verb scoping (`a` = add-edge on the
  Relations canvas; cycle-status remains card-surface behavior).
- `docs/projections.md`: a "planned" entry for the `threads` projection
  format (shared nvim+TUI bulk editing of plotlines) so the canvas-first v1
  doesn't read as an oversight.
- No other frozen-contract changes. `reorder` remains Neovim-only surface
  work; the TUI never restructures chapters.

## 14. Non-Code Extras

Documentation and assets landing alongside (or immediately after) the code:

1. **VHS demo refresh**
   - Update `docs/vhs/19-tui.tape` to exercise all five tabs, the footer,
     staging (`N pending` → `S`), and one narrow-width moment.
   - New tapes: `20-relations.tape` (focus walk, add/delete edge, apply) and
     `21-plotlines.tape` (attach/detach, thread states); regenerate GIFs into
     `docs/assets/`.
2. **`tui/README.md` (new)** — crate readme: screenshots (dark + light),
   flags table (`--theme/--background/--glyphs`), preset gallery, how
   `:Story tui` interacts with Neovim colorscheme background, build/test
   instructions.
3. **User guide** — extend `docs/user-guide.md`'s TUI section: theme flags,
   `tui_theme`/`tui_glyphs` options, the staged-editing model (`S` vs nvim's
   `:w`), and the concurrency guidance from §11.
4. **Nixvim module docs** — document the new setup options in the nixvim
   module settings comments/docs for flake consumers.
5. **README touch-ups** — "The TUI" section gains one sentence on theming
   parity and staged editing; keep the AI/no-AI wording intact.
6. **Preset gallery asset** — VHS-generated collage of the five presets,
   referenced from `tui/README.md`.
7. **Release notes** — PROGRESS.md gains a "TUI restyle" bullet group
   (theme module, widgets, flags) and a "TUI structured editing" group
   (store engine, relations/timeline/plotlines), matching the existing log
   style.

## 15. Out Of Scope

- Prose editing inside the TUI (stays `$EDITOR`/Neovim).
- Chapter restructuring (`reorder`) in the TUI — corkboard stays read-only;
  structural moves remain Neovim storyboard work.
- Mouse-first interaction; mouse aliases remain as-is per
  `docs/interaction.md`.
- Animation/spinners/shader effects (nothing long-running exists to indicate;
  determinism principle).
- User-defined palette files (can come later behind the same `--theme` seam).
- `threads` projection implementation (documented follow-up, §13).
- Horizontal timeline canvas (roadmap #1 remains the Neovim-side design).
- fs-watch auto-refresh (§11 notes it as future work).

## 16. Sequencing

Visuals first (other workstream's lane), then editing, each step shippable
and green (`cargo test`, headless suite untouched) so concurrent source work
never collides with a broken tree:

1. `theme.rs` + palette slots + `coolor`/`termprofile` wiring; mechanically
   port existing views onto it — zero visual ambition, pure refactor.
2. Frame skeleton: outer rounded block, `Tabs` header, footer key strip.
3. Per-view polish: dashboard gauges → corkboard → timeline visuals
   (one commit each, TestBackend test included).
4. Flags + responsive breakpoints + glyph tiers.
5. `store.rs` op engine + golden fixtures + stale guard (still no UI change).
6. Timeline staged retiming (`h/l/H/L/d/s/t`).
7. Relations canvas + edge editing.
8. Plotlines board.
9. Non-code extras: tapes, READMEs, gallery asset, release notes (§14).

Steps 5–8 reuse the palette and chrome from steps 1–4 automatically; no view
is restyled twice.
