# Storyteller User Guide

Storyteller is a Markdown-native writing environment for Neovim. It is most
useful when it stays out of the way while you draft, and becomes visible when
you need to orient yourself: where the manuscript is, what remains unfinished,
which characters and locations matter in a scene, and whether a revision is
safe to attempt.

Your Markdown files remain the project. Storyteller builds views over them,
and a **language server** adds always-on, prose-aware navigation on top.

---

## What Storyteller adds

Storyteller is organized around five pillars:

- **Metadata** — one scene-centric schema. Each scene owns its workflow state
  in a YAML block; chapter frontmatter holds shared defaults.
- **Compilation** — a metadata-free longform manuscript, an editable two-way
  *Scrivenings* view, and Pandoc export.
- **Tracking** — writing sessions, a daily progress log, an activity heatmap,
  streaks, milestones, and git snapshots.
- **Templating** — bundled story structures (three-act, hero's journey, save
  the cat, story circle, seven point).
- **UI** — a buffer-first, Scrivener-style workspace: binder, corkboard,
  outliner, inspector, and a dashboard.

On top of those, a **prose-aware language server** resolves bare character,
location, item, and organization names in your prose — no `[[wikilinks]]`
required — powering `gd`, hover, references, completion, and code actions.

---

## Getting started

Create a ready-to-write project with the `nixvim_config` template:

```bash
nix flake init -t github:AlejandroGomezFrieiro/nixvim_config#storytelling
nix develop
just draft
```

`just draft` opens `outline/overview.md` in the configured writing Neovim. The
first activation provisions Neovim, Storyteller (plugin + language server),
Pandoc, Just, Vale, LTeX, and Markdown tooling.

The important folders are:

| Folder | Use it for |
| --- | --- |
| `chapters/` | One Markdown file per chapter. |
| `references/` | Character, location, item, and organization cards. |
| `outline/` | Overview, beat sheets, and structural experiments. |
| `treatment/` | A short prose version of the story. |
| `research/` | Notes and the ideas inbox. |
| `words/` | Names and vocabulary for completion. |

You can also drop an empty `.storyteller` marker into an existing project.
Files and folders beginning with `_` are excluded from indexing and export —
use `chapters/_unused/` as a parking place for cuts.

---

## Project model

- A **chapter** is one Markdown file in `chapters/`.
- A **scene** is a `##` heading within a chapter.
- A **reference card** is a Markdown file below `references/<type>/`
  (`characters/`, `locations/`, `items/`, `organizations/`).
- **Scene metadata** lives in a YAML block immediately below the heading.
- **Chapter metadata** lives in frontmatter and holds shared defaults.

Example chapter with one scene:

````markdown
---
status: draft
target: 5000
tags:
  - act1
---

# Chapter 1 — The Harbor

## Scene 1 — The warning

```yaml
storyteller: scene
status: draft
pov: Odysseus
location: Ithaca
time: Day 1, night
goal: Convince the council to leave
conflict: The storm closes the harbor
outcome: The council refuses
beat: A warning arrives too late.
```

The rain had not stopped for a week.
````

The `storyteller: scene` sentinel makes the block unambiguous. Field
resolution is scene → chapter → default: a scene's own `status` wins; a
chapter-wide `target` or `tags` list applies to every scene in that chapter.

### Migration

Older chapters that stored metadata as inline bullets (`- **POV:** …`) are
still read correctly. Convert them to scene YAML with `:Story migrate`.

---

## Drafting

Write chapters as normal Markdown. The `chapter` and `scene` LuaSnip snippets
from the template scaffold the frontmatter and scene YAML above; expand them
with your configured snippet key.

While you draft, the statusline shows the live word count and, when a target
is set, progress toward it. `:Story status` cycles the current scene through
`outline → draft → revision → done → unused`.

Edit the current scene's metadata in a scratch buffer with `:Story meta`
(`:w` writes it back to the scene YAML block).

---

## Moving between scales

- `:Story outline` — chapters with word counts and target progress bars.
- `:Story corkboard [filter]` — every scene as a compact card.
- `:Story track` — the tracking dashboard (below).
- `:Story scenes` — fuzzy-pick any scene; `:Story next` / `prev` step between
  them; `:Story resume` returns to the last scene you were in.
