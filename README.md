# storyteller.nvim

> A calm, Markdown-first writing workspace for Neovim.

Storyteller helps you move between the small and large parts of a long-form
project: a sentence in a scene, the shape of a chapter, the people and places
around it, and the manuscript as a whole. Your writing stays in ordinary
Markdown files. Storyteller adds the views and actions that make those files
comfortable to work with.

> [!WARNING]
> `storyteller.nvim` is in **early development**. Commands, APIs, metadata, and
> the language server may change between releases. Expect rough edges and
> occasional breaking changes while the project takes shape.

## What You Get

- A dashboard, outline, corkboard, workspace, and scene picker.
- Scene metadata for status, point of view, location, beats, and targets.
- Reference cards for characters, places, objects, organizations, and your own
  categories.
- An editable continuous manuscript that writes changes back to chapter files.
- Metadata-free Markdown plus Pandoc-based DOCX, EPUB, PDF, and SMF export.
- Writing sessions, progress history, streaks, milestones, and git snapshots.
- Story structure templates for planning a new project.
- An optional prose-aware language server for navigation, completion, and
  reference cards.

![Storyteller workspace](docs/assets/storyteller.gif)

## Install

Storyteller has no required Lua dependencies. Add it to your Neovim plugin
manager and call `setup`:

```lua
{
  "AlejandroGomezFrieiro/storyteller.nvim",
  config = function()
    require("storyteller").setup()
  end,
}
```

Optional integrations are detected when available:

- `telescope.nvim` or `fzf-lua` for faster pickers.
- `nui.nvim` for richer windows and layouts.
- `ripgrep` for faster project indexing.
- `pandoc` for document export.

The UI falls back to ordinary buffers, so the core workflow does not depend on
any of these tools.

## Your First Project

Storyteller recognizes a project when it finds a `.storyteller` marker, a
`chapters/` or `references/` directory, or a git root. For a new project:

```bash
mkdir -p my-story/{chapters,references/characters,references/locations}
touch my-story/.storyteller
nvim my-story/chapters/01-opening.md
```

Write chapters as Markdown. A `##` heading starts a scene:

````markdown
# Chapter 1 — The Harbor

## The warning

```yaml
storyteller: scene
status: draft
pov: Odysseus
location: Ithaca
goal: Convince the council to leave
conflict: The storm closes the harbor
```

The rain had not stopped for a week.
````

Open the dashboard with `:Story`, or use `<leader>s` after setup. For a guided
tour of the workflow, see the [user guide](docs/user-guide.md).

## A Writing Session

Most days can be as simple as:

1. Open `:Story resume` or choose a scene with `:Story scenes`.
2. Draft in the chapter file as usual.
3. Use `:Story status` as a lightweight record of where the scene is.
4. Step back with `:Story outline` or `:Story corkboard` when you need to
   reorient.
5. Run `:Story compile` when you want to read the manuscript continuously.

Storyteller is meant to disappear while you write and reappear when structure,
context, or progress becomes useful.

## Commands

Every command begins with `:Story` and supports completion. `:Story palette`
opens a searchable command list.

| Command | Use it to |
| --- | --- |
| `:Story` | Open the dashboard. |
| `:Story outline` | Review chapters, word counts, and targets. |
| `:Story scenes` | Find and open a scene. |
| `:Story next` / `prev` | Move between scenes. |
| `:Story resume` | Return to the last scene you visited. |
| `:Story corkboard` | Review scenes as cards. |
| `:Story workspace` | Toggle the binder and inspector. |
| `:Story meta` | Edit the current scene's metadata. |
| `:Story status` | Set or cycle the current scene's status. |
| `:Story references` | Browse reference cards. |
| `:Story detect` | Find and link known references. |
| `:Story capture` | Create a card from a visual selection. |
| `:Story idea` / `ideas` | Capture or review ideas. |
| `:Story compile` | Open the editable continuous manuscript. |
| `:Story manuscript` | Write `build/manuscript.md` without metadata. |
| `:Story export` | Export the manuscript through Pandoc. |
| `:Story track` | Review writing progress. |
| `:Story session start` / `end` | Record a writing session. |
| `:Story snapshot` | Create a git safety snapshot. |
| `:Story template` | Apply a story structure without overwriting files. |

The default keymaps live under `<leader>s`; the complete list is in the
[user guide](docs/user-guide.md).

## The Language Server

The optional `storyteller-lsp` companion understands Storyteller projects. It
connects names in your prose to reference cards without requiring special link
syntax:

- `K` shows a card summary.
- `gd` opens the matching card.
- `gr` finds mentions across the manuscript.
- Completion suggests names and metadata values.
- Code actions create cards and connect them to scenes.

See the [language server guide](docs/language-server.md) for installation,
configuration, and the command-line tools.

## Configuration

The defaults are intentionally useful:

```lua
require("storyteller").setup({
  picker = "auto",          -- "auto" | "telescope" | "fzf"
  ui = "auto",              -- "auto" | "morph" | "nui" | "buffer"
  detect_on_save = true,
  detect_debounce = 300,
  heatmap_weeks = 30,
})
```

For project vocabulary, custom fields, reference types, and diagnostics, see
the [schema reference](docs/schema.md).

## Documentation

- [User guide](docs/user-guide.md): the complete writing workflow.
- [Language server guide](docs/language-server.md): prose navigation and
  completions.
- [Schema reference](docs/schema.md): customize project metadata and checks.
- [VHS demos](docs/vhs/README.md): reproduce the screenshots and GIFs.
- `:help storyteller`: Neovim help for commands and options.

## Development

Run the dependency-free regression suite with a recent Neovim:

```bash
nvim --headless -u NONE -l tests/storyteller_spec.lua
```

The demo assets can be regenerated with the instructions in
[`docs/vhs/`](docs/vhs/README.md).
