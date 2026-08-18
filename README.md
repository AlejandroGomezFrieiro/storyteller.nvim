# storyteller

A Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.
Planned as a layered implementation (`PLAN.md`); current status in `PROGRESS.md`.
Pure Lua for Neovim 0.12, no hard dependencies (pandoc and telescope are
optional and detected at runtime).

Shipped as a nixvim module (`nixvim.nix`) and as a [`flake.nix`](./flake.nix)
package; consumed by `nixvim_config`'s `writing` derivation under the
`writing.storyteller.*` option namespace.

---

## Commands

The plugin registers `:Story*` user commands through its central registry
(`lua/storyteller/command.lua`). Materialize them with:

```lua
require("storyteller").setup({})
```

| Command | Description |
|---|---|---|
| `:StoryStatus` | Project stats: chapters, scenes, words, reference cards, target. |
| `:StoryOutline` | Outline of chapters with word counts + target progress. |
| `:StoryScrivenings[!]` | Compile all chapters into one editable buffer; `:w` writes back (`!` = recompile). |
| `:StoryCollection` | Saved-filter picker (pov/status/planning/unfinished/tagged). |
| `:StoryCollectionAdd` | Add the current scene to a named collection. |
| `:StoryCollections` | Browse saved collections like a filter. |
| `:StoryMeta` | Edit the current file's frontmatter in a scratch buffer. |
| `:StoryDetect` | Detect references project-wide; auto-link confident matches. |
| `:StoryDetectScene` | Detect references for the scene under the cursor. |
| `:StoryReferences` | Browse reference cards by type. |
| `:StoryCorkboard [filter]` | Open the scene corkboard (cards: `<CR>` open, `a` status, `d` unused, `R` rebuild). |
| `:StoryTargets` | Targets/dashboard report buffer. |
| `:StorySessionStart` / `:StorySessionEnd` | Begin/end a writing-session word counter. |
| `:StoryProgress` | Append/update today's delta in `progress.log`. |
| `:StorySnapshot [msg]` | Git snapshot (or file copy outside git). |
| `:StorySnapshots` | List snapshots. |
| `:StoryTemplate` | Pick a story structure and scaffold its chapters. |
| `:StoryExport [fmt]` | Compile the whole manuscript and export (docx, epub, pdf, smf). |
| `:StoryExportAll [fmt]` | Export the whole project into `build/`. |

Additional commands from earlier phases register the same way and appear
automatically once their modules load.

---

## Statusline

A live chapter/scene word count with target is exposed via
`lua/storyteller/status.lua` (`status.render()` / `status.context(bufnr)`) and
shipped as a drop-in lualine component (`lua/storyteller/lualine.lua`):

```lua
local lualine = require("storyteller.lualine")
-- append to an existing sections table best-effort (z/y/c, else z):
lualine.apply_to(LUALINE_SECTIONS)
```

Guarded by `writing.storyteller.lualine.enable` (nixvim flag, default true);
the module schedules the patch once lualine loads.

---

## Templates & Export

### Templates

Story structures ship as JSON under [`templates/`](./templates):

- `three-act.json` (`three-act-structure`) – 3 acts, 9 beats
- `heroes-journey.json` – 3 acts, the 12 monomyth stages
- `save-the-cat.json` – 3 acts, the 15 beat sheet
- `story-circle.json` – 3 acts, Dan Harmon's 8 steps
- `seven-point.json` – 3 acts, the 7 plot beats

`lua/storyteller/templates.lua`:

- `templates.list()` / `templates.entries()` – available structures
- `templates.load(name)` – decode `templates/<name>.json` (or global override dir)
- `templates.apply(prj, name)` – scaffold chapters

`apply` creates `chapters/<slug>.md` (one per beat) with frontmatter
`type: chapter` + `planning: flexible`, scenes as `## <title>` headings with
synopsis lines. Existing files are skipped. Override/Add by dropping JSON files
into a `templates/` dir and pointing `settings.templates_dir` at it.

### Export

`lua/storyteller/export.lua` compiles chapters to `build/` via pandoc:

- `export.file(prj, file, fmt)` – export a single markdown file.
- `export.manuscript(prj, fmt)` – stitch chapters into `build/manuscript.md`,
  then export (aliases: `project`, `export_project`).

Formats: `docx` (default), `epub`, `pdf`, `smf`. `smf` passes
`--reference-doc=<templates>/storyteller/reference.docx` (warns if absent).
If pandoc is missing, commands notify instead of erroring. When pandoc is
enabled in the nixvim module (`writing.storyteller.export.enable`), it is added
to `extraPackages`.