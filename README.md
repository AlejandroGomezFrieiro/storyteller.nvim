# storyteller.nvim

> [!WARNING]
> Storyteller is in **early stages of development**. APIs, the command
> surface, the metadata schema, and the language server may change
> significantly between releases. Expect rough edges and breaking changes.

Storyteller is a Markdown-native project layer for long-form writing in
Neovim. It keeps chapters, scenes, reference cards, planning metadata, and
exports in ordinary files so the project remains usable without the plugin.

It is built to complement the writing configuration in
[`nixvim_config`](https://github.com/AlejandroGomezFrieiro/nixvim_config).
That repository's `storytelling` flake template enables Storyteller for new
projects.

## Start Here

Create a ready-to-write project with the template:

```bash
nix flake init -t github:AlejandroGomezFrieiro/nixvim_config#storytelling
nix develop
just draft
```

The template provides Neovim, Storyteller, Markdown tooling, Telescope,
Pandoc, grammar/style checking, and this project layout:

```text
chapters/                  chapter Markdown files
references/characters/     character cards
references/locations/      location cards
references/items/          item cards
references/organizations/  organization cards
outline/                   overview and beat sheets
treatment/                 treatments
research/                  research notes
words/dictionary.txt       project vocabulary
```

For detailed workflow guidance, read the
[user guide](docs/user-guide.md).

## Five Pillars

Storyteller is organized around five ideas:

- **Metadata** — one scene-centric schema. Each scene owns its workflow state
  in a YAML block; chapter frontmatter holds shared defaults. Legacy inline
  `- **POV:** …` bullets are read transparently and migratable.
- **Compilation** — a metadata-free longform manuscript, an editable two-way
  *Scrivenings* view that writes changes back to the chapter files, and Pandoc
  export.
- **Tracking** — writing sessions, a daily progress log, an activity heatmap,
  streaks, milestones, and safety snapshots.
- **Templating** — bundled story structures (three-act, hero's journey, save
  the cat, story circle, seven point).
- **UI** — a buffer-first, Scrivener-style workspace: binder, corkboard,
  outliner, inspector, and a dashboard. `nui.nvim` is optional; `morph.nvim`
  is vendored. Everything degrades to plain buffers.

## Commands

A single `:Story` command with subcommand-style arguments and completion:

| Command | Purpose |
| --- | --- |
| `:Story` | Open the dashboard. |
| `:Story outline` | Chapter outline with word counts and targets. |
| `:Story scenes` | Pick a scene. |
| `:Story next` / `prev` | Move between scenes. |
| `:Story corkboard [filter]` | Review scene cards. |
| `:Story resume` | Return to the last visited scene. |
| `:Story meta` | Edit the current scene's metadata. |
| `:Story status [status]` | Set (or cycle) the current scene status. |
| `:Story migrate` | Rewrite inline `- **Key:**` bullets as scene YAML. |
| `:Story compile[!]` | Open the editable continuous manuscript. |
| `:Story manuscript` | Write `build/manuscript.md` (metadata-free). |
| `:Story track` | Open the tracking dashboard. |
| `:Story session start\|end` | Track a writing session. |
| `:Story snapshot [message]` | Create a safety snapshot. |
| `:Story references` | Browse reference cards. |
| `:Story capture [type]` | Create a reference card from a visual selection (any `references/<type>/`). |
| `:Story detect [scene]` | Detect and link references. |
| `:Story idea` | Capture an idea into `research/ideas.md`. |
| `:Story ideas` | Open the ideas inbox. |
| `:Story template [name]` | Apply a story structure (with preview). |
| `:Story export [fmt]` | Export the manuscript (docx/epub/pdf/smf). |
| `:Story export all [fmt]` | Export each chapter. |
| `:Story snapshots` | List git snapshots. |
| `:Story workspace` | Toggle the binder + inspector workspace. |
| `:Story palette` | Command palette. |

Default keymaps put these under `<leader>s`:

| Key | Purpose |
| --- | --- |
| `<leader>s` | Dashboard |
| `<leader>so` | Outline |
| `<leader>sb` | Corkboard |
| `<leader>sc` | Compile |
| `<leader>st` | Tracking |
| `<leader>se` | Export |
| `<leader>sT` | Template |
| `<leader>sw` | Workspace |

## Project Model

Storyteller recognizes a project from a `.storyteller` marker, a git root with
the expected folders, or a directory containing `chapters/` or `references/`.

- A **chapter** is one file in `chapters/`.
- A **scene** is a `##` heading within a chapter.
- A **reference card** is a Markdown file below `references/<type>/`.
- Scene metadata lives in a YAML block immediately below the heading:

  ````markdown
  ## Scene 2 — The council refuses

  ```yaml
  storyteller: scene
  status: revision
  pov: Penelope
  location: Council hall
  goal: Convince the council to leave
  conflict: The storm closes the harbor
  outcome: The council refuses
  ```
  ````

- Chapter frontmatter holds shared defaults (`status`, `target`, `tags`).
- Files or folders beginning with `_` are excluded from indexing and export.

## Reference Detection

Put one card per entity in the matching references directory, with a title and
a `names:` alias list. `:Story detect` scans the project; `:Story detect
scene` reviews suggestions for the scene under the cursor. Detection is
case-insensitive, matches one-to-three-word phrases, and links high-confidence
matches conservatively.

## Text Interaction

Select a name in visual mode and press `<leader>sr` (or run
`:Story capture [type]`) to create a reference card for it — the selected prose
is left untouched and the new card opens for editing. Any subfolder of
`references/` is a reference type, so custom categories ("creatures", "lore",
…) need no configuration.

## Language Server

Storyteller ships a prose-aware language server (Rust/tower-lsp) that replaces
markdown-oxide for writing projects. It resolves bare character, location, item,
and organization names in prose — and any custom `references/<type>/` folder —
with no `[[wikilinks]]` needed, powering:

- `gd` → open the reference card for the name under the cursor
- `K` / hover → card summary
- `gr` → every mention across chapters
- completion → names, POV values, and status enums
- `<leader>o` → document outline (scene headings)
- code actions → create a reference card for an unknown name

The nixvim writing module wires it automatically when `storyteller.lspPackage`
is set; the standalone Nixvim module exposes `storyteller.lsp.package`.

## Installation Outside The Template

With a plugin manager:

```lua
require("storyteller").setup({
  picker = "auto",
  detect_on_save = true,
})
```

With the `nixvim_config` writing module, the configuration provides the plugin
package and keeps it disabled unless requested:

```nix
writing.storyteller = {
  enable = true;
  settings = {
    picker = "telescope";
    detect_on_save = true;
  };
};
```

The standalone `storytelling.nvim` Nixvim module uses the independent
`storyteller.*` namespace instead, so it can be imported alongside the
`nixvim_config` writing module without redeclaring `writing.storyteller.*`.

## Development Checks

Run the dependency-free regression suite with a recent Neovim:

```bash
nvim --headless -u NONE -l tests/storyteller_spec.lua
```

It covers marker-only project discovery, explicit setup precedence, safe
frontmatter mutation, scene indexing and word counts, multi-day progress
accounting, Scrivenings write-back synchronization and conflict protection,
frontmatter-free export, and inline-metadata migration.

VHS demos are reproducible from [`docs/vhs/`](docs/vhs/README.md).

## Inspirations And Attribution

Storyteller is an independent, Markdown-first Neovim plugin. It is not
affiliated with, endorsed by, or a replacement for the projects below.

- [Scrivener](https://www.literatureandlatte.com/scrivener/features) inspired
  the binder, outliner, corkboard, targets, snapshots, compilation, and
  Scrivenings-style whole-manuscript editing goals.
- [Kindling](https://kindlingwriter.com/features) inspired the rolling outline,
  reference-aware drafting, and the conservative non-AI reference-detection
  model.
- [yWriter](https://www.spacejock.com/yWriter.html) reinforced the value of a
  chapter/scene/reference workflow for novelists.
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim),
  [markdown-oxide](https://github.com/Feel-ix-343/markdown-oxide), and
  [Neorg](https://github.com/nvim-neorg/neorg) informed the workspace,
  Markdown-linking, and modular-Neovim design.
- [obsidian-storyline](https://github.com/PixeroJan/obsidian-storyline)
  (its extensible "Codex" model) inspired arbitrary, user-defined reference
  categories — any `references/<type>/` folder becomes a first-class
  reference type.
- [triforce.nvim](https://github.com/gisketch/triforce.nvim) inspired the
  tracking dashboard (activity heatmap, streaks, milestones).
- [morph.nvim](https://github.com/jrop/morph.nvim) is vendored as the
  reactive rendering library; [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
  is the optional window/layout dependency.

Storyteller stores its own data model in plain Markdown and YAML frontmatter;
it does not import, copy, or depend on those applications' proprietary project
formats.