- `:Story workspace` — the three-pane workspace: binder (left), editor
  (center), inspector (right).

`:Story` (or `<leader>s`) opens the dashboard, which collects these plus
templates, references, detection, and export onto one screen.

### The corkboard

The corkboard is a temporary buffer, not a second copy of the manuscript.

| Key | Result |
| --- | --- |
| `<CR>` | Open the selected scene. |
| `a` | Cycle the scene's status. |
| `u` | Mark the scene unused. |
| `R` | Rebuild the board. |
| `q` | Close. |

### The workspace

`<leader>sw` toggles a binder on the left and an inspector on the right around
your prose. The binder is a chapter→scene tree; the inspector shows the current
scene's status, POV, location, beat, and goal/conflict/outcome. `<C-h>`/`<C-l>`
move between panes.

---

## Compilation and export

`sc` (or `:Story compile`) opens the **Scrivenings** view: every chapter joined
into one editable, continuous manuscript. Edit it like any buffer; `:w` writes
each changed chapter back to its source file. `:Story compile!` rebuilds it from
disk.

The *compiled* manuscript strips all metadata:

- `:Story manuscript` writes a metadata-free `build/manuscript.md`.
- `:Story export [fmt]` runs it through Pandoc: `docx` (default), `epub`,
  `pdf` (needs a LaTeX engine), or `smf` (Standard Manuscript Format DOCX via
  `reference.docx` when present).
- `:Story export all [fmt]` exports each chapter individually.

Exports land in `build/` and never modify your chapter files.

---

## References and detection

Put one card per entity in the matching directory. A card is a `names:` alias
list plus a title and notes:

```markdown
---
names:
  - Odysseus
  - Ody
---

## Odysseus

- **Role:** protagonist
- **Core want:** return home
```

`<leader>sr` (or `:Story references`) browses the cards. `:Story detect` scans
the project and links confident matches; `:Story detect scene` reviews
suggestions for the scene under the cursor. Detection is case-insensitive,
matches one-to-three-word phrases, and honors an `ignore` list.

### Creating cards from your prose

Select a name in visual mode and press `<leader>sr` (or run
`:Story capture [character|location|item|organization]`). Storyteller creates
the card under `references/<type>/`, seeds it with the selected name, and opens
it. The prose is left untouched.

---

## Ideas

`<leader>si` (or `:Story idea`) prompts for an idea and appends a dated bullet
to `research/ideas.md` without leaving your buffer. `:Story ideas` opens the
inbox. Ideas stay out of your prose and your word counts.

---

## Tracking

`:Story track` opens the tracking dashboard:

- total words and manuscript target;
- per-chapter progress bars;
- a **heatmap** of daily word output;
- current and longest **streaks**;
- **milestones** (first 1k words, a 50k-word novel, a 7-day streak, …).

Track a session with `:Story session start` and `:Story session end`; progress
is recorded in `progress.log` (idempotent per day).

### Snapshots

Before a large revision, run `:Story snapshot before-act-two`. Snapshots are
**git commits** whose subject begins `storyteller:snapshot`. They never create
files or copies. Outside a git repository, Storyteller offers to run `git init`
and otherwise does nothing. `:Story snapshots` lists them.

---

## Templating

`:Story template` offers five structures: Three Act, Hero's Journey, Save the
Cat, Story Circle, and Seven Point. It shows a preview of which chapter files
will be created and which already exist; `a` applies, `q` cancels. Applying is
idempotent — it never overwrites existing chapters.

---

## The language server

Storyteller ships a prose-aware language server (Rust) that replaces
markdown-oxide for writing projects. It needs no configuration — it attaches to
Markdown buffers under any `.storyteller` or git root.

Because it resolves **bare names in prose**, you don't have to wrap characters
or places in links. The server indexes your reference cards and their aliases,
then matches them as you type or navigate.

