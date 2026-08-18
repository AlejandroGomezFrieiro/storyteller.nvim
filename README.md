# storyteller.nvim

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

## What Storyteller Adds

- Chapter outline with live word counts and targets.
- Two-way Scrivenings: edit a compiled manuscript buffer, then `:write` back to
  individual chapter files.
- Reference cards and conservative name detection for characters, locations,
  items, and organizations.
- Corkboard and smart collections for reviewing scenes.
- Session totals, daily progress, and snapshots before revisions.
- Structure templates and Pandoc export.

The core has no mandatory plugin dependencies. It uses Telescope or fzf-lua
when present and falls back to `vim.ui.select`; Pandoc is needed only for
export.

## Project Model

Storyteller recognizes a project from a `.storyteller` marker, a git root with
the expected folders, or a directory containing `chapters/` or `references/`.

- A **chapter** is one file in `chapters/`.
- A **scene** is a `##` heading within a chapter.
- A **reference card** is a Markdown file below `references/<type>/`.
- Metadata lives in YAML frontmatter at the top of the **chapter file**.
- `- **POV:** ...`, `- **Location:** ...`, and `- **Beat:** ...` fields inside
  a scene remain supported for compatibility with the supplied snippets.
- Files or folders beginning with `_` are excluded from project indexing and
  export. Use `chapters/_unused/` for material you do not want in the draft.

The current metadata unit is the chapter file, not an individual scene. A
chapter status, target, tags, and detected reference links therefore apply to
the chapter containing those scenes. Scene headings supply the finer-grained
navigation used by the outline and corkboard.

Example chapter metadata:

```yaml
---
type: chapter
pov: Odysseus
location: Ithaca
status: draft
planning: flexible
target: 5000
chars:
  - Odysseus
locs:
  - Ithaca
tags:
  - act2
---
```

Use `:StoryMeta` to edit this frontmatter in a scratch buffer.

## Commands

| Command | Purpose |
| --- | --- |
| `:StoryStatus` | Display project totals. |
| `:StoryOutline` | Browse chapters with counts and targets. |
| `:StoryScrivenings[!]` | Open the editable continuous manuscript; `!` rebuilds it. |
| `:StoryMeta` | Edit current chapter metadata. |
| `:StoryDetect` | Scan all scenes and link high-confidence references. |
| `:StoryDetectScene` | Review suggestions for the scene under the cursor. |
| `:StoryReferences` | Browse reference cards. |
| `:StoryCorkboard [filter]` | Review scene cards; optionally filter their text. |
| `:StoryCollection` | Filter scenes by metadata, tags, or unfinished beats. |
| `:StoryCollectionAdd` / `:StoryCollections` | Maintain named, in-memory scene lists. |
| `:StoryTargets` | Open the project targets dashboard. |
| `:StorySessionStart` / `:StorySessionEnd` | Track a writing session. |
| `:StoryProgress` | Update today's entry in `progress.log`. |
| `:StorySnapshot [message]` | Commit a git snapshot or copy a non-git snapshot. |
| `:StorySnapshots` | List snapshots. |
| `:StoryTemplate` | Scaffold a bundled story structure. |
| `:StoryExport [docx\|epub\|pdf\|smf]` | Export the compiled manuscript through Pandoc. |

The nixvim writing integration assigns the common commands to `<leader>s`:

| Key | Purpose |
| --- | --- |
| `<leader>so` | Outline |
| `<leader>ss` | Scrivenings |
| `<leader>sr` | References |
| `<leader>sd` | Detect references in current scene |
| `<leader>sb` | Corkboard |
| `<leader>st` | Targets |
| `<leader>sn` | Snapshot |
| `<leader>sx` | Export |
| `<leader>sT` | Template |

## Reference Detection

Put one card per entity in the matching references directory. The title can be
an H1 or H2; aliases belong in `names` frontmatter:

```markdown
---
names:
  - Odysseus
  - Ody
---

## Odysseus
```

Detection is case-insensitive and checks one-to-three-word phrases. Full names
are high confidence; a character first name is considered only when it is
unique among the project's references. Dismissed suggestions are retained in
the chapter's `ignore` metadata so they are not repeatedly offered.

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

See [the user guide](docs/user-guide.md) for the writing workflow and
[`PLAN.md`](PLAN.md) for the technical roadmap.
