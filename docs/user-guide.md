# Storyteller — A Writer's Guide

Storyteller turns a plain-Markdown project into a full novel-writing engine:
outlines that show your progress, a "scrivenings" view of the whole manuscript,
reference cards that find themselves, a corkboard of your scenes, writing
targets, snapshots, and clean exports — all without leaving Neovim.

It is built for writers, not for computers. Everything you create is an
ordinary `.md` file you own. Nothing is hidden in a database; nothing is locked
away. If the plugin disappeared tomorrow, your manuscript would still be there,
readable in any text editor.

---

## The big idea

Think of your project as **four rooms in a house**:

| Room | What lives there | Folder |
|---|---|---|
| The outline | the plan: acts, beats, loglines | `outline/` |
| The draft | your prose, one file per chapter | `chapters/` |
| The corkboard | people, places, things, factions | `references/` |
| The study | research notes, treatments, vocabulary | `research/`, `treatment/`, `words/` |

You write in the **draft** room, and every other room exists to serve it. The
plugin's job is to keep those rooms talking to each other.

Storyteller **reads your frontmatter** (the small YAML block at the top of each
file) to understand each scene: whose point of view it's from, where it
happens, how far along it is, how many words it needs. That metadata powers the
outline, the corkboard, the filters, the targets — and the reference detection
that saves you from ever having to keep a "continuity bible" by hand.

---

## Quick start

### With nixvim (the intended way)

The plugin ships as a nixvim module. In a nixvim config that imports it:

```nix
{
  imports = [ inputs.storytelling_plugin.nixvimModules.default ];

  # enable with sensible defaults:
  writing.storyteller.enable = true;

  # all of these are optional and default to true:
  writing.storyteller.export.enable = true;   # adds pandoc
  writing.storyteller.lualine.enable = true;  # live word/target in the statusline
  writing.storyteller.picker.enable = true;   # uses telescope
}
```

If you're using the `nixvim_config` **storytelling template**, the layout,
snippets, and focus mode are already wired; Storyteller layers on top of that.

### With lazy.nvim (or any plugin manager)

```lua
{
  dir = "~/storytelling_plugin",   -- or a git url
  config = function()
    require("storyteller").setup({})
  end,
}
```

The plugin has **no hard dependencies**. Telescope, fzf-lua, lualine, ripgrep,
and pandoc are all optional; it falls back gracefully when they're missing.

---

## Your first session

### 1. Start a project

Make a folder with a `chapters/` directory (or create an empty `.storyteller`
file inside it). Storyteller finds the project from anywhere inside it — git
root, marker file, or just "this folder looks like a novel".

```
my-novel/
├── chapters/
├── references/
│   ├── characters/
│   ├── locations/
│   ├── items/
│   └── organizations/
├── outline/
├── research/
├── treatment/
└── words/
```

Don't want to build it by hand? **Start from a structure template instead:**

1. `:StoryTemplate`
2. Pick one — *Hero's Journey*, *Save the Cat*, *Three-Act*, *Story Circle*,
   or *Seven-Point*.

Storyteller scaffolds one chapter file per beat with scenes as `## Scene`
headings, all marked `planning: flexible` so you can tighten or loosen the
structure as you go.

### 2. Outline, then draft

Keep the big picture in `outline/overview.md`. As you draft, open a chapter and
just write. That's the whole trick: **the engine works while you work.**

- The statusline shows your live word count for the current scene and chapter,
  plus the chapter's target if you set one.
- Word counts appear next to each heading in the file as you type.
- `:StoryOutline` shows every chapter with its word count and a target progress
  bar. Jump to any chapter.

### 3. Know where you are

`<leader>st` (or `:StoryTargets`) opens the dashboard: words per chapter vs.
their targets, the manuscript total, and your last seven days from
`progress.log`. Start a writing session with `:StorySessionStart`, and when
you stop, `:StorySessionEnd` tells you how many words you wrote and appends
them to `progress.log` — one clean line per day.

### 4. Keep it safe

Before a big rewrite, `<leader>sn` (or `:StorySnapshot my rewrite`) commits the
whole project with a `storyteller:snapshot` message. You can always come back.
Inside a git repo it's a real commit on your current branch (no scary branch
switching); outside git it copies your work into `build/snapshots/<timestamp>/`.