| Action | Key (writing profile) | What it does |
| --- | --- | --- |
| Go to definition | `gd` | Open the reference card for the name under the cursor. |
| Hover | `K` | Show the card summary (role, notes). |
| References | `gr` | List every mention of the name across chapters. |
| Rename | `<leader>lr` | Rename the entity across its card and every mention. |
| Completion | `tab`/`<C-n>` | Suggest character, location, item, and org names (and YAML fields/statuses) while you type. |
| Document outline | `<leader>o` | List the scene headings in the current chapter. |
| Code action | `<leader>la` | Create a reference card for an unknown name (character/location/item/org), or link a known name into the current scene's metadata (`chars`/`locs`/`items`/`orgs`). |
| Diagnostics | — | Hint at capitalized names with no card, and unused cards. |

The server resolves **single- and multi-word** names ("Odysseus" as well as
"Captain Greg") via the same 1–3-word n-gram matching as the plugin, and it
re-indexes on save and on watched-file changes.

Try it: open a chapter that mentions "Odysseus", place the cursor on the name,
and press `K`, `gd`, then `gr`.

The server is packaged as `storyteller-lsp`. The `nixvim_config` writing module
wires it automatically; the standalone Storyteller Nixvim module exposes
`storyteller.lsp.package` for the same purpose.

---

## Keymaps

All Storyteller keymaps live under `<leader>s`:

| Key | Action |
| --- | --- |
| `<leader>s` | Dashboard |
| `<leader>so` | Outline |
| `<leader>sb` | Corkboard |
| `<leader>sc` | Compile (Scrivenings) |
| `<leader>st` | Tracking |
| `<leader>sd` | Detect references |
| `<leader>sr` | References (normal) / create card from selection (visual) |
| `<leader>sm` | Edit scene metadata |
| `<leader>ss` | Cycle scene status |
| `<leader>sl` | Resume last scene |
| `<leader>se` | Export |
| `<leader>sT` | Template |
| `<leader>sw` | Workspace |
| `<leader>si` | Capture an idea |
| `<leader>sn` / `<leader>sp` | Next / previous scene |

All commands are also available through `:Story <subcommand>` with
tab-completion, or `:Story palette` for a searchable list.

---

## Configuration

The plugin is configured through `storyteller.setup({...})`:

```lua
require("storyteller").setup({
  picker = "auto",            -- "auto" | "telescope" | "fzf"
  ui = "auto",                -- "auto" | "morph" | "buffer"
  detect_on_save = true,
  detect_debounce = 300,
  heatmap_weeks = 30,
})
```

With nixvim:

```nix
writing.storyteller = {
  enable = true;
  settings = {
    picker = "telescope";
    detect_on_save = true;
  };
};
```

The UI is buffer-first. Storyteller vendors `morph.nvim` for its declarative,
flicker-free rendering and uses `nui.nvim` (optional) for windows and layouts;
without either, views degrade to plain buffers, so the plugin always works.

---

## Troubleshooting

**"Not in a storytelling project"**

Open a file under a folder containing `chapters/` or `references/`, or add a
`.storyteller` marker.

**No scene cards or scene detection**

Add `##` scene headings. A chapter without headings still counts toward word
totals, but it does not expose individual scene cards.

**`gd` / hover does nothing**

The name may not have a reference card, or it is not in the card's `names:`
list. Create the card (or add an alias), then try again — the server re-indexes
on save.

**A reference is not found**

Check that its card is in the correct reference folder and has a title. Add
aliases through `names:` and run `:Story detect scene` again.

**Scrivenings looks stale**

Run `:Story compile!` to rebuild the view.

**Export fails**

Ensure Pandoc is available. PDF requires a LaTeX engine. The Nix development
shell supplies Pandoc, but it intentionally does not pull in a large TeX
distribution by default.

**Snapshots do nothing**

Snapshots require a git repository. Run `git init` in the project (Storyteller
will offer to do it for you).

---

## The supporting tools

The template includes tools Storyteller deliberately does not replace:

- Fyler for file and binder navigation.
- Telescope for project search.
- LuaSnip for chapter, scene, character, place, item, and beat scaffolds.
- Goyo and Twilight for focused drafting.
- LTeX and Vale for grammar and style checking.
