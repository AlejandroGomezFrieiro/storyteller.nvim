# storyteller.nvim

> A calm, Markdown-first writing workspace for Neovim.

Storyteller helps you move between the small and large parts of a long-form
project: a sentence in a scene, the shape of a chapter, the people and places
around it, and the manuscript as a whole. Your writing stays in ordinary
Markdown files. Storyteller adds the views and actions that make those files
comfortable to work with.

## Why?

As an engineer, I spend a good amount of time in Neovim writing and reading code, and have my own personalized configuration. I wanted to build this for my own personal usage, and as a way to create an open source standard that allows text editors like Neovim, Zed, etc to help authors without depending on other tools.

I also wanted to check how well a custom LSP would interact with prose, since I very much enjoyed [markdown-oxide](https://github.com/Feel-ix-343/markdown-oxide) as a way to do note-taking with markdown notes.


> [!WARNING]
> `storyteller.nvim` is in **early development**. Commands, APIs, metadata, and
> the language server may change between releases. Expect rough edges and
> occasional breaking changes while the project takes shape.

## AI disclaimer

Storyteller was developed with the aid of AI tools, but it has no AI
integration. Nothing in the plugin generates, rewrites, or "improves" your
prose, and it never calls out to a language model.

It is a set of tools for organizing and reviewing your own writing.
I do not believe in AI tools replacing artists, or any other person's job.
But as any new technology, there are clear consequences from its mere existence.

I understand many authors are against any usage of AI, and respect that. That is why
it is also important to add clear disclaimers of when they were used as part of a
social code-of-conduct of sorts.

As for any technology, I think there is a place for LLMs in the hands of people.
If you feel uncomfortable with using this tool because it was created with the aid of AI,
that is fine. But I do wish this tool could help you in your own projects,
or inspire similar ones.

## What You Get

- A project dashboard, outline, card-based corkboard, timeline, plot-thread
  planner, story-health review, workspace, and scene picker.
- Keyboard restructuring: move scenes across the story with `J`/`K` on the
  corkboard.
- File-backed annotations in plain Markdown (`notes/annotations.md`), captured
  from selections and linked back to their source.
- Saved searches ("collections") over scenes: `status:draft tag:war`.
- Distraction-free composition mode.
- Compile presets that keep drafts out of exports; Fountain export and
  best-effort Scrivener import.
- Snapshot diffing: see exactly what changed since before a revision pass.
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
| `:Story corkboard` | Review scenes as cards — an editable storyboard. |
| `:Story timeline` | Review scenes in story-time order — an editable storyboard. |
| `:Story synopsis` | Edit synopses in place (writes back to YAML). |
| `:Story metasheet` | Bulk-edit scene metadata with visual block. |
| `:Story threads` | Follow plot setups through their payoffs. |
| `:Story health` | Find loose ends and scenes worth revisiting. |
| `:Story workspace` | Toggle the binder and inspector. |
| `:Story tui` | Open the `storyteller-tui` cockpit in a terminal buffer. |
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
| `:Story diff` | Diff the working tree against a snapshot. |
| `:Story annotations` | Review `%%annotations%%`; they never reach exports. |
| `:Story collections` | Saved searches over scenes (`status:draft tag:war`). |
| `:Story compose` | Distraction-free composition mode. |
| `:Story import <file.scrivx>` | Import a Scrivener project (best effort). |
| `:Story fountain` | Export the manuscript as Fountain. |
| `:Story template` | Apply a story structure without overwriting files. |

On the corkboard, `J`/`K` move the scene card under the cursor through the
story order — across chapters too. Storyboards are editable text projections:
edit cards, rows, and synopses like any buffer and `:w` applies your changes
atomically to the Markdown sources (a git snapshot is taken first). The
shared key grammar lives in [docs/interaction.md](docs/interaction.md); the
projection formats in [docs/projections.md](docs/projections.md). Compile
presets live at `.storyteller/compile.json` (`include_statuses`,
`pandoc_args`, `title`) so drafts can be excluded from exports.

The default keymaps live under `<leader>s`; the complete list is in the
[user guide](docs/user-guide.md).

## The Language Server

The optional `storyteller-lsp` companion understands Storyteller projects. It
connects names in your prose to reference cards without requiring special link
syntax — the prose itself is the link:

- `K` shows a card summary.
- `gd` opens the matching card.
- `gr` finds mentions across the manuscript.
- Resolved names are highlighted in place via semantic tokens (`mention`).
- Completion suggests names and metadata values.
- Code actions create cards and connect them to scenes.

Outside a project the server still provides universal markdown features:
hierarchical symbols, folding, selection ranges, document links, and semantic
tokens for headings, emphasis, fences, comments, and tags. It negotiates
incremental sync and multi-root workspaces.

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
3. **The frontends** — `storyteller.nvim` is the reference *editing* consumer
   (prose, projections-as-buffers, LSP integration), and `tui/` in this repo is
   the reference *cockpit* (a ratatui app for dashboards, review, and
   `$EDITOR` handoff). Both speak the grammar in
   [docs/interaction.md](docs/interaction.md).

The plugin bundles a copy of the standard's canonical `schema.json`
(`lua/storyteller/schema.json`) so its metadata vocabulary never drifts from
the standard; the conformance fixtures in the standard repo pin both
implementations to the same behavior.

## The TUI

`storyteller-tui` (in [`tui/`](tui/)) is a keyboard-first ratatui companion:
a Dashboard cockpit (overall manuscript gauge, a navigable chapter binder, and
a word-flow sparkline), plus Corkboard, Timeline (axis-aware, with retiming),
Plotlines lanes/threads, and a Relations graph — all under one semantic theme.
`?` overlays the key grammar for the current view. Staged edits: mark changes
anywhere (`a` attach, `i` stage, `x` remove, `s` swap, `h/l` retime), review
the pending count in the footer, and apply them atomically with `S` (`u`
drops). `<CR>` opens the focused item in `$EDITOR`. Mouse scroll/click are
optional aliases. Build it with the flake (`.#storyteller-tui`) or `cargo build`
inside `tui/`. Theming: five presets (`dark`, `light`, `midnight`, `forest`,
`contrast`) with automatic truecolor → 16-color degradation and three glyph
tiers (`--glyphs safe|ascii|nerd`) — see [`tui/README.md`](tui/README.md).
`:Story tui` follows your editor's background; override with the
`tui_theme`/`tui_glyphs` options.

## Configuration

The defaults are intentionally useful:

```lua
require("storyteller").setup({
  picker = "auto",          -- "auto" | "telescope" | "fzf"
  tui_bin = "storyteller-tui", -- the cockpit binary for :Story tui
  tui_first = false,        -- :Story opens the embedded TUI cockpit instead of the dashboard
  detect_on_save = true,
  detect_debounce = 300,
  heatmap_weeks = 30,
})
```

`tui_first` makes the default `:Story` launch the full `storyteller-tui`
cockpit in a terminal buffer (when the binary is available) — the cockpit is
the preferred overview. The buffer dashboard stays one keystroke away
(`:Story dashboard`) and exposes its own `[T]` TUI cockpit action.

For project vocabulary, custom fields, reference types, and diagnostics, see
the [schema reference](docs/schema.md).

## Documentation

- [User guide](docs/user-guide.md): the complete writing workflow.
- [Language server guide](docs/language-server.md): prose navigation and
  completions.
- [Schema reference](docs/schema.md): customize project metadata and checks.
- [Roadmap](docs/roadmap.md): designed-but-unbuilt features (timeline editor,
  relationship map, and more).
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
affiliated with, endorsed by, or a replacement for the projects below. Many of them
have helped inspired what this plugin is, as well as the [storyteller](https://github.com/AlejandroGomezFrieiro/storyteller) standard.

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
- [oil.nvim](https://github.com/stevearc/oil.nvim) inspired the storyboard
  model: views are editable text projections of project state, applied on
  write.

Storyteller stores its own data model in plain Markdown and YAML. It does not
import, copy, or depend on those applications' proprietary project formats.
