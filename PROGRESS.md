# Storyteller — Implementation Log

A Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.
Log of implementation work against the plan in `PLAN.md`.

> **Rework (0.3.0).** The plugin split into two frontends over one grammar:
> the Neovim plugin (editing) and `storyteller-tui` (a ratatui cockpit in
> `tui/`). Structural views became *storyboards* — editable text projections
> applied on write, oil.nvim-style. Contracts: `docs/interaction.md` and
> `docs/projections.md`. Details below under "Rework".

---

## Rework (0.3.0)
- [x] **TUI visuals lane** (`docs/tui-visual-plan.md` §16 1–4): `theme.rs`
      with semantic slots, five presets, termprofile capability detection and
      truecolor→16 degradation, glyph tiers; frame skeleton (rounded block,
      tab strip, footer key strip); dashboard progress bars, corkboard status
      glyphs + accent selection, timeline styling; `--theme/--background/
      --glyphs` flags; responsive breakpoints (<50/50–79/≥80); TestBackend
      matrix. `:Story tui` passes `--background` + `tui_theme`/`tui_glyphs`.
- [x] **Storyboard styling**: `ui/board_hl.lua` paints the projection buffers
      with extmarks (surface card bands, status colors, key/value splits,
      table headers) — text stays canonical; repaints on edits and commits.
      `StorytellerSurface`/`StorytellerSelection` palette slots added.
- [x] `docs/interaction.md` — the frozen key grammar shared by both
      frontends (keyboard-first, vim-like; mouse optional and TUI-only).
- [x] `docs/projections.md` — projection formats (corkboard, timeline,
      synopsis, metasheet), the op set (`reorder` / `set_field` /
      `set_chapter_field`), round-trip rules, and the planned LSP binding.
- [x] `lua/storyteller/projections/` — the projection engine: deterministic
      render, structural diff (rejects deletions/additions rather than
      guessing), and transactional apply with a pre-apply git snapshot.
      Cross-file scene moves are expressed by editing a card's `file:` line.
- [x] `ui/storyboard.lua` — projections as `acwrite` buffers: full vim
      editing, `J`/`K` block moves, `a` status cycle, `<CR>` open, `:w`
      applies atomically and re-renders.
- [x] `:Story synopsis` / `:Story metasheet` — new storyboards.
- [x] Collections land in the **quickfix list** instead of a custom view.
- [x] Deleted the reactive canvas stack: vendored `morph/` (2.4k lines),
      `ui/fibrous.lua`, `ui/react_{corkboard,timeline,graph}.lua`; the plain
      buffer renderer now serves every read-only view.
- [x] `:Story tui` — embeds `storyteller-tui` in a terminal buffer.
- [x] `tui/` — ratatui crate: dashboard, corkboard/timeline mirrors, `o`
      opens the focused scene in `$EDITOR +<line>`; optional mouse aliases;
      unit-tested project parser (the future `storyteller-core` seam).
- [x] Flake: `.#storyteller-tui` output; fibrous input removed.
- [x] Regression suite extended (167 checks, headless): projection
      render/determinism, field edits, cross-file reorder, round trip,
      deletion rejection, timeline retiming, synopsis write-back, metasheet.

---

## Redesign (0.2.0)
- [x] `schema.lua` — single source of truth for metadata vocabulary (fields,
      statuses, list/enum typing).
- [x] `meta/{serde,read,write}.lua` — unified metadata layer; scene-centric
      schema with chapter-frontmatter defaults; inline `- **Key:**` migration.
- [x] `index.lua` refactored onto the schema; adds `current_scene`/`open_scene`.
- [x] `compile.lua` — unified metadata-free longform + two-way Scrivenings +
      Pandoc export (replaces `scrivenings.lua` + `export.lua`).
- [x] `track.lua` — sessions, progress log, heatmap, streaks, milestones
      (replaces `target.lua`).
- [x] `commands.lua` — `:Story <subcommand>` dispatch + completion.
- [x] `ui/{init,views,dashboard,workspace,meta_form}.lua` — buffer-first,
      Scrivener-style views with a single highlight palette.
- [x] Vendored `morph.nvim` (pinned single file) under `lua/storyteller/morph/`.
- [x] `nui.nvim` declared as an optional dependency (flake + nixvim module).
- [x] Removed phase files and the now-folded `metadata`, `scene`, `scrivenings`,
      `export`, `target`, `outline`, `corkboard`, `collections`, `workflow`,
      `view`, and `command` modules.
