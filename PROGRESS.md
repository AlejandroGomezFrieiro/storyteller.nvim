# Storyteller — Implementation Log

A Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.
Log of implementation work against the plan in `PLAN.md`.

## Legend

- `[x]` done · `[~]` in progress · `[ ]` planned
- Each completed step records files touched and how it was verified.

---

## Phase 0 — Scaffolding

- [ ] Flake exposes `packages.default` (plugin) — usable and nvim-ready.
- [ ] `plugin/storyteller.lua` runtimepath entry.
- [ ] `init.lua` `setup(opts)` + lazy command registration + autocmds.
- [ ] `config.lua` defaults (+ user opts merge).
- [ ] `project.lua` root detection (git → marker → template layout).
- [ ] `metadata.lua` frontmatter read/merge/write (no external YAML).
- [ ] `index.lua` project scan (chapters, scenes, reference cards).
- [ ] `pickers/{init,telescope,fzf}.lua` picker-agnostic dispatch.
- [ ] `command.lua` `:Story*` namespace + `keymaps.lua` / which-key ledger.
- [ ] Smoke test: `:Story Status` / `:Story Outline` against the template layout.

### Phase 0 log

- _(empty — scaffold not yet started)_

---

## Phase 1 — Outline & live targets

- [ ] `outline.lua` heading tree + per-section word counts + `done/target`.
- [ ] `status.lua` pure data for lualine `{scene, chapter, target, session}`.
- [ ] Virtual-text word counts beside headings.
- [ ] lualine wiring.

---

## Phase 2 — Two-way Scrivenings & Collections

- [ ] `scrivenings.lua` `buftype="acwrite"` joined buffer + chunk write-back.
- [ ] `collections.lua` saved filters.
- [ ] Metadata scratch buffer + `vim.ui.input` editing loop.

---

## Phase 3 — References detection & Corkboard

- [ ] `detect.lua` Kindling-style name index + n-gram matching.
- [ ] `references.lua` suggestions picker + Link/Dismiss → frontmatter.
- [ ] `corkboard.lua` `nofile` buffer card-mode.

---

## Phase 4 — Targets & Snapshots

- [ ] `target.lua` session counter + `progress.log` + dashboard.
- [ ] `snapshot.lua` git snapshot + `:diffthis`.

---

## Phase 5 — Templates, Export & nixvim module

- [ ] `templates.lua` + `templates/*.json` (incl. seven-point).
- [ ] `export.lua` pandoc docx/epub/pdf/SMF.
- [ ] nixvim module `writing/storyteller` + README + docs.

---

## Cross-cutting decisions (locked)

- Name: `storyteller`, command prefix `:Story`.
- Detection trigger: auto on save (`BufWritePost`, debounced) + manual `:Story Detect`.
- Corkboard: `nofile` buffer card-mode.
- Collections: saved filters, no custom UI.
- Contract frozen in Phase 0 so parallel subagents can build safely:
  `metadata` get/set signature, `project.paths`, `pickers` API, `status` shape.