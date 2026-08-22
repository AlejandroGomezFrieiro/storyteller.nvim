# VHS Demos

The tapes in this directory generate the GIFs embedded in the README, user
guide, and language-server guide. They use
[Charmbracelet VHS](https://github.com/charmbracelet/vhs), `demo-init.lua`, and
the small Markdown project in `demo/`, so they run without a personal Neovim
configuration.

The demo project (`demo/`) covers the documented surface: two chapters in scene
YAML, character/location cards with aliases, a custom codex type
(`creatures/`), an unused card, a name mentioned in prose without a card so
the LSP can offer to create it, seeded annotations in `notes/annotations.md`,
and saved searches in `.storyteller/collections.json`.

From the repository root, use the demo shell so the recordings include the
same polished LSP UI used by the project demos:

```bash
nix develop .#demo # provides VHS, Storyteller, storyteller-tui, and storyteller-lsp
vhs docs/vhs/01-dashboard.tape
vhs docs/vhs/02-corkboard.tape
vhs docs/vhs/03-scrivenings.tape
vhs docs/vhs/04-track.tape
vhs docs/vhs/05-lsp-navigation.tape
vhs docs/vhs/06-lsp-create-card.tape
vhs docs/vhs/07-lsp-completion.tape
vhs docs/vhs/08-timeline.tape
vhs docs/vhs/09-threads.tape
vhs docs/vhs/10-health.tape
vhs docs/vhs/11-annotations.tape
vhs docs/vhs/12-collections.tape
vhs docs/vhs/13-compose.tape
vhs docs/vhs/14-corkboard-move.tape
vhs docs/vhs/15-snapshot-diff.tape
vhs docs/vhs/17-synopsis.tape
vhs docs/vhs/18-metasheet.tape
vhs docs/vhs/19-tui.tape
vhs docs/vhs/storyteller.tape
```

Validate every tape before recording, then regenerate every GIF with:

```bash
nix develop .#demo --command vhs validate 'docs/vhs/*.tape'
for tape in docs/vhs/*.tape; do nix develop .#demo --command vhs "$tape"; done
```

The output paths are declared inside each tape:

| Tape | GIF | What it shows |
| --- | --- | --- |
| `01-dashboard.tape` | `01-dashboard.gif` | `:Story` dashboard. |
| `02-corkboard.tape` | `02-corkboard.gif` | `:Story corkboard` as an editable storyboard; `a` stages a status change. |
| `03-scrivenings.tape` | `03-scrivenings.gif` | `:Story compile` (editable continuous manuscript). |
| `04-track.tape` | `04-track.gif` | `:Story track` tracking dashboard. |
| `05-lsp-navigation.tape` | `05-lsp-navigation.gif` | LSP hover (`K`), `gd`, `gr` on an alias. |
| `06-lsp-create-card.tape` | `06-lsp-create-card.gif` | LSP code action: create a card for an uncarded name. |
| `07-lsp-completion.tape` | `07-lsp-completion.gif` | LSP completion for prose names, fields, statuses, and references. |
| `08-timeline.tape` | `08-timeline.gif` | Story-time table; `J` shifts a scene's day cell. |
| `09-threads.tape` | `09-threads.gif` | Plot setup and payoff planner. |
| `10-health.tape` | `10-health.gif` | Story health review. |
| `11-annotations.tape` | `11-annotations.gif` | Capture a note from a selection; review `notes/annotations.md`. |
| `12-collections.tape` | `12-collections.gif` | One-off scene query landing in the quickfix list. |
| `13-compose.tape` | `13-compose.gif` | Distraction-free composition mode. |
| `14-corkboard-move.tape` | `14-corkboard-move.gif` | Reordering scenes with `J`/`K`; `:w` applies across chapter files. |
| `15-snapshot-diff.tape` | `15-snapshot-diff.gif` | Snapshot, revise, and diff against the snapshot. |
| `16-relations.tape` | `16-relations.gif` | The character relationship graph. |
| `17-synopsis.tape` | `17-synopsis.gif` | The synopsis outliner; prose writes back to YAML on `:w`. |
| `18-metasheet.tape` | `18-metasheet.gif` | Bulk metadata editing; even `:s` is a project edit. |
| `19-tui.tape` | `19-tui.gif` | The `storyteller-tui` cockpit: dashboard, corkboard, timeline. |
| `20-relations-tui.tape` | `20-relations-tui.gif` | The TUI relations graph with its inspector pane. |
| `21-plotlines-tui.tape` | `21-plotlines-tui.gif` | The TUI plotlines lanes, threads, and grid. |
| `storyteller.tape` | `storyteller.gif` | Tour: dashboard → corkboard → scrivenings. |

`demo-init.lua` starts the plugin and the `storyteller-lsp` client for the
demo project. Each tape requires the demo executables and pins 60 FPS with
normal playback speed for deterministic, current VHS output. Regenerate all
assets after a visual or workflow change before publishing documentation.