- [x] Regression suite rewritten; 23/23 checks pass headlessly.

---

## Redesign round 2 (UI + LSP)

- [x] `capture.lua` — extract-to-reference: create a reference card from a
      visual selection (or `<cword>`), file + open only.
- [x] `ideas.lua` — project ideas inbox in `research/ideas.md`
      (`:Story idea` / `:Story ideas`).
- [x] `snapshot.lua` — git-only snapshots; non-git prompts to `git init`,
      never creates files. `:Story snapshots` lists commits.
- [x] `ui/init.lua` morph renderer — views render via vendored morph.nvim when
      available, with a plain-buffer fallback (verified headlessly).
- [x] `ui/views.lua` template preview (`templates.plan` → confirmable view).
- [x] `ui/workspace.lua` toggle open/close with window tracking.
- [x] `meta/read.lua` mtime cache + `index.scenes` unified onto `meta` resolution.
- [x] nixvim_config: lualine word-count wiring; drop `:WritingExport`.
- [x] `schema.json` — shared canonical schema; `server/` Rust crate
      (tower-lsp) with hover/definition/references/completion/document-symbols
      and create-card code actions; bare-name resolution, no wikilinks.
- [x] flake packages `storyteller-lsp`; nixvim_config wires it via
      `vim.lsp.config`, replacing markdown-oxide in the writing module.
- [x] Regression suite extended; 49/49 checks pass headlessly; Rust crate
      compiles and answers initialize/hover/definition/references over stdio.

---

## Legend

- `[x]` done · `[~]` in progress · `[ ]` planned
- Each completed step records files touched and how it was verified.

---

## Phase 0 — Scaffolding

- [x] Flake exposes `packages.default` (plugin) — usable and nvim-ready.
- [x] `plugin/storyteller.lua` runtimepath entry.
- [x] `init.lua` `setup(opts)` + lazy command registration + autocmds.
- [x] `config.lua` defaults (+ user opts merge).
- [x] `project.lua` root detection (git → marker → template layout).
- [x] `metadata.lua` frontmatter read/merge/write (no external YAML).
- [x] `index.lua` project scan (chapters, scenes, reference cards).
- [x] `pickers/{init,telescope,fzf}.lua` picker-agnostic dispatch.
- [x] `command.lua` `:Story*` namespace + `keymaps.lua` / which-key ledger.
- [x] Smoke test: `:Story Status` / `:Story Outline` against the template layout.

### Phase 0 log

- `flake.nix` exposes `packages.default` (derivation with `plugin/`, `lua/`,
  `doc/`, `templates/`) + `nixvimModules.default` stub (`nixvim.nix`).
- Backed by an **initial git commit** (flake source is a git input — untracked
  files are invisible to `nix build`).
- Lua modules: `config`, `project`, `metadata` (frontmatter read/merge/write),
  `index`, `events`, `pickers` (telescope/fzf/fallback + dispatch), `command`
  (registry → `:Story*`), `keymaps`, `commands/phase0` (`StoryStatus`,
  `StoryOutline`).
- Verified headlessly (nvim 0.12):
  - all modules `require` clean;
  - frontmatter round-trip + `metadata.push` dedupe work;
  - template smoke test: root detected at
    `nixvim_config/templates/storytelling`, chapter parsed (`First Contact`,
    words=119), `_`-prefixed references excluded;
  - plugin loads via rtp: `:StoryStatus`/`:StoryOutline` defined and run.
- `nix build .#packages.x86_64-linux.default` succeeds; result contains the
  full plugin tree.

---

## Phase 1 — Outline & live targets

- [x] `outline.lua` heading tree + per-section word counts + `done/target`.
- [x] `status.lua` pure data for lualine `{scene, chapter, target, session}`.
- [x] Virtual-text word counts beside headings.
- [x] lualine wiring (`lualine.lua` component + merge helper).
- [x] `:StoryOutline` enhanced + wired into `init.lua`.

### Phase 1 log

- `status.lua`: `context()` reads only the current buffer (scene words from
  nearest `## ` heading; chapter words from `wordcount()`; target from
  frontmatter `target:` or `# Target:` line). `render()` formats short string.
- `outline.lua`: `sections(bufnr)` → per-heading word counts (frontmatter- and
  code-fence-aware); `attach/refresh/detach` draw `"N words"` eol virt text;
  `setup_buffer()` debounces refresh on `TextChanged*/InsertLeave`; `pick(prj)`
  → Telescope/fzf outline with `done/target %` progress bars.
