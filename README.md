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

## AI, and who writes the story

Storyteller was developed with the aid of AI tools, but it has no AI
integration. Nothing in the plugin generates, rewrites, or "improves" your
prose, and it never calls out to a language model. It is a set of tools for
organizing and reviewing your own writing — not a way to replace an author.
The words are yours.

## What You Get

- A project dashboard, outline, card-based corkboard, timeline, plot-thread
  planner, story-health review, workspace, and scene picker.
- Scene metadata for status, point of view, location, beats, and targets.
- Reference cards for characters, places, objects, organizations, and your own
  categories.
- An editable continuous manuscript that writes changes back to chapter files.
- Metadata-free Markdown plus Pandoc-based DOCX, EPUB, PDF, and SMF export.
- Writing sessions, progress history, streaks, milestones, and git snapshots.
- Story structure templates for planning a new project.
- An optional prose-aware language server for navigation, completion, and
  reference cards.

The language-server approach is strongly informed by
[markdown-oxide](https://github.com/Feel-ix-343/markdown-oxide): an LSP is a
natural way to make Markdown-aware navigation, completion, references, and
rename feel native inside Neovim. Storyteller takes that idea into a
story-specific model of scenes, prose names, aliases, and reference cards.

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
context, or progress becomes useful. When you need a wider view, `:Story
timeline` follows story time, `:Story threads` follows setup and payoff fields,
and `:Story health` collects gentle review prompts without changing your draft.

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
| `:Story timeline` | Review scenes in story-time order. |
| `:Story threads` | Follow plot setups through their payoffs. |
| `:Story health` | Find loose ends and scenes worth revisiting. |
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

`storyteller-lsp` is the reference implementation of the
[Storyteller standard](https://github.com/AlejandroGomezFrieiro/storyteller) —
an open, editor-agnostic standard for Markdown-first fiction writing. Any
editor can speak the same protocol, and the same binary doubles as a headless
CLI (`storyteller-lsp check --project .`). See the
[language server guide](docs/language-server.md) for installation,
configuration, and the command-line tools.

## Architecture

Storyteller is three layers:

1. **The standard** ([`storyteller`](https://github.com/AlejandroGomezFrieiro/storyteller))
   — a vendor-neutral spec for how a fiction project lives on disk as Markdown,
   plus the LSP protocol and CLI contract.
2. **The reference implementation** — `storyteller-core` (a Rust library) and
   `storyteller-lsp` (the server and CLI), from the same repo.
3. **This plugin** — `storyteller.nvim` is the reference *consumer*. It talks to
   `storyteller-lsp` over LSP, with a native Lua fallback so the read-only views
   (outline, corkboard) and LSP-less setups keep working.

The plugin bundles a copy of the standard's canonical `schema.json`
(`lua/storyteller/schema.json`) so its metadata vocabulary never drifts from
the standard; the conformance fixtures in the standard repo pin both
implementations to the same behavior.

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

## Inspirations And Attribution

Storyteller is an independent, Markdown-first Neovim plugin. It is not
affiliated with, endorsed by, or a replacement for the projects below.

- [Scrivener](https://www.literatureandlatte.com/scrivener/features) inspired
  the binder, outliner, corkboard, targets, snapshots, compilation, and
  continuous-manuscript editing goals.
- [Kindling](https://kindlingwriter.com/features) inspired the rolling outline,
  reference-aware drafting, and conservative reference-detection model.
- [yWriter](https://www.spacejock.com/yWriter.html) reinforced the value of a
  chapter, scene, and reference workflow for novelists.
- [triforce.nvim](https://github.com/gisketch/triforce.nvim) inspired the
  rewarding progress language, activity heatmap, milestone presentation, and
  colorful dashboard direction.
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) and
  [Neorg](https://github.com/nvim-neorg/neorg) informed the modular Neovim and
  Markdown-first design.
- [markdown-oxide](https://github.com/Feel-ix-343/markdown-oxide) was a major
  inspiration for the LSP-based approach to Markdown navigation, completion,
  references, and rename. Storyteller applies those ideas to a writing project
  model built around scenes and reference cards.
- [obsidian-storyline](https://github.com/PixeroJan/obsidian-storyline) inspired
  arbitrary, user-defined reference categories.
- [morph.nvim](https://github.com/jrop/morph.nvim) is vendored as the reactive
  rendering library; [nui.nvim](https://github.com/MunifTanjim/nui.nvim) is an
  optional window and layout dependency.

Storyteller stores its own data model in plain Markdown and YAML. It does not
import, copy, or depend on those applications' proprietary project formats.
