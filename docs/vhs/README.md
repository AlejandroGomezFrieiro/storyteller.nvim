# VHS Demos

The tapes in this directory generate the GIFs embedded in the README, user
guide, and language-server guide. They use
[Charmbracelet VHS](https://github.com/charmbracelet/vhs), `demo-init.lua`, and
the small Markdown project in `demo/`, so they run without a personal Neovim
configuration.

The demo project (`demo/`) covers the documented surface: two chapters in scene
YAML, character/location cards with aliases, a custom codex type
(`creatures/`), an unused card, and a name mentioned in prose without a card so
the LSP can offer to create it.

From the repository root, use the demo shell so the recordings include the
same polished LSP UI used by the project demos:

```bash
nix develop .#demo # provides VHS, Storyteller, LSPSaga, and storyteller-lsp
vhs docs/vhs/01-dashboard.tape
vhs docs/vhs/02-corkboard.tape
vhs docs/vhs/03-scrivenings.tape
vhs docs/vhs/04-track.tape
vhs docs/vhs/05-lsp-navigation.tape
vhs docs/vhs/06-lsp-create-card.tape
vhs docs/vhs/07-lsp-completion.tape
vhs docs/vhs/storyteller.tape
```

The output paths are declared inside each tape:

| Tape | GIF | What it shows |
| --- | --- | --- |
| `01-dashboard.tape` | `01-dashboard.gif` | `:Story` dashboard. |
| `02-corkboard.tape` | `02-corkboard.gif` | `:Story corkboard`. |
| `03-scrivenings.tape` | `03-scrivenings.gif` | `:Story compile` (editable continuous manuscript). |
| `04-track.tape` | `04-track.gif` | `:Story track` tracking dashboard. |
| `05-lsp-navigation.tape` | `05-lsp-navigation.gif` | LSP hover (`K`), `gd`, `gr` on an alias. |
| `06-lsp-create-card.tape` | `06-lsp-create-card.gif` | LSP code action: create a card for an uncarded name. |
| `07-lsp-completion.tape` | `07-lsp-completion.gif` | LSP completion for prose names, fields, statuses, and references. |
| `storyteller.tape` | `storyteller.gif` | Tour: dashboard → corkboard → scrivenings. |

`demo-init.lua` starts the plugin and the `storyteller-lsp` client for the
demo project. Regenerate all assets after a visual or workflow change before
publishing documentation.