- `lualine.lua`: `component()` returns a ready lualine component; `apply_to()`
  appends it to an existing `sections` table.
- Verified headlessly: `status` returns `119` chapter words on the sample
  chapter; `sections` yields `Chapter 1 — First Contact = 113 words`;
  `outline.attach/setup_buffer` run without error.
- `events.lua` FileType markdown → `outline.setup_buffer(bufnr)`.
- `commands/phase1.lua` re-registers `:StoryOutline` to use `outline.pick()`.

---

## Phase 1 — Outline & live targets

- [ ] `outline.lua` heading tree + per-section word counts + `done/target`.
- [ ] `status.lua` pure data for lualine `{scene, chapter, target, session}`.
- [ ] Virtual-text word counts beside headings.
- [ ] lualine wiring.

---

## Phase 2 — Two-way Scrivenings & Collections

- [x] `scrivenings.lua` `buftype="acwrite"` joined buffer + chunk write-back.
- [x] `collections.lua` saved filters.
- [x] Metadata scratch buffer + `vim.ui.input` editing loop.

### Phase 2 log

- `scrivenings.lua`: compiles all chapters into one `acwrite` buffer (`:w` →
  `BufWriteCmd` → write-back of changed slices via chunk re-sync against
  chapter separators; snapshot-compare so unchanged chapters stay untouched).
  `:StoryScrivenings[!]` (bang recompiles). (Agent note: `nofile` can't be
  written — `acwrite` is the correct partner for `BufWriteCmd`.)
- `collections.lua`: predicates pov/location/status/planning/unfinished/tagged;
  frontmatter-first with inline `- **Key:**` fallback; named in-memory
  collections (`CollectionAdd` / `Collections`).
- `commands/phase2.lua`: `Scrivenings`, `Collection`, `CollectionAdd`,
  `Collections`, `Meta` (frontmatter scratch editor, `:w` reparses + writes).
- Verified headlessly (agent test): 25/25 assertions (compile, write-back
  propagation, registry entries).

## Phase 3 — References detection & Corkboard

- [x] `detect.lua` Kindling-style name index + n-gram matching.
- [x] `references.lua` suggestions picker + Link/Dismiss → frontmatter.
- [x] `corkboard.lua` `nofile` buffer card-mode.

### Phase 3 log

- `detect.lua`: Kindling port — normalized lowercase name index; full name 1.0,
  unique first name 0.7, locs/items/orgs 1.0; 1–3-word n-grams with trailing
  ASCII-punctuation trim (apostrophe excluded → `Alice's` never matches);
  filters already-linked + `ignore`; `link`/`dismiss`/`link_all` write
  `chars`/`locs`/`items`/`orgs`/`ignore` frontmatter.
- `references.lua`: `suggest` (picker + link/dismiss/all), `panel` (browse
  cards by type).
- `corkboard.lua`: `nofile`/`storyl-corkboard` buffer, cards per scene with
  status/pov/location/words; `<CR>` open, `a` cycle status, `d` unused, `R`
  rebuild.
- `commands/phase3.lua`: `Detect`, `DetectScene`, `References`, `Corkboard`.
- Verified headlessly: 17/17 assertions (detection incl. trailing comma,
  `link` → frontmatter, corkboard buffer, status cycle).
- **Integrator fixes applied:** reference cards are `## Name` (H2), so
  `index.parse_reference` now reads H1/H2 and extracts the primary name before
  `—`/`–`/`:`; `references.lua` passed `project` instead of `prj` to
  `link_all`; corkboard cursor was off-by-one (1-based line).

## Phase 4 — Targets & Snapshots

- [x] `target.lua` session counter + `progress.log` + dashboard.
- [x] `snapshot.lua` git snapshot + `:diffthis`.

### Phase 4 log

- `target.lua`: session start/end (word delta vs start total), `progress.log`
  (`YYYY-MM-DD <delta>`; idempotent per day — recomputes vs previous day's
  total), `dashboard()` → `nofile` report buffer with per-chapter words/target
  and last-7-days summary.
- `snapshot.lua`: git snapshot = `git add -A` + commit `storyteller:snapshot
  <ts> — <msg>` on the current branch (no branch switching); non-git fallback
  copies `chapters/`+refs into `build/snapshots/<ts>/`. `list()` via
  `git log --grep` or dirs.
