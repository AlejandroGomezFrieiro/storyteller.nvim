# Tutorial Plan — `:Story tutorial`

> Status: **planned, not started**. Written against the tree as of
> 2026-08-22 (pre-rework). The joint rework (`docs/rework-plan.md`) does not
> touch the onboarding surface, so there is no overlap — but every file path
> and line number below must be re-verified against the post-rewrite tree
> before implementation begins. Treat them as pointers, not anchors.
>
> Companion to `docs/notes-inline-plan.md`; both are independent of each
> other and of the schema rework.

## Why this plan exists

New users face a cold start: the README documents features, but nothing in
the plugin *teaches* them. Most commands no-op outside a project with only
"Not in a storytelling project." as guidance (`commands.lua::need`), and
there is no first-run experience. A guided, hands-on tutorial seeded from an
empty folder closes that gap while exercising the actual product — not a
slide deck about it.

## Research basis

- **vimtutor / vim-tutor-mode** (built-in `:Tutor`; upstream repo archived
  after incorporation into Neovim): lessons live in a document buffer and
  exercises edit that document. Linear, resumable, zero state machine. Not
  sufficient alone here: storyteller's features are project-level
  (corkboard moves, compile, notes review) and cannot be exercised on one
  scratch file — but its linear, resumable shape is worth keeping.
- **vim-be-good** (~4.5k stars): command-driven rounds starting from a clean
  slate; renders a round into the buffer, watches the user perform it,
  advances. Proves the "command starts the flow in place" model and shares
  our constraint of requiring a clean start.
- **Existing building blocks**: `project.current()` returns nil in empty
  folders (`lua/storyteller/project.lua` `has_layout` heuristic);
  `templates.apply` mkdirs and scaffolds without overwriting
  (`lua/storyteller/templates.lua`); JSON-per-project persistence under
  `stdpath("state")/storyteller/` (`lua/storyteller/resume.lua`); keyed
  read-only card rendering via `ui.view({ name, prj, build })`
  (`lua/storyteller/ui/init.lua`).

Design synthesis: **mission-based tutorial on a seeded mini-story** —
vim-be-good's watch-and-advance mechanics wrapped in vimtutor-style linear
resumability, rendered with storyteller's own card UI.

## Locked design decisions

1. **Missions verify real state where cheap; manual `<Tab>` always
   available.** Checks query genuine project state (a note exists, scene
   status changed, manuscript built). If a check misfires, `<Tab>` advances
   anyway — never trap the user inside the tutorial.
2. **Seed in cwd directly**, guarded: refuse when cwd matches the project
   layout heuristic, contains a `.storyteller` marker, or contains any files
   at all. Escape hatch `:Story tutorial {path}` seeds a subdirectory
   instead for users who want containment.
3. **Refuse inside existing projects.** The tutorial must never pollute real
   work; the guard is the same code path regardless of intent.
4. **Purpose-built seed story, not a stock template.** The bundled templates
   produce 5–12 chapter files — far too heavy for a walkthrough. The seed is
   a single chapter with three short scenes authored inline in Lua (same
   discipline as the scaffold in `notes.lua::read_or_new`).
5. **Single global progress file**
   `stdpath("state")/storyteller/tutorial.json`. Unlike `resume.lua`, this is
   not keyed by project root: tutorials happen wherever the user happened to
   be, and there is at most one active learner per machine in practice.
6. **Calm UI.** One mission card visible at a time via `ui.view`. No
   persistent floats, no timers, no global keymaps; the only autocmd work is
   a cheap check on `BufWritePost` for prose-affecting missions.
7. **No AI anywhere in the tutorial copy or flow**, consistent with the
   project stance stated in the README.

## Bootstrap flow

`:Story tutorial`

1. Detect state: existing project → notify refusal. Non-empty folder →
   notify refusal (suggesting `:Story tutorial <subdir>`). Empty folder →
   confirm prompt ("Create a practice project here?").
