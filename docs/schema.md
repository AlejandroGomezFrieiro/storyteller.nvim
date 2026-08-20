# Storyteller Schema Reference

The vocabulary Storyteller understands — scene/chapter fields, enum values,
reference types, and diagnostics toggles — is **schema-driven at runtime**. The
language server and the plugin load and merge the same schema with the same
recipe, so a project can reshape the tool without touching code.

## Layers

Three layers merge per key, lowest to highest precedence:

1. **Embedded defaults** — `server/schema.json` (mirrored by
   `lua/storyteller/schema.lua`'s `DEFAULTS`).
2. **Project file** — first match wins:
   - `.storyteller/schema.json`
   - `storyteller.schema.json`
   - `.storyteller.toml` → `[storyteller] schema = "path"` (or top-level
     `schema = "path"`), resolved relative to the project root.
3. **Client override** — `initializationOptions.schema`, an inline JSON value.
   In nixvim: `storyteller.lsp.schema = { … };`.

## Merge recipe

Implemented identically in Rust (`server/src/schema.rs`) and Lua
(`lua/storyteller/schema.lua`), asserted by the test suites:

- Both values are **objects** → merge **per key** (recurse), so partial
  overrides work (`scene_field_defs.pov.completion = false`).
- Anything else (scalar, array) → the override **replaces** the layer below.
  Arrays never concatenate.
- `null` or `{"remove": true}` → **delete** the key at any level.
- A `reference_types` entry with an empty/omitted `dir` is treated as a
  deletion.

A malformed layer is skipped with a warning (LSP `window/logMessage`, CLI
stderr, `vim.notify`) — it never crashes the server.

## Top-level shape

```json
{
  "statuses": ["outline", "draft", "revision", "done", "unused"],
  "status_next": { "outline": "draft", "…": "…" },
  "enums": {},
  "scene_fields": ["id", "status", "pov", "…"],
  "scene_field_defs": { "status": { "type": "enum", "from": "statuses", "completion": true }, "…": "…" },
  "chapter_fields": ["type", "pov", "…"],
  "chapter_field_defs": { "…": "…" },
  "list_fields": ["tags", "chars", "…"],
  "scene_sentinel": "storyteller: scene",
  "reference_types": { "character": { "dir": "characters", "label": "Character", "field": "chars", "body": ["Role", "Notes"], "min_fields": ["Role"] }, "…": "…" },
  "diagnostics": { "unknown_field": true, "…": "…" }
}
```

- **`scene_fields` / `chapter_fields`** are the canonical order *and* the
  allowlist (drive field-name completion and the `unknown_field` check).
- **`*_field_defs`** add typing to listed fields. A def for a field absent from
  the list is ignored; a listed field without a def is a free-form string.
- **`FieldDef.type`** is one of `enum` | `reference` | `reference-list` |
  `thread-key` | `string`.
  - `enum` uses `from` (an `enums` key or `statuses`).
  - `reference` / `reference-list` use `ref_type` (a singular `reference_types`
    id) for completion.
  - `thread-key` completes from existing `setup:`/`payoff:` values.
- **`enums`** is a map of `name → [values]`; a project can define POV lists,
  tonalities, etc. without a new field-def kind.
- **`diagnostics`** maps a rule to a bool. Unknown keys default **on**.
- **`setup` / `payoff`** are plot-thread keys: a thread is resolved when some
  scene carries `setup: <key>` and some scene carries `payoff: <key>` (either
  order). Unpaired keys are flagged; completion offers existing keys.

## Time semantics

- `time:` accepts any string. `day:`/`time_of_day:` are free-form siblings.
- A numeric `time:`/`day:` value is a "story day" ordinal and participates in
  numeric ordering; free text never order-compares.
- `timeline_regression` flags numeric values that decrease in document order
  within a chapter (and across the book). Mixed numeric/free-text in one chapter
  never warns by default.

## Per-client setup

- **Neovim (nixvim):** set `storyteller.lsp.schema` (inline JSON) or drop
  `storyteller.schema.json` in the project root.
- **Helix / VS Code / Emacs / Obsidian:** pass
  `initializationOptions = { schema = { … } }` to the `storyteller-lsp` server,
  or rely on a project schema file.
- **CLI:** `storyteller-lsp check --project .` reads the same project schema
  file — no editor involved.

## Writing a schema

In Neovim, `:Story schema write` dumps the merged defaults+project schema to
`storyteller.schema.json`, giving a starting point for customization. `:Story
schema` prints the merged result.

Example — add a POV list and a `factions` reference type, and turn off the
unknown-field warning:

```json
{
  "enums": { "povs": ["Odysseus", "Penelope"] },
  "scene_field_defs": { "pov": { "type": "enum", "from": "povs" } },
  "reference_types": {
    "faction": { "dir": "factions", "label": "Faction", "field": "factions" }
  },
  "diagnostics": { "unknown_field": false }
}
```