---

## The engine, feature by feature

### Scrivenings — read and edit the whole manuscript as one document

Scrivener's killer feature, made two-way. `:StoryScrivenings` joins every
chapter into a single buffer with `# Chapter` separators. You can read it
straight through, proof it, and **edit it** — when you `:w`, each chapter's
section is written back into its own file. (The first run's edit doesn't
overwrite chapters you didn't touch.)

- `:StoryScrivenings!` force-recompiles a fresh copy.
- The joined view is a virtual buffer — it never creates or destroys files.

### Reference detection — your continuity bible, automated

Write a character card (using a public-domain example):

```markdown
## Odysseus
- **Role:** protagonist
```

Put `names: [Ody]` in its frontmatter to add aliases. Now when your
scene prose mentions "Odysseus", Storyteller notices:

- **On save**, it auto-links confident matches (full names are 100% confident;
  a first name is 70% if it's unique in your story) by adding them to the
  scene's frontmatter:
  ```yaml
  chars: [Odysseus]
  locs: [Ithaca]
  ```
- **Manually**, `:StoryDetect` scans the whole project; `:StoryDetectScene`
  checks the scene under your cursor and asks what to do (link / dismiss /
  link all).
- `<leader>sr` (`:StoryReferences`) browses every card by type.

The detection is clever but conservative: it matches whole words (up to three
in a row), ignores trailing punctuation (so `Alice,` matches `Alice`), and
never treats `Alice's` as `Alice`. If it guesses wrong, dismiss it — dismissed
names are remembered in the scene's `ignore:` list and won't be suggested again.

### Corkboard — your scenes at a glance

`:StoryCorkboard` (or `<leader>sb`) shows every scene as a card:

```
[draft]  Scene 1 — Arrival — Odysseus — 412 words · Ithaca
```

- `<CR>` open that scene at its heading.
- `a` cycle its status: outline → draft → revision → done.
- `d` mark it unused (taken out of the running without deleting it).
- `R` rebuild the board.
- `:StoryCorkboard flashback` filters to cards mentioning "flashback".

### Collections — "show me everything that needs work"

Like Scrivener's smart collections, but built from filters you already have:

`:StoryCollection` → pick a field (POV, location, status, planning, unfinished
scenes, tagged) → pick a value → get a list of matching scenes. Select one to
jump straight to it.

`unfinished` is especially useful on revision days: every scene that still has
an unticked `- [ ]` beat, gathered in one list.

You can also group scenes by hand: `:StoryCollectionAdd` while inside a scene,
then `:StoryCollections` to browse your lists.

### Rolling outline — plan at your own pace

Every scene carries a `planning` value: `fixed` (fully planned), `flexible`
(loosely planned), or `undefined` (discovery writing). Mark scenes
`undefined` and just write; tighten them to `fixed` as the shape of the story
becomes clear. Templates scaffold everything as `flexible` — decide how much
planning each scene needs, when it needs it.

---

## The metadata model (the one thing worth learning)

Frontmatter is the connective tissue. Set it by hand, or let the plugin do it.
You can also edit it in a safe scratch buffer with `:StoryMeta` (`:w` writes it
back and parses it — no corrupting your file).

```yaml
---
type: chapter          # chapter | scene | reference
pov: Odysseus          # whose head are we in
location: Ithaca
status: draft          # outline | draft | revision | done | unused
planning: flexible     # fixed | flexible | undefined
target: 5000           # word goal for this chapter
chars: [Odysseus]      # linked references (auto-detected)
locs: [Ithaca]
items: []
orgs: []
ignore: []             # dismissed detection suggestions
tags: [act2, flashback]
names: [Ody]           # aliases (on reference cards, for detection)
---
```

Every key is optional. The only thing you must remember: **the `#`-comments and
free-form keys are preserved**, so nothing you add by hand is ever lost.

### The folder conventions

- **One file per chapter**, filename-prefixed in order (`01_first.md`, ...).
- **Scenes** are `## Scene N — Title` headings inside a chapter (a chapter with
  no headings is treated as one continuous scene).
- **Reference cards** are one file per person/place/thing, `## Name — Role`.
- **Skip anything** by prefixing a file or folder with `_` (e.g.
  `chapters/_unused/`): the index and exports leave it alone.
- **Chapter targets** can live in frontmatter (`target: 5000`) or on a line
  like `> Target: 5000` if you prefer to keep them in the prose.

---

## Export — from manuscript to file

| Command | What it produces |
|---|---|
| `:StoryExport` | a compiled manuscript (all chapters, in order) |
| `:StoryExport docx` | `build/manuscript.docx` (default) |
| `:StoryExport epub` | `build/manuscript.epub` |
| `:StoryExport pdf` | `build/manuscript.pdf` (needs a LaTeX engine) |
| `:StoryExport smf` | Standard Manuscript Format DOCX (uses `reference.docx` if present) |
| `:StoryExportAll fmt` | one exported file per chapter |

Exports go into `build/`, which is always a derived, throwaway directory —
your source never changes. Without pandoc installed, the commands tell you so
instead of failing mysteriously.

---

## Keybindings

Everything under `<leader>s` (the "Writing" group in which-key):

| Key | Action |
|---|---|
| `<leader>so` | Outline |
| `<leader>ss` | Scrivenings |
| `<leader>sr` | Browse references |
| `<leader>sd` | Detect references in the current scene |
| `<leader>sb` | Corkboard |
| `<leader>st` | Targets / dashboard |
| `<leader>sn` | Snapshot |
| `<leader>sx` | Export |
| `<leader>sT` | Templates |

In the **corkboard** buffer: `<CR>` open scene, `a` cycle status, `d` mark
unused, `R` rebuild.

---

## A week in the life

**Monday** — picked a template, moved a few beats around in `outline/`.
**Tuesday** — drafting. Scene cards autocomplete characters from
`words/dictionary.txt`; `:StorySessionStart` and just write; the statusline
ticks toward the chapter target.
**Wednesday** — `:StoryCollection` → *unfinished*, ticked off every `- [ ]`
beat, then exported a draft with `:StoryExport` to send to a reader.
**Thursday** — realised the timeline is wrong. `:StorySnapshot before-timeline`,
then moved scenes around in the corkboard (`a` to mark them `revision`).
**Friday** — `:StoryDetect` found two locations I'd referenced but never made
cards for; made them, linked, done. `:StorySessionEnd` logged 4,300 words for
the week.

---

## Tuning it to you

`require("storyteller").setup({ ... })` accepts (all optional):

```lua
{
  markers = { ".storyteller", ".storyteller.toml" }, -- project root markers
  templates_dir = nil,           -- where to look for extra story templates
  autocmds = true,               -- project attach + outline + detect-on-save
  detect_on_save = true,         -- auto-link confident references on save
  detect_debounce = 300,         -- ms
  picker = "auto",               -- telescope | fzf | minipick | auto
  collections = { predicates = { "pov", "location", "status", "planning", "unfinished", "tagged" } },
}
```

Via the nixvim module, `writing.storyteller.settings` passes the same table, and
`writing.storyteller.{export,lualine,picker}.enable` gate the optional
integrations.

---

## Troubleshooting

- **"Not in a storytelling project."** — Storyteller couldn't find a `chapters/`
  or `references/` directory (or `.storyteller` marker) above your buffer. Create
  one, or open a file inside the project folder.
- **`:StoryExport` says pandoc isn't found** — install pandoc, or enable
  `writing.storyteller.export.enable` in nixvim so it's added for you.
- **Detection links the wrong thing** — `:StoryMeta` on that scene and add the
  name to `ignore:`, or delete it from `chars:`/`locs:`. It won't be suggested
  again.
- **Scrivenings shows my frontmatter** — that's normal; it's the real content
  of the chapter files. Use `:StoryScrivenings!` after edits to recompile.
- **Nothing shows in the statusline** — the lualine component is gated on
  `writing.storyteller.lualine.enable` (or requires lualine if you're not on
  nixvim). The word counts under headings work without it.

---

*Your words are plain text. The engine is just a helpful reader.*
