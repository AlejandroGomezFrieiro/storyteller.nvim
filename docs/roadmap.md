# Roadmap — Features For Writers

This document is the design backlog: features that would make Storyteller a
complete writing environment, with enough detail to implement each one
independently. Items are ordered roughly by value-to-effort. Nothing here is
committed; the [standard repo's spec](https://github.com/AlejandroGomezFrieiro/storyteller)
gains normative status only when a feature ships.

Design principles, inherited from the standard:

1. **Files are the truth.** Every feature reads and writes plain Markdown +
   YAML; nothing lives only in a database or session state.
2. **The prose is the link.** Bare names resolve through the index; no bracket
   syntax is ever required.
3. **Views are cheap; edits are precise.** Any view may be rebuilt from disk at
   any time; write-back paths must be surgical and conflict-aware.

---

## 0. Rendering Strategy For Interactive Views

The timeline editor (#1) and relationship map (#2) are *canvases*, not lists:
nodes at positions, edges between them, hover states, click-to-activate. That
is a different shape from today's line-based views, so the renderer choice
matters. The candidates evaluated:

### Candidates

| | [morph.nvim](https://github.com/jrop/morph.nvim) (vendored) | [fibrous.nvim](https://github.com/mbrea-c/fibrous.nvim) | [volt](https://github.com/nvzone/volt) |
| --- | --- | --- | --- |
| Model | React-like reconciler, hyperscript elements | React-like VDOM + hooks + subtree reconciliation | Reactive extmark UI |
| Layout | Manual (we compose columns ourselves) | CSS-like **box model**, inline flow | Panel/positioning helpers |
| Rendering | Whole-buffer reconciliation | Inline text + extmarks in one unmodifiable buffer; editable floats only for real inputs | Extmarks |
| Interaction | Manual keymaps + hit-testing (our `at_cursor`) | Built-in cursor-driven hover/activation; [flash.nvim](https://github.com/folke/flash.nvim) jump-to-widget via `fibrous.targets` | Per-plugin keymaps |
| License | MIT | MIT | **GPL-3.0** |
| Packaging | Single file, designed to be vendored | Flakified (`packages.<system>.default`), test suite, benchmarks | Flakified |
| Maturity | Stable, small API, already integrated here | Young but actively developed (102 commits, WASM-powered docs site) | Proven (minty, menu, typr) but docs "coming soon" |

### Assessment

- **volt is ruled out** despite the most stars: GPL-3.0 would force the
  licensing story of this MIT project, its API is undocumented, and it is
  coupled to the NvChad ecosystem's conventions.
- **morph stays** for everything already shipped. It works, it's vendored, and
  rewriting working views buys nothing.
- **fibrous is the right foundation for new canvas-like views.** The box model
  solves exactly our hardest problems (card layout, edge drawing, padding that
  respects display width); inline rendering means a graph can live in one
  buffer next to a normal inspector split; hover/activation replaces our
  hand-rolled `at_cursor` hit-testing; and `targets()` gives free flash-style
  jumping between nodes. Its youth is the main risk.

### The plan: one internal contract, three backends

Introduce `lua/storyteller/ui/canvas.lua` — a small interface every complex
view programs against:

```lua
canvas.new({ name, build, on_activate })
  :node(props)   -- positionable, hoverable element
  :edge(from, to, props)
  :text(props)
```

Backends, chosen per view at open time:

1. **`fibrous`** (preferred for canvases) — maps nodes/edges onto fibrous
   components; gets hover, activation, and flash-jumping for free.
2. **`morph`** (default for list/panel views) — unchanged behavior for
   dashboard, outline, corkboard, tracking.
3. **`buffer`** (always available) — the current plain-extmark fallback.

Two frameworks never share one buffer. Composition happens at the window
level: e.g., the relationship map renders its graph in a fibrous buffer while
the inspector panel beside it remains a morph view. If fibrous is absent, the
buffer backend degrades gracefully — same data, plainer presentation — which
matches the plugin's zero-hard-dependency stance.

Adoption steps: add fibrous as an optional dependency + flake input → port the
relationship map (#2) as the first canvas view → evaluate the timeline editor
(#1) on the same contract → leave existing views on morph unless a rewrite
pays for itself.

---

## 1. Timeline Editor (viewer + retiming)

**Problem.** `:Story timeline` orders scenes by `day:` but is read-only. Writers
plan in time: "this confrontation must happen three days after the storm, and
before the funeral."

**Design.**

- A new `ui.timeline_editor` view renders a horizontal story-time axis:
  one column per story day (or per distinct numeric value), scenes as compact
  cards placed in their day column, stacked when they share a day.
- Multiple timelines are supported natively — the implicit `main` timeline plus
  every card in `references/timelines/` — selected with a key (`t` cycles).
- Rows below the axis show parallel tracks filtered by POV or thread
  (`p`/`T` pickers), so you can see Anna's day 3 against Ben's day 3.
- Regressions (a scene earlier than its manuscript predecessor) and overlaps
  flagged by the existing diagnostics render in warning colors.

**Editing operations** (each writes exactly one YAML field via `meta.scene_write`):

| Key | Action |
| --- | --- |
| `h` / `l` | Move scene one day earlier / later (`day:` ± 1). |
| `H` / `L` | Prompt for an absolute day. |
| `d` | Prompt for free-form time (`after the storm`) — removes numeric ordering. |
| `<CR>` | Open the scene. |
| `s` | Swap two selected scenes' days. |

- The LSP already publishes `timeline_regression`/`timeline_overlap`
  diagnostics; the editor re-checks locally after each edit and shows the
  result immediately.
- Non-numeric scenes appear in a holding area ("unscheduled") at the left;
  pressing a number key schedules them.

**Effort.** Medium. All data access exists (`index.timeline`, LSP
`storyteller.timeline` command); the work is layout + hit-testing, both of
which have precedents in `compose_columns`.

## 2. Character Relationship Map

**Problem.** Cards support `relations:` edges (spouse, ally, rival, contains…)
but nothing visualizes or edits them.

**Prior art.** [ideadrop.nvim](https://github.com/CarGDev/ideadrop.nvim) proves
an Obsidian-style graph works inside a Neovim buffer: a computed layout drawn
into one buffer, `h/j/k/l` node walking, zoom (`+`/`-`), centering, label
toggling, tag/folder filters, an orphans toggle, and cache refresh. We borrow
the *interaction model*, not the code (it is nvim-tree-dependent and edges come
from `[[wikilinks]]`, whereas our edges are structured `relations:` YAML plus
bare-name mentions from the index — richer and already resolved).

**Design.**

- `:Story relations` renders the cast as a graph on the canvas contract
  (section 0): fibrous backend when available, plain-buffer fallback otherwise.
  First release uses deterministic layouts only — circular for small casts
  (<12), columns-by-reference-type for larger ones; ideadrop's optional
  "animate" mode shows force-directed layout is *possible* in a buffer, but
  determinism beats prettiness for an editing tool.
- Interaction model (ideadrop-style):

  | Key | Action |
  | --- | --- |
  | `h/j/k/l` / Tab | Walk to the nearest node. |
  | `<CR>` | Open the card file. |
  | `a` | Add an edge from the focused node: pick target, then kind (existing kinds complete; free text allowed). |
  | `x` | Delete the edge under the cursor. |
  | `+` / `-` | Zoom (node radius / label density). |
  | `L` | Toggle edge-kind labels. |
  | `o` | Toggle orphan display. |
  | `f` | Filter by reference type or tag. |
  | `R` | Re-index and redraw. |

- A side panel (separate window, morph) shows the focused card's summary
  bullets and its edges — two frameworks, one screen, no shared buffer.
- Writes go through card frontmatter (`relations:`), matching the standard;
  the LSP's `storyteller.relationships` command supplies the graph when
  available, with a Lua fallback in `index.lua`.
- Derived views: **orphan detection** (cards with no edges — candidates for
  cutting), **containment tree** (`kind: contains` rendered as nesting for
  organizations/places), and a degrees-of-separation query (`:Story relations
  Odysseus Charybdis`) showing shortest paths.
- Mention-weighting: because the index counts bare-name mentions, edge and
  node size can reflect how often a character actually appears in the
  manuscript — something wikilink graphs cannot do.

**Effort.** Medium-high. Graph layout is the risk; the column fallback keeps v1
shippable without force simulation.

## 3. Synopsis Outliner

**Problem.** The schema has a `synopsis:` field, but the outline shows only
titles and word counts. Scrivener users live in the synopsis outliner.

**Design.** Extend `:Story outline` with a synopsis mode (`s`): each scene row
expands to its wrapped synopsis text, editable in place. Editing writes back to
the scene's YAML block on save (same two-way machinery as Scrivenings). Add a
"chapter card" row type so chapters can carry synopses too (frontmatter
`synopsis:`).

**Effort.** Low-medium. Highest value-per-line-of-code on this list.

## 4. Beat Sheet Overlay

**Problem.** Templates scaffold chapters but don't help you check a draft
*against* a structure.

**Design.** `:Story beats <template>` overlays the chosen structure's expected
beats against actual scenes: each beat row lists candidate scenes (matched by
position or by `beat:` metadata keywords) and flags gaps ("no midpoint") and
misplacements ("dark night of the soul occurs before midpoint"). Read-only in
v1; `b` assigns a scene to a beat by writing `beat:` metadata.

**Effort.** Medium. Builds directly on `templates.lua` plans.

## 5. Writing Sprints

**Problem.** Sessions track totals; writers respond to timed bursts.

**Design.** `:Story sprint 15` starts a countdown shown in the statusline
component (already exists) plus a floating timer. At zero: words written during
the window, words/hour pace, and a log line appended to `progress.log` with a
`sprint` tag. History surfaces in the tracking dashboard as a per-sprint bar
chart. Optional chime via `vim.notify` + terminal bell.

**Effort.** Low.

## 6. Velocity Forecast

**Problem.** "Will I finish by November?"

**Design.** From `progress.log`: rolling 14-day average velocity vs. remaining
words (sum of chapter/scene targets minus current counts). Rendered on the
tracking dashboard as "on pace for <date>" with best/median/worst bands. No new
data required.

**Effort.** Low.

## 7. Revision Walk

**Problem.** Revising means re-reading everything, but writers need a queue,
not a wall.

**Design.** `:Story revise` builds a worklist from `story_health` findings +
scenes whose status is `draft`, ordered by chapter. Each entry opens the scene
with a small fixed footer: `n` next finding, `r` mark revised (status →
`revision`), `d` defer (pins to end). State persists in
`.storyteller/revision.json`. Pairs naturally with snapshot diffing: entering
the walk can diff against the last pre-revision snapshot.

**Effort.** Medium.

## 8. Name Guardian

**Problem.** Long drafts accumulate near-duplicate names (Alys/Alice/Elice)
that alias resolution can't disambiguate safely.

**Design.** A diagnostic (LSP HINT + health finding) using edit distance over
tokenized proper nouns: flag pairs above a similarity threshold where neither
is an alias of the other. Code action offers "rename all X → Y" through the
existing guarded rename path.

**Effort.** Low-medium. Mostly core-side (`crates/core`).

## 9. Reading Mode

**Problem.** Reviewing pacing requires reading without chrome.

**Design.** `:Story read` opens the compiled manuscript in composition-style
presentation with estimated reading time per chapter, progress percentage, and
`j/k`-only navigation. Strictly a view over `compile.manuscript()`; no
write-back.

**Effort.** Low.

## 10. Backmatter Generator

**Design.** `:Story backmatter` emits `build/` artifacts from the index: a
table of contents (chapters + scene titles), a cast list grouped by reference
type with one-line summaries, and a chapter synopsis sheet. Each is a stable,
regenerable Markdown file intended for submission packages.

**Effort.** Low.

## 11. Series Workspace

**Design.** A `.storyteller/series.json` listing sibling project roots; the
picker gains a project switcher, tracking aggregates across books, and the
relationship map can span series bibles kept in a shared references root.

**Effort.** Medium. Depends on finishing multi-root hygiene in the plugin
(schema scoping groundwork already landed).

## 12. Session Analytics

**Design.** Extend `progress.log` parsing with optional fourth column
(words/hour) recorded by sessions/sprints; heatmap gains an hour-of-day view
("you write best at 6am"), and the dashboard shows median session length.

**Effort.** Low.

---

## Deliberately Out Of Scope

- **Cloud sync / mobile** — files + git already cover this better than we can.
- **AI drafting** — the project carries an explicit no-AI-features stance.
- **WYSIWYG formatting** — Pandoc handles presentation; prose stays plain.

## Sequencing Suggestion

1. Synopsis outliner (#3) + sprints (#5) + forecast (#6) — small, compounding.
2. Canvas contract (#0) + relationship map (#2) — introduces fibrous as an
   optional backend on the highest-interaction view.
3. Timeline editor (#1) — reuses the canvas contract; the flagship planning
   surface.
4. Revision walk (#7) + name guardian (#8) — the revision pass.
5. Everything else as appetite allows.
