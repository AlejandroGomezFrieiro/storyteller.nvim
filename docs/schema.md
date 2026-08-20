# Project Schema Reference

Storyteller's schema is the vocabulary of a project. It defines which scene
and chapter fields are valid, which values can be completed, which reference
types exist, and which diagnostics are enabled.

Most projects can use the defaults. A project schema becomes useful when your
story has its own statuses, recurring fields, point-of-view list, or reference
categories.

## Where A Schema Comes From

The final schema is merged in three layers, from lowest to highest priority:

1. Storyteller's embedded defaults.
2. The first project schema file that exists:
   `.storyteller/schema.json`, `storyteller.schema.json`, or a path declared in
   `.storyteller.toml`.
3. A client-provided override passed as `initializationOptions.schema`.

The Neovim plugin and `storyteller-lsp` use the same merge rules.

## Merge Rules

- Objects merge recursively by key, so a small override is enough.
- Scalars and arrays replace the value below them; arrays are not concatenated.
- `null` or `{ "remove": true }` removes a key.
- A reference type without a directory is removed.
- Malformed schema layers are skipped with a warning instead of stopping the
  plugin or server.

## Schema Shape

The main keys are:

| Key | Purpose |
| --- | --- |
| `statuses` | Scene status values. |
| `status_next` | The order used when cycling statuses. |
| `enums` | Named lists such as points of view or tonalities. |
| `scene_fields` | Allowed scene fields and their completion order. |
| `scene_field_defs` | Types and completion behavior for scene fields. |
| `chapter_fields` | Allowed chapter frontmatter fields. |
| `chapter_field_defs` | Types and completion behavior for chapter fields. |
| `list_fields` | Fields that contain lists. |
| `scene_sentinel` | Marker used to identify a scene metadata block. |
| `reference_types` | Card directories, labels, fields, and body fields. |
| `diagnostics` | Individual diagnostic switches. |

A minimal top-level shape looks like this:

```json
{
  "statuses": ["outline", "draft", "revision", "done", "unused"],
  "scene_fields": ["id", "status", "pov", "location"],
  "scene_field_defs": {
    "status": { "type": "enum", "from": "statuses" }
  },
  "reference_types": {
    "character": {
      "dir": "characters",
      "label": "Character",
      "field": "chars"
    }
  }
}
```

## Field Definitions

`scene_fields` and `chapter_fields` are both the allowlist and the completion
order. A field definition adds typing to one of those fields:

- `enum` reads values from `from`, which names an `enums` key or `statuses`.
- `reference` and `reference-list` read names from a `reference_types` entry.
- `thread-key` completes from existing `setup:` and `payoff:` values.
- `string` is free-form text.

An unknown field is treated as a warning by default. A listed field without a
definition is treated as a free-form string.

## Custom Vocabulary

This example adds a point-of-view list, a faction card type, and disables the
unknown-field diagnostic:

```json
{
  "enums": {
    "povs": ["Odysseus", "Penelope"]
  },
  "scene_field_defs": {
    "pov": { "type": "enum", "from": "povs" }
  },
  "reference_types": {
    "faction": {
      "dir": "factions",
      "label": "Faction",
      "field": "factions"
    }
  },
  "diagnostics": {
    "unknown_field": false
  }
}
```

The corresponding project can use:

```yaml
pov: Penelope
factions:
  - The Council
```

Any folder below `references/` is already available as a reference type. A
schema entry is useful when you want custom labels, fields, card bodies, or
required card fields.

## Time And Plot Threads

`time`, `day`, and `time_of_day` are free-form fields. Numeric `time` or `day`
values can also be compared in document order; the `timeline_regression`
diagnostic reports when they move backwards.

`setup` and `payoff` identify plot threads. A thread is complete when one scene
sets it up and another scene pays it off. Unpaired keys are reported and are
available for completion.

## Inspecting The Merged Schema

`:Story schema` displays the merged schema. `:Story schema write` writes a
starting copy to `storyteller.schema.json` for editing.

The command-line checker reads the same project schema:

```sh
storyteller-lsp check --project .
```
