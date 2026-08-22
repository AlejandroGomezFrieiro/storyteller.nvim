# Interaction Contract — One Grammar, Two Frontends

Storyteller ships two frontends: the Neovim plugin and the `storyteller-tui`
(ratatui) application. Both drive the same project model through the same
operations, so both must speak the same control language. This document is the
contract. It is frozen before implementation; changes require updating both
frontends in the same release.

## Principles

1. **Keyboard-first, vim-like.** Every action is reachable with the grammar
   below. Muscle memory transfers between Neovim buffers and the TUI.
2. **No divergent controls.** A key means the same verb everywhere. Frontends
   may add keys, never redefine these.
3. **Mouse is optional, TUI-only.** The TUI may alias mouse actions (click =
   `<CR>`, drag = `J`/`K`) for those who enjoy it. Nothing is mouse-only, and
   documentation never presents dragging as the primary path.
4. **Views are projections; edits commit on write.** Structural surfaces are
   editable text projections of project state (see `docs/projections.md`).
   Neovim applies on `:w`; the TUI applies on `S`.

## The grammar

| Verb | Key | Notes |
| --- | --- | --- |
| Motion | `j` `k` `h` `l` `gg` `G` | `h/l` move between panes/nodes where they exist. |
| Filter | `/` | Prompt, then narrow the visible items. |
| Filter next/prev | `n` `N` | Cycle matches of the last filter. |
| Pane / node cycle | `Tab` | Move focus between panels or graph nodes. |
| Move item | `J` `K` | Move the focused item down/up (scene across the story order, edge target, row). |
| Cut / yank / paste block | `dd` `y` `p` | Block = card (corkboard), row (timeline), node (graph). |
| Edit field | `i` `a` | Edit the field under the cursor. `<CR>` confirms, `Esc` cancels. |
| Cycle status | `a` on a card | Advance `outline → draft → revision → done → outline`. |
| Mark unused | `u` | Set status `unused`. |
| Open | `<CR>` | Open the scene/card: a buffer in Neovim, `$EDITOR` from the TUI. |
| Dismiss / delete | `x` | Remove the focused edge, suggestion, or item. |
| Refresh | `R` | Re-read from disk and re-render. |
| Apply staged changes | `S` (TUI) / `:w` (Neovim) | Commit projection edits atomically. |
| Close | `q` | Leave the view. |
| Key help | `?` | Overlay listing this grammar in context. |

## Projection editing rules

- In **Neovim**, projections are ordinary modifiable `acwrite` buffers. The
  full editor applies: macros, `:g`, visual-block, regex, undo. `:w` diffs the
  buffer against the last render and applies the resulting operations.
- In the **TUI**, insert mode is deliberately limited to single-field edits.
  Anything larger (a multi-line synopsis, a new card's prose) defers to
  `$EDITOR` — which hands off to Neovim.
- Applying is atomic: either every operation lands or none does. Frontends
  stage the diff first and report `N pending changes` before commit.
- A failed apply leaves files untouched and surfaces the reason.

## Verb scoping

The grammar scopes verbs to surfaces. `a` advances a card's status on the
corkboard, but on surfaces without status — the Relations canvas and
Plotlines lanes — it means *add* (an edge, a scene attachment). `<CR>`
always opens what is focused. A surface may add keys beyond this table; it
may never redefine one.

## TUI-added keys (storyteller-tui)

These extend the grammar inside specific TUI tabs and are aliases nowhere
else:

| Key | Tab | Action |
| --- | --- | --- |
| `t` | Timeline | Cycle the focused axis: implicit `main`, then each timeline card. |
| `o` | Timeline | Toggle Reading order ⇄ Story order (both first-class views). |
| `w` | Timeline | Cycle swimlane grouping: off / POV / location / chapter. |
| `s` | Timeline | Mark two rows and swap their coordinates. |
| `v` | Plotlines | Switch Lanes ⇄ Threads modes. |
| `p` | Plotlines | Toggle the read-only plot grid (scenes × plotlines). |

## Safety

- Before any apply that moves scenes between files or rewrites more than one
  file, the engine creates a git snapshot (existing `storyteller:snapshot`
  convention) when the project is a git repository. Undo after apply is
  `:Story diff` against that snapshot.
- Unknown or malformed lines inside a projection are preserved verbatim and
  never written back destructively.
