# Writing Config — Roadmap Plan

Bring the `writing` Neovim derivation and the `#storytelling` flake template
closer to Scrivener / yWriter / Kindling parity **without adding custom
plugins**. Everything here is markdown-native, shell-scriptable, or plain
nixvim options.

## Principles

1. **No custom plugins.** Anything we can do with a shell script, a `just`
   recipe, a nixvim option, or a markdown convention wins.
2. **Markdown stays the source of truth.** Scripts only *read* markdown (for
   reports/views) or *generate derived artifacts* into `build/`.
3. **Opt-in.** Editor tweaks default to subtle; heavy features live behind the
   existing `writing.*` flags or in the template's `justfile`.

---

## Gap → Fix mapping

| Gap | Fix | Where | Cost |
|---|---|---|---|
| Scrivenings (read/proof mode) | `just scrivenings` → concatenate chapters into `build/manuscript.md` | template | low |
| Outliner w/ word counts | `just outline` → heading + wordcount tree | template | low |
| Storyboard / corkboard | `just storyboard` → table from scene metadata | template | low |
| Daily word log | `just progress` → append daily total to `progress.log` | template | low |
| Session/chapter targets | `# Target:` in `chapter` snippet + `just status` | both | low |
| Reference auto-detection | `just mentions <name>` → counts per chapter | template | low |
| Unused scenes | `_`-prefixed files skipped by export scripts | template | low |
| Smart collections | todo-comments + per-field grep presets | writing | low |
| Persistent undo / auto-save | `undofile`, `updatetime`, `autowrite` | writing | low |
| Live word count | lualine word-count section | writing | medium |
| ePub/PDF export | `WritingExport` gains format arg; pandoc `--to epub` | writing | low |
| Manuscript formatting | ship `reference.docx` (SMF) in template | template | medium |
| Write-back scrivenings, screenplay, Scrivener/yWriter import | **out of scope** (need plugins/scripts) | — | — |

---

## Phase 1 — `just` tooling (storytelling template)

Files: `templates/storytelling/justfile`, `templates/storytelling/flake.nix`
(pandoc already present).

### 1.1 `just outline`
Print the project as an outline: chapter heading + word count, then scenes.
- Implementation: iterate `chapters/*.md` in lexical order; `grep '^#'` for
  headings; `wc -w` per file.
- Acceptance: `just outline` shows `<Chapter file> — N words` lines.

### 1.2 `just storyboard`
Generate `build/storyboard.md` — one row per scene extracted from chapter
files. Parser: `grep` lines starting with `- **POV:**`, `- **Location:**`,
`- **Time:**`, `- **Beat:**` inside `## Scene` blocks.
- Acceptance: table with chapter, scene title, POV, location, time, beat, words.

### 1.3 `just scrivenings`
Concatenate `chapters/*.md` (in order, with chapter separators) into
`build/manuscript.md` for continuous reading/proofing.
- Acceptance: `build/manuscript.md` contains all chapters in outline order.
- Note: single-direction only (no write-back).

### 1.4 `just progress`
Append `YYYY-MM-DD <today's chapter words>` to `progress.log`; also print a
short 7-day summary.
- Acceptance: `progress.log` grows one line/day, idempotent for the same day.

### 1.5 `just status`
Print total words vs `Target:` sums; per-chapter `done/target` + `%`.
- Acceptance: reads `# Target:` lines (e.g. `# Chapter 1 — Title` + `> Target: 5000`).

### 1.6 `just mentions <name>`
Grep all chapters for `<name>`; report per-file counts.
- Acceptance: `just mentions Ada` prints counts and files.

### 1.7 unused scenes
Convention: files/dirs prefixed `_` (e.g. `chapters/_unused/`) are excluded
from `outline`, `storyboard`, `scrivenings`, `status`, and `export`.
- Acceptance: `_`-prefixed chapters are absent from all derived artifacts.

---

## Phase 2 — export breadth (writing config + template)

Files: `writing/default.nix`, `templates/storytelling/flake.nix`.

### 2.1 `:WritingExport [fmt]`
Extend the existing command to accept `docx` (default), `epub`, `pdf`.
`pandoc --to=epub3` for EPUB; `--to=pdf` needs a LaTeX engine (`pdflatex`) —
add `pkgs.texlive` only if `writing.export.pdf` is enabled (new flag, default
`false`).
- Keymaps: `<leader>ex` → docx; `<leader>ee` → epub; `<leader>ep` → pdf.

### 2.2 Standard Manuscript Format
Ship `templates/storytelling/reference.docx` (a pandoc reference doc styled
with 12pt Courier/Times, double-spaced, 1" margins) + a `just smf` recipe
`pandoc --reference-doc=reference.docx`.
- Acceptance: `just smf` produces a submission-ready `build/manuscript.docx`.
- Note: reference.docx generated once from a script (`scripts/make-reference.sh`)
  and committed.

---

## Phase 3 — editor ergonomics (writing config)

Files: `writing/default.nix`.

### 3.1 Persistence
- `opts.undofile = true`
- `opts.updatetime = 250`
- `opts.autowrite = false` (keep explicit saves; rely on undofile for safety)

### 3.2 Live word count
Add `plugins.lualine.enable = true` with a minimal statusline whose
`wordcount` section uses `vim.fn.wordcount().words`; keep the rest minimal.
- Acceptance: word count visible in statusline while typing.

### 3.3 Field presets
Which-key group `Writing` gains:
- `<leader>wf` → Telescope grep for `**POV:**` (all scene POVs)
- `<leader>wb` → Telescope grep for `- [ ]` (unfinished beats)
- `<leader>wt` → Telescope grep for `**Time:**`
- Acceptance: each opens a grep results list scoped to the project.

### 3.4 Chapter target line
`chapter` snippet emits `> Target: ` placeholder after the goal line.
- Acceptance: `just status` in Phase 1 picks these up.

### 3.5 Todo highlighting
`plugins.todo-comments.enable = true` to surface `- [ ]` / `- [x]` beats and
`TODO`/`IDEA` research notes. Add to default enabled list.

---

## Out of scope (recorded for later)

- **Two-way Scrivenings** — needs a plugin or a custom buffer mapper.
- **Screenplay (Final Draft)** — pandoc lacks a fountain reader; would need a
  fountain plugin.
- **Scrivener `.scriv` / yWriter `.yw5` import** — format reverse-engineering;
  suggest exporting those apps to Markdown/DOCX and importing via pandoc.
- **Mobile sync** — external (git remote / syncthing); no nvim-side work.

---

## Execution order & verification

1. Phase 1 recipes in template → verify with `just outline/storyboard/progress`.
2. Phase 3 options in `writing/default.nix` → verify `nix build .#checks.x86_64-linux.launch-writing`.
3. Phase 2 export + SMF → verify `:WritingExport` variants in the built nvim.
4. Update `writing/README.md` + `templates/storytelling/README.md` command tables.

Each step is small, independently reversible, and leaves the existing config
untouched.
