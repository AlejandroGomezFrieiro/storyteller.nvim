# Projections — Editable Text Views of Project State

A *projection* is a canonical text rendering of project state that can be
edited like any text file and applied back to the Markdown sources. This is
the oil.nvim idea generalized: the view is the editor, and `:w` is the commit.

Projections are the contract between three consumers:

1. **storyteller.nvim** renders them into modifiable `acwrite` buffers (the
   primary editing surface).
2. **storyteller-tui** renders the same text with a modal layer using the
   grammar in `docs/interaction.md`.
3. **storyteller-lsp** will expose `render`/`apply` over its automation bus so
   every frontend shares one implementation (binding specified below).

Until the LSP ships the methods, the plugin's embedded Lua engine
(`lua/storyteller/projections/`) is the reference implementation.

## Engine API

```lua
require("storyteller.projections").render(name, prj)
-- -> { text = string, lines = string[], records = {...} }

require("storyteller.projections").diff(name, prj, old_lines, new_lines)
-- -> ops[]  -- or nil, err when the edit cannot be expressed

require("storyteller.projections").apply(name, prj, ops)
-- -> applied count | nil, err   -- atomic; snapshot-protected per interaction.md

require("storyteller.projections").commit(name, prj, old_lines, new_lines)
-- convenience: diff + apply in one step
```

## Operations

Every edit a user can make to a projection reduces to these ops:

| Op | Payload | Effect |
| --- | --- | --- |
| `reorder` | `{ files = { [rel] = {titles...} } }` | The complete per-file scene sequence for every chapter. Scenes may move between files freely; vacated files lose the moved blocks. Applied atomically after full validation. |
| `set_field` | `{ raw_title, key, value }` | Write one scene YAML field (`value = nil` removes it). The scene is located by its heading text. |
| `set_chapter_field` | `{ path, key, value }` | Write chapter frontmatter (e.g. `synopsis:`). |

Scene identity inside ops: the raw H2 heading text (render disambiguators
` #N` are stripped). Duplicate headings across chapters are rejected.

## Round-trip rules

- Rendering is deterministic: same project state → byte-identical text.
- Unknown body lines inside a card/row are ignored on diff, never written
  back destructively.
- Read-only annotations (e.g. word counts) are re-derived on render; edits to
  them are ignored, never written back.
- A diff that would delete or duplicate cards is rejected (`nil, err`) rather
  than guessed at.

## Formats

### `corkboard`

```
# Corkboard · 12 scenes

## The warning
file: chapters/01-harbor.md
status: draft
pov: Odysseus
location: Ithaca
target: 500
words: 412 / 500

## The storm
file: chapters/01-harbor.md
status: outline
beat: The fleet scatters
words: 380
```

- Card header: `## <title>`; the first body line `file:` is the card's
  address, oil.nvim-style: edit it (and/or move the card) to relocate a scene
  across chapter files.
- Body lines `key: value` map to scene YAML fields; only `file`, `status`,
  `pov`, `location`, `day`, `target`, `beat`, `goal`, `conflict`, `outcome`,
  `synopsis` are writable. `words:` is a read-only annotation.
- Moving cards (dd/p or J/K) and/or editing `file:` lines produces the
  `reorder` op; other field edits produce `set_field`.

### `timeline`

```
# Timeline · story time

day | title              | pov      | words
----+--------------------+----------+------
1   | The warning        | Odysseus | 412
2   | The storm          | Odysseus | 380
·   | The omen           | Athena   | 95
```

- One row per scene, sorted by numeric `day:`; unscheduled rows sort last with
  `·` in the day column.
- Writable cells: day (`nil` clears), title is identity-only, everything else
  read-only.
- `J`/`K` on a row shift its day ±1 (the frontend edits the cell; the op is
  always `set_day`). Row moves are normalized away — order follows days.

### `synopsis`

```
# Synopsis

# Chapter 1 — The Harbor
Convince the council to leave.

## The warning
The storm closes the harbor while Odysseus argues...
```

- Chapter H1s carry their frontmatter `synopsis:` beneath them; scene H2s
  carry their `synopsis:` field as wrapped prose until the next heading.
- Editing prose under a heading writes `set_synopsis`. Headings themselves are
  structural anchors: renaming a scene title here renames the H2 (v2).

### `metasheet`

```
# Metadata sheet

scene                          | status | pov       | location
ch01 :: The warning            | draft  | Odysseus  | Ithaca
ch01 :: The storm              | draft  | Odysseus  | Open sea
```

- One row per scene; each configured schema column is a writable cell mapping
  to `set_field`. Built for visual-block edits across many scenes.
- Rows are keyed by `chapter :: title`; row deletion/reordering is rejected.

## LSP binding (planned, storyteller standard repo)

The automation bus gains:

```
workspace/executeCommand:
  storyteller.renderProjection   [name, root]         -> { text }
  storyteller.applyProjection    [name, root, ops]    -> { ok } | error
  storyteller.diffProjection     [name, oldText, newText] -> ops[]
```

Frontends call render/diff remotely when a `storyteller` client is attached
and fall back to the embedded engine otherwise. Golden fixtures
(`tests/projections/`) pin the canonical text so both implementations stay
byte-compatible.

## Frontend responsibilities

| Concern | Neovim | TUI |
| --- | --- | --- |
| Render | extmark styling over canonical text | styled spans over the same text |
| Commit | `:w` → diff → apply | `S` stages, then applies |
| Insert mode | full editor | single-field editor, else `$EDITOR` |
| Snapshot | before multi-file applies | same, via core |
