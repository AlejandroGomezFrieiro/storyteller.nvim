# Notes Inline Plan — borrowed features for the annotations subsystem

> Status: **planned, not started**. Written against the tree as of
> 2026-08-22 (pre-rework). The joint rework (`docs/rework-plan.md`) does not
> touch the notes/annotations subsystem, so there is no overlap — but every
> file path and line number below must be re-verified against the
> post-rewrite tree before implementation begins. Treat them as pointers,
> not anchors.

## Why this plan exists

A survey of the annotation/bookmark plugin ecosystem (haunt.nvim,
marker-groups.nvim, fusen.nvim, todo-comments.nvim, the marks.nvim family)
found no plugin worth depending on in place of the custom notes system.
Every candidate stores ephemeral single-line dev bookmarks as JSON/SQLite
outside the project — the opposite of storyteller's identity:

- Project-local plain Markdown (`notes/annotations.md`, default from
  `config.notes_file`), shareable with editors/collaborators and versionable.
- Open/resolved status workflow; multi-line free-form bodies; captured quote
  excerpt.
- Quote-based drift-tolerant jumping (prose is edited heavily; recorded line
  numbers rot).
- Zero hard dependencies, Neovim 0.9+, exports never see notes.

What the survey did validate: three features that haunt/fusen/marker-groups
all share and we lack. This plan adds those three natively (~180 lines of
production Lua), keeping storage and the review board untouched.

## Locked design decisions

1. **No new dependencies, no nvim version bump.** Everything uses core APIs;
   extmarks follow the existing pattern in `lua/storyteller/ui/board_hl.lua`.
2. **Storage format does not change.** `notes.lua`'s parse/render/update
   logic stays byte-compatible; existing `notes/annotations.md` files keep
   working unchanged.
3. **Resolved notes stay visible inline but dimmed** (mirrors the review
   board's ✓ treatment), never auto-hidden.
4. **Inline display defaults on** (`eol`), opt-out via config — a feature
   nobody discovers is a feature that doesn't exist.
5. **No git-branch scoping** (haunt/fusen model) and **no hover-float mode**
   (fusen model) in this pass; both can be layered later without format
   changes.
6. **Motions are global `]n` / `[n`** that no-op outside a project, matching
   how `]t`/`[t` style motions behave in comparable plugins.

## Feature 1 — Inline ghost text in prose buffers

The one genuine gap: notes are currently invisible outside `:Story
annotations`. Show an end-of-line virtual text on lines that carry notes.

- **New module `lua/storyteller/ui/note_marks.lua`** (~80 lines):
  - Namespace `storyteller_notes`; paints eol extmarks:
    open → `◆ <title>`, resolved → `✓ <title>` (dimmed).
  - Highlight groups: `StorytellerKey` / `StorytellerDone` /
    `StorytellerMuted`, consistent with the review view's palette
    (`ui/views.lua` `M.annotations`).
  - Titles truncated ~40 chars; multiple notes on one line merge into a
    single mark joined by ` · `.
  - `refresh(bufnr)` clears the namespace and repaints.
- **Refactor `notes.lua`:** extract the outward ring search from `jump()`
  into `M.locate(entry) -> line?` — shared by jump, inline display, motions,
  and quickfix so drift handling lives in exactly one place.
- **Wiring:** autocmds (`BufReadPost`, `BufWritePost` for markdown buffers in
  a project) call refresh; mutations (`add`/`update`/`delete`/
  `toggle_status`) trigger repaint via lazy `require("storyteller.ui.note_marks")`
  to avoid circular requires (codebase style: views/compile lazy-required).
- **Config** (`lua/storyteller/config.lua` DEFAULTS):
  `notes_inline = "eol" | "none"`, documented next to `notes_file`.

## Feature 2 — Next/prev note motions

- `notes.jump_relative(prj, delta)` in `lua/storyteller/notes.lua`: notes
  sorted by (file, located line); cycles within the current buffer first,
  falls back to the first note when the buffer has none.
- Commands registered alongside the existing note commands in
  `lua/storyteller/commands.lua`: `:Story note-next`, `:Story note-prev`.
- Keymaps `]n` / `[n` set up in `lua/storyteller/init.lua`.

## Feature 3 — Quickfix export

- `notes.to_quickfix(prj)` in `lua/storyteller/notes.lua`: builds items
  `{ filename = root/file, lnum = located line, text = title .. " — " .. quote }`,
  loads them with `setqflist` and opens the list.
- Legacy `%%inline%%` annotations included too (prefixed `% `), so the
  quickfix mirrors the review board exactly.
- Command `:Story notes-qf`.

## Tests

Extend `tests/storyteller_spec.lua` (notes suite):

- `locate` finds quoted text after line drift (already covered for `jump`;
  assert the extracted helper directly).
- `to_quickfix` item shape: filename resolution, lnum location, legacy rows.
- `jump_relative` ordering and wrap-around.
- Inline display: after opening a chapter buffer with a note pointing at it,
  `nvim_buf_get_extmarks` returns the expected mark; resolved status flips
  the highlight group; `notes_inline = "none"` paints nothing.

## Docs

- `doc/storyteller.txt`: ANNOTATIONS section — new commands, keymaps,
  `notes_inline` option.
- `docs/user-guide.md` §"Leave Notes, Not Clutter": mention inline ghost
  text, motions, and quickfix.
- README bullet under "What You Get".

## Verification

- Full test suite, plus `luacheck` (`.luacheckrc`) and `stylua`
  (`.stylua.toml`) clean.