2. Scaffold layout using the same directory conventions as
   `project.paths_for` (`chapters/`, `references/{characters,locations,
   items,organizations}/`, plus `research/`, `build/`) and write a
   `.storyteller` marker so detection is unambiguous.
3. Write seed story files (idempotent: skip any file that already exists).
4. Open Mission 1.

Re-invocation later: resume at the first incomplete mission. After the last
mission: progress summary + replay option (replay resets progress JSON, does
not rewrite user-modified prose).

## Seed story

"The Lighthouse Keeper's Last Watch" — one chapter (`chapters/the-last-watch.md`)
with three scenes (~150 words each):

- Scene 1 status `draft`, POV Maren — includes a deliberately rough passage
  so note-taking has a target.
- Scene 2 status `outline`, POV different — gives the corkboard something
  to sort.
- Scene 3 status `outline` — tail end of the story.

Character name "Maren" appears in prose so reference-card capture
(`<leader>sr`) has a natural anchor, though capturing her card is a bonus
step, not a required mission.

## Missions

| # | Mission | Card teaches | Check |
|---|---|---|---|
| 1 | The dashboard | `:Story`, reading metrics | dashboard buffer opened during tutorial |
| 2 | Find your scenes | outline + corkboard views | either view opened |
| 3 | Write | open a scene, add prose | total word count > seed baseline |
| 4 | Status | `<leader>ss` / `:Story status` cycles | some scene status ≠ seed value |
| 5 | Metadata | `<leader>sm` meta form | POV field differs from seed |
| 6 | Leave a note | select text, `<leader>sN` capture | entry exists in `notes/annotations.md` |
| 7 | Review notes | `<leader>sa` board; resolve/delete | annotations review opened |
| 8 | Rearrange | corkboard `J`/`K` move | scene order ≠ seed order |
| 9 | Ship it | `:Story compile` + `:Story snapshot` | `build/manuscript.md` exists |

Wrap-up card: how to delete the practice folder, pointer to
`docs/user-guide.md` / `:help storyteller`, and `:Story template` for
starting a real structure in a fresh folder.

Checks run opportunistically (on relevant buffer writes and when a mission
card is opened), not on aggressive timers. Observational checks (1, 2, 7)
are satisfied by opening the corresponding view during an active tutorial;
the engine records that fact rather than instrumenting every view module —
one small hook in `ui.view` gated on tutorial-active keeps this contained.

## Module structure

- **New `lua/storyteller/tutorial.lua`** (~300 lines):
  - seed content constants;
  - mission table `{ id, title, body_lines, check(prj) -> bool }`;
  - bootstrap/guard logic (empty-folder matrix, subdir escape);
  - progress load/save (`vim.json`, same pattern as `resume.lua`);
  - card rendering via lazy-required `storyteller.ui.view` (avoids circular
    requires, matching codebase style).
- **`lua/storyteller/commands.lua`**: `register("tutorial", ...)` — command
  completion comes free from `register`.
- **`need()` message extension**: *"Not in a storytelling project. Run
  `:Story tutorial` to get started."*
- No default keymap additions; the tutorial is opt-in via the command.

## Tests

Extend `tests/storyteller_spec.lua`:

- Bootstrap guard matrix: empty dir scaffolds; non-empty refuses; existing
  project refuses; explicit subdir escape works.
- Seeding is idempotent (second run skips existing files).
- Each mission's `check()`: false on untouched seed, true on the simulated
  effect (write prose, flip status, create note, reorder scenes, build).
- Progress persistence round-trip and resume-at-first-incomplete ordering.
- Completion summary state.

## Docs

- `doc/storyteller.txt`: new TUTORIAL section (command, guard behavior,
  progress location, replay).
- README quick-start: first line becomes "run `:Story tutorial` in an empty
  folder".
- `docs/user-guide.md` intro links back to the tutorial.

## Verification

- Full test suite plus `luacheck` (`.luacheckrc`) and `stylua`
  (`.stylua.toml`) clean.
- Manual smoke test of all nine missions in a throwaway folder.