- `commands/phase4.lua`: `Targets`, `SessionStart`, `SessionEnd`, `Progress`,
  `Snapshot`, `Snapshots`.
- (This phase's parallel agent returned empty; implemented directly by the
  integrator.)

## Phase 5 — Templates, Export & nixvim module

- [x] `templates.lua` + `templates/*.json` (incl. seven-point).
- [x] `export.lua` pandoc docx/epub/pdf/SMF.
- [x] nixvim module `writing/storyteller` + README + docs.

### Phase 5 log

- `templates.lua` + `templates/{three-act,heroes-journey,save-the-cat,
  story-circle,seven-point}.json` — Kindling-shaped `parts → chapters → scenes`
  trees; `apply()` scaffolds `chapters/<slug>.md` (frontmatter `type: chapter`
  + `planning: flexible`, scenes as `## ` headings), idempotent skip.
- `export.lua`: `file()` / `manuscript()` via pandoc → `build/`; formats
  docx/epub/pdf/smf; smf uses `--reference-doc` if present, warns otherwise.
- `nixvim.nix`: `writing.storyteller.{enable,settings,export,lualine,picker}`
  flags; adds plugin to `extraPlugins`, pandoc to `extraPackages` when export
  on, enables lualine/telescope, calls `storyteller.setup()` from config.
- Verified headlessly: 13/13 assertions (template decode/apply idempotency,
  export notify-fallback, command registration).

## Full-stack integration (integrator)

- [x] All 27 modules load cleanly; `setup()` twice is idempotent
  (`command.setup()` now guards re-materialization — the nixvim module calls
  setup from config AND the scheduled plugin load runs again).
- [x] End-to-end fixture test (25/25): project resolution, chapter/scene
  parsing, detection + link → frontmatter, scrivenings compile + write-back
  propagation, template apply, progress.log, git snapshot, corkboard.
- [x] Bugfixes: `export.run_pandoc` now checks `vim.v.shell_error` (was
  comparing output string); `parse_chapter` scans for H1 past frontmatter and
  trims titles; `parse_reference` handles H2 cards.
- [x] `nix build` succeeds; `nixvim.nix` parses.
- [x] Human-first user guide: `docs/user-guide.md` (linked from README).
- [ ] Pending: SMF `reference.docx` asset; `texlive` gating for `pdf` export
  behind a flag.

---

## Cross-cutting decisions (locked)

- Name: `storyteller`, command prefix `:Story`.
- Detection trigger: auto on save (`BufWritePost`, debounced) + manual `:Story Detect`.
- Corkboard: `nofile` buffer card-mode.
- Collections: saved filters, no custom UI.
- Contract frozen in Phase 0 so parallel subagents can build safely:
  `metadata` get/set signature, `project.paths`, `pickers` API, `status` shape.

---

## Post-review hardening

- [x] Explicit `setup(opts)` now merges later user options; plugin loading no
  longer races configuration with an automatic default setup.
- [x] `.storyteller` marker roots can bootstrap an empty project and run
  `:StoryTemplate`.
- [x] Metadata mutations preserve raw comments and unsupported YAML lines while
  rewriting only changed Storyteller fields; `:StoryMeta` writes its edited raw
  frontmatter back verbatim.
- [x] Scrivenings synchronizes clean open source buffers after write-back and
  marks a modified stale source buffer read-only before it can overwrite disk.
- [x] `progress.log` now records `date delta total`, fixing multi-day deltas;
  legacy two-column rows remain readable but are not used as a total baseline.
- [x] Manuscript export strips chapter frontmatter; `:StoryExportAll` now
  exports every chapter rather than duplicating the manuscript command.
- [x] Fixed reference action selection, corkboard frontmatter POV, saved-scene
  auto-detection cursor capture, and the unimplemented `minipick` setting.
- [x] Standalone Nixvim module uses `storyteller.*`, avoiding collision with
  nixvim_config's `writing.storyteller.*` adapter.
- [x] Added `tests/storyteller_spec.lua`; current suite: 24 passing checks.
- [x] Added reproducible Charmbracelet VHS demos in `docs/vhs/` and generated
  corkboard, Scrivenings, targets, and README promotional GIFs in `docs/assets/`.
- [x] Template `justfile` now owns only launch, linting, and git-branch helpers;
  Storyteller is the sole command surface for story-aware views and export.
