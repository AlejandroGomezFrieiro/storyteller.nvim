# Schema-Driven LSP Platform — Implementation Plan

Continuation plan for making `storyteller-lsp` schema-driven at runtime so it
can be used "in a multitude of ways for storytelling": an in-editor LSP, a
headless CLI/CI checker, and an automation bus for any client.

## Current state (already landed — do not replan)

Verified against the working tree (Aug 2026):

- Codex-style arbitrary reference types — any folder under `references/` is a
  type (`server/src/index.rs:265`, `reference_dirs`).
- Multi-word 1–3 n-gram resolution (`index.rs:392` `resolve_at`).
- Hover with match range, `gd`, `gr` over the alias set, rename, context-aware
  completion (prose vs YAML; per-field values for `status`/`pov`/`chars`/…)
  (`main.rs:526-703`).
- Diagnostics: "No reference card for X" + "«X» is never mentioned", published
  on open/save/watched-file changes (`main.rs:233-285`).
- Code actions: create card per type; link mention into the enclosing scene
  block (`main.rs:732-802`).
- UTF-16↔byte conversions are correct (`main.rs:42-52, 349-358`).
- `cargo test` runs in CI via `doCheck = true` (`flake.nix:35`); the flake pins
  `Cargo.lock` (`flake.nix:34`), so dependency changes must keep the lockfile
  minimal.
- The server does **not** advertise `workspace.didChangeWatchedFiles`
  (`main.rs:464-485`), so nvim never sends file-change notifications; the
  handler at `main.rs:521` is currently dead weight. Phase A fixes this.

## Locked decisions

1. **Time semantics: free text.** `time:` may be any string. Fast path: a
   numeric value (`time: 3`) is a "day ordinal" and participates in numeric
   ordering. Free-text values never order-compare; only a mixed-format
   heuristic may warn (configurable, default off). See "Time spec" below.
2. **TOML parsing: use the `toml` crate** for `.storyteller.toml` (add
   `toml = "0.8"` to `server/Cargo.toml` via `cargo add toml@0.8` — a full
   `cargo update` would churn the pinned lockfile). The Lua side uses
   `vim.tbl_parse(text, "toml")` (nvim ≥ 0.10) — no new dependency.
3. **`setup`/`payoff` are thread keys.** Free-form strings naming a plot
   thread, **not** scene ids. A thread is "resolved" when some scene carries
   `setup: <key>` and some scene carries `payoff: <key>` (either order, any
   scenes). Diagnostics flag unpaired keys; completion offers existing thread
   keys. This decouples plot threads from scene identity (renumbering scene
   ids never breaks a thread).
4. **Generic `enums` map.** The schema carries `enums: {name: [values]}`;
   an `enum`-typed field's `from` may reference any `enums` key or
   `statuses`. This makes custom value lists (POV lists, tonality, …)
   reachable from a project schema without a new `FieldDef` kind.
5. **File watching is registered.** The server advertises
   `workspace.didChangeWatchedFiles` (dynamic registration) and registers
   globs for the schema sources + `references/**` + `chapters/**` in
   `initialized()`. Previously rejected on the grounds that "any save
   triggers `rescan()`" — invalid, because the capability was never
   advertised, so nvim never sent notifications and schema edits made outside
   an open editor were only picked up by an unrelated save.

## Schema v2 shape

`server/schema.json` (defaults, embedded via `include_str!`) — additions in
**bold**:

```json
{
  "statuses": ["outline", "draft", "revision", "done", "unused"],
  "status_next": { "outline": "draft", "draft": "revision", "revision": "done",
                   "done": "unused", "unused": "outline" },
  "enums": {},
  "scene_fields": [
    "id", "status", "planning", "pov", "location", "time",
    "goal", "conflict", "outcome", "beat", "target", "setup", "payoff",
    "tags", "chars", "locs", "items", "orgs", "ignore"
  ],
  "scene_field_defs": {
    "status":   { "type": "enum", "from": "statuses", "completion": true },
    "pov":      { "type": "reference", "ref_type": "character", "completion": true },
    "location": { "type": "reference", "ref_type": "location", "completion": true },
    "chars":    { "type": "reference-list", "ref_type": "character", "completion": true },
    "locs":     { "type": "reference-list", "ref_type": "location", "completion": true },
    "items":    { "type": "reference-list", "ref_type": "item", "completion": true },
    "orgs":     { "type": "reference-list", "ref_type": "organization", "completion": true },
    "setup":    { "type": "thread-key", "completion": true },
    "payoff":   { "type": "thread-key", "completion": true },
    "time":     { "type": "string" }
  },
  "chapter_fields": [
    "type", "pov", "location", "status", "planning", "target",
    "chars", "locs", "items", "orgs", "ignore", "tags", "aliases", "names"
  ],
  "chapter_field_defs": {
    "status":   { "type": "enum", "from": "statuses", "completion": true },
    "pov":      { "type": "reference", "ref_type": "character", "completion": true },
    "location": { "type": "reference", "ref_type": "location", "completion": true },
    "chars":    { "type": "reference-list", "ref_type": "character", "completion": true },
    "locs":     { "type": "reference-list", "ref_type": "location", "completion": true },
    "items":    { "type": "reference-list", "ref_type": "item", "completion": true },
    "orgs":     { "type": "reference-list", "ref_type": "organization", "completion": true }
  },
  "list_fields": ["tags", "chars", "locs", "items", "orgs", "ignore", "aliases", "names"],
  "scene_sentinel": "storyteller: scene",
  "reference_types": {
    "character":     { "dir": "characters",     "label": "Character",     "field": "chars",
                       "body": ["Role", "Notes"], "min_fields": ["Role"] },
    "location":      { "dir": "locations",      "label": "Location",      "field": "locs",
                       "body": ["Atmosphere", "Notes"], "min_fields": [] },
    "item":          { "dir": "items",          "label": "Item",          "field": "items",
                       "body": ["Type", "Notes"], "min_fields": [] },
    "organization":  { "dir": "organizations",  "label": "Organization",  "field": "orgs",
                       "body": ["Wants", "Members", "Notes"], "min_fields": [] }
  },
  "diagnostics": {
    "unknown_field": true, "invalid_enum": true, "missing_id": false,
    "unresolved_setup": true, "unresolved_payoff": true,
    "timeline_regression": true, "duplicate_alias": true, "missing_min_fields": true
  }
}
```

Notes:

- Card creation keeps the current `body` array (renders `- **Role:** …`) — no
  `template` string; both are equivalent. Projects can override `body`.
- `reference_types` stays keyed by singular id; the server resolves
  `dir`↔`field` through this map (already does via `type_field`).
- `setup`/`payoff` are **thread-key** fields (locked decision 3) — the basis
  for plot-thread diagnostics.
- **Field lists vs field defs.** `scene_fields`/`chapter_fields` are the
  canonical order **and** the allowlist (drives field-name completion and
  `unknown_field`). `*_field_defs` only add typing to listed fields; a def for
  a field missing from the list is ignored (asserted by tests). A listed
  field without a def is a free-form string.
- `enums` defaults to `{}`. A project wanting a POV list writes, e.g.,
  `"enums": { "povs": ["Odysseus", "Penelope"] }` plus
  `"scene_field_defs": { "pov": { "type": "enum", "from": "povs" } }`.
- `status_next` should cover the keys of an overridden `statuses`; the
  fallback for a missing key is `statuses[1]` (existing `next_status`
  behavior, `schema.lua:126-128`).

## Discovery + merge precedence (per project root)

Layer 1 (lowest) → layer 3 (highest), per key:

1. Embedded defaults (`include_str!("../schema.json")`).
2. Project file, first match wins:
   - `R/.storyteller/schema.json` (when `.storyteller` is a directory);
   - `R/storyteller.schema.json` (flat convention);
   - `R/.storyteller.toml` → `[storyteller] schema = "path"` or top-level
     `schema = "path"` (TOML crate; path resolved relative to `R`).
3. Client override: `initializationOptions.schema` (an inline JSON value).
   This is a **new** mechanism — nothing in the repo uses it today;
   `nixvim.nix` gains an `lsp.schema` option for it (A6).

Merge semantics — **one shared recipe**, implemented identically in Rust and
Lua and asserted by tests on both sides:

- Both values are objects → merge **per key** (recurse). This makes partial
  overrides work (e.g. overriding only `scene_field_defs.pov.completion`).
- Anything else (scalar, array) → the override **replaces** the layer below.
  Arrays never concatenate.
- `null` or `{"remove": true}` → **delete** the key, at any level. This is
  how a project schema removes a declared type
  (`"reference_types": { "item": null }`) or a status.
- Convenience for `reference_types`: an entry with empty/omitted `dir` is
  treated as a deletion.

Rust sketch (the Lua version is in A5; keep them in lockstep):

```rust
fn is_removal(v: &Value) -> bool {
    matches!(v, Value::Null) || v.get("remove").and_then(|r| r.as_bool()) == Some(true)
}

fn merge_values(base: Value, over: Value) -> Value {
    match (base, over) {
        (Value::Object(mut b), Value::Object(o)) => {
            for (k, v) in o {
                if is_removal(&v) { b.remove(&k); }
                else { b.insert(k, merge_values(b.get(&k).cloned().unwrap_or(Value::Null), v)); }
            }
            Value::Object(b)
        }
        (_, over) => over, // scalars and arrays: override replaces
    }
}
```

Malformed layers never crash the server: each layer is parsed to `Value`
**and** validated by deserializing the merged result before it is accepted; a
bad layer is skipped with a warning (LSP: `window/logMessage`; CLI: stderr;
Lua: `vim.notify`). `Schema::load` therefore returns `(Schema, Vec<String>)`
warnings.

---

## Phase A — Runtime schema (core plumbing)

### A1. `server/src/schema.rs` (new module)

```rust
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Deserialize, Serialize, Default)]
pub struct RefType {
    pub dir: String,
    pub label: String,
    #[serde(default)]
    pub field: String,
    #[serde(default)]
    pub body: Vec<String>,
    #[serde(default)]
    pub min_fields: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize, Default)]
pub struct FieldDef {
    #[serde(rename = "type")]
    pub kind: String,                 // enum | reference | reference-list | thread-key | string
    #[serde(default)]
    pub from: Option<String>,         // enum source: "statuses" or an `enums` key
    #[serde(default)]
    pub ref_type: Option<String>,     // reference type id (singular, e.g. "character")
    #[serde(default)]
    pub completion: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Schema {
    #[serde(default)] pub statuses: Vec<String>,
    #[serde(default)] pub status_next: HashMap<String, String>,
    #[serde(default)] pub enums: HashMap<String, Vec<String>>,
    #[serde(default)] pub scene_fields: Vec<String>,
    #[serde(default)] pub scene_field_defs: HashMap<String, FieldDef>,
    #[serde(default)] pub chapter_fields: Vec<String>,
    #[serde(default)] pub chapter_field_defs: HashMap<String, FieldDef>,
    #[serde(default)] pub list_fields: Vec<String>,
    #[serde(default)] pub scene_sentinel: String,
    #[serde(default)] pub reference_types: HashMap<String, RefType>,
    #[serde(default)] pub diagnostics: HashMap<String, bool>,
    #[serde(skip)] pub dir_index: HashMap<String, String>, // dir -> type id
}

impl Schema {
    pub fn defaults() -> Schema;                                  // parse include_str once
    pub fn load(root: Option<&Path>, init: Option<&Value>) -> (Schema, Vec<String>);
    pub fn from_value(v: Value) -> Result<Schema, String>;        // builds dir_index
    pub fn flag(&self, key: &str) -> bool;                        // diagnostics toggle, default true
    pub fn ref_type(&self, dir: &str) -> Option<&RefType>;        // via dir_index
    pub fn dir_of(&self, type_id: &str) -> Option<&str>;          // inverse of dir_index
    pub fn scene_field_def(&self, key: &str) -> Option<&FieldDef>;
    pub fn chapter_field_def(&self, key: &str) -> Option<&FieldDef>;
    pub fn enum_values(&self, from: &str) -> Vec<String>;         // "statuses" or enums[from]
    pub fn is_list(&self, key: &str) -> bool;
}

fn find_schema_file(root: &Path) -> Option<PathBuf>;  // 3 fallbacks above
```

`from_value` is fallible because a project layer can replace `statuses` with a
non-array; `load` validates each layer (see merge section) and skips bad ones.
`dir_index` is `#[serde(skip)]` and filled in `from_value` from
`reference_types` entries with non-empty `dir` — no linear scans in hot paths.

`find_schema_file` sketch:

```rust
fn find_schema_file(root: &Path) -> Option<PathBuf> {
    let a = root.join(".storyteller").join("schema.json");
    if a.is_file() { return Some(a); }
    let b = root.join("storyteller.schema.json");
    if b.is_file() { return Some(b); }
    let toml = root.join(".storyteller.toml");
    if toml.is_file() {
        let text = std::fs::read_to_string(&toml).ok()?;
        let parsed: toml::Value = text.parse().ok()?;
        let key = parsed.get("storyteller").and_then(|s| s.get("schema"))
            .or_else(|| parsed.get("schema"));
        if let Some(path) = key.and_then(|k| k.as_str()) {
            let abs = root.join(path);
            if abs.is_file() { return Some(abs); }
        }
    }
    None
}
```

### A2. `server/src/main.rs` — live schema, watcher, init options

- `Backend.schema: Schema` → `RwLock<Schema>`; add
  `init_schema: RwLock<Option<Value>>` (from `initializationOptions`).
- `rescan()` (main.rs:77) becomes:

```rust
fn rescan(&self) -> Vec<String> {   // returns schema warnings
    let root = self.root.read().unwrap().clone();
    if let Some(root) = root {
        let init = self.init_schema.read().unwrap().clone();
        let (schema, warnings) = Schema::load(Some(&root), init.as_ref());
        *self.schema.write().unwrap() = schema;
        *self.index.write().unwrap() = index::scan(&root);
        // NOTE: scan() stays disk-driven (any references/ subfolder is a type);
        // the schema adds labels/min_fields/completion typing for those dirs.
        return warnings;
    }
    Vec::new()
}
```

  `rescan` stays sync; the async callers (`initialized`, `did_open`,
  `did_save`, `did_change_watched_files`) log returned warnings via
  `client.log_message(MessageType::WARNING, …)`. Re-parsing the schema on each
  rescan is fine (KB-sized file); add an mtime cache only if profiling shows
  it matters.

- `initialize` (main.rs:451): read `params.initialization_options`, store
  `schema` (if present) into `init_schema`, then rescan. Advertise:

```rust
workspace: Some(WorkspaceServerCapabilities {
    did_change_watched_files: Some(DidChangeWatchedFilesCapability::Options(
        DidChangeWatchedFilesRegistrationOptions {
            dynamic_registration: Some(true),
            ..Default::default()
        }
    )),
    ..Default::default()
}),
```

- `initialized` (main.rs:489): register the watcher, then publish:

```rust
// globs relative to the workspace root:
//   .storyteller/schema.json, storyteller.schema.json, .storyteller.toml,
//   references/**, chapters/**
self.client.register_capability(serde_json::json!({
    "registrations": [{
        "id": "storyteller-watch",
        "method": "workspace/didChangeWatchedFiles",
        "registerOptions": { "watchers": [ /* glob uris or relative globs */ ] }
    }]
})).await;
```

  (nvim honors dynamic registration and starts its own file watcher; the
  existing `did_change_watched_files` handler at main.rs:521 then actually
  fires — keep it as-is.)
- `card_content` (main.rs:148) — replace the hardcoded `match rtype` with a
  `schema.reference_types` `body` lookup (via `dir_index`), falling back to
  `["Notes"]`.
- `card_uri` (main.rs:214) — replace the hardcoded `match rtype` with the
  schema `dir` lookup, falling back to `rtype` itself (codex types). The
  current match arms are effectively dead for declared types (the function is
  called with folder names, which hit the codex fallback); this just removes
  the duplication.
- `type_field`/`type_label`/`type_dirs` (main.rs:170-212) read `self.schema`
  → adapt to the `RwLock` (and to `dir_index` for `type_field`).

### A3. `server/schema.json` — adopt the v2 shape above (field defs, `enums`,
`setup`/`payoff` as thread-key, `min_fields`, `diagnostics`). Keep `body`
arrays.

### A4. `server/Cargo.toml` — `cargo add toml@0.8` (minimal `Cargo.lock`
delta; the flake pins the lockfile).

### A5. Lua parity — `lua/storyteller/schema.lua`

Keep the public API tables (`M.statuses`, `M.reference_types`, `M.type_field`,
`M.type_label`, `M.type_body`, `M.is_list`, …) unchanged for all consumers;
add runtime loading behind them. The merge recipe must match A1 exactly
(including the array-replaces and deletion rules — in Lua, arrays are tables,
so the recipe must detect array-ness before recursing):

```lua
local cache = {}              -- root -> merged schema table
local DEFAULTS = { /* mirrors server/schema.json (asserted by the spec) */ }

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n == #t
end

local function is_removal(v)
  return v == nil or (type(v) == "table" and v.remove == true)
end

local function merge_values(base, over)
  if type(base) ~= "table" or type(over) ~= "table"
     or (is_array(base) and is_array(over)) then
    return over
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(over) do
    if is_removal(v) then out[k] = nil else out[k] = merge_values(base[k], v) end
  end
  return out
end
```

```lua
local function find_schema_file(root)  -- .storyteller/schema.json >
                                       -- storyteller.schema.json >
                                       -- [storyteller] schema= / schema= in
                                       -- .storyteller.toml (vim.tbl_parse)
```

(capture.lua:34 already resolves singular ids ↔ folders — no changes needed
there beyond making `schema.type_body` read from the merged table, which the
`apply()` below provides.)

```lua
local function apply(merged)  -- sync the M.* tables
  M.statuses, M.status_next = merged.statuses, merged.status_next
  M.enums = merged.enums or {}
  M.scene_fields, M.chapter_fields = merged.scene_fields, merged.chapter_fields
  M.scene_field_defs, M.chapter_field_defs = merged.scene_field_defs or {}, merged.chapter_field_defs or {}
  M.list_fields = {}
  for _, f in ipairs(merged.list_fields) do M.list_fields[f] = true end
  M.reference_types, M.scene_sentinel = merged.reference_types, merged.scene_sentinel
  M.diagnostics = merged.diagnostics or {}
end

function M.load(root)    -- cache + apply; nil-safe json decode; warns on bad file
function M.invalidate(root)
function M.write(root)   -- `:Story schema write`: dump the merged (defaults +
                         -- project) schema to storyteller.schema.json
```

Notes:

- `apply` is global (last-loaded root wins) — same as today's module tables.
  Every command entry loads the current project's root first, so this stays
  consistent.
- `M.write` cannot see LSP `initializationOptions` overrides (they are
  client-side only); it writes defaults+project, which is the intended
  bootstrap use.
- Plugin call sites: `project.current().root` on entry to `capture.run()`,
  `detect`, `references.panel`, and `:Story` dispatch — call
  `schema.load(prj.root)` once per command. `BufWritePost` on the three schema
  sources → `schema.invalidate(root)`.

New command `:Story schema [write]` in `commands.lua` (write the merged schema
/ print it).

### A6. `nixvim.nix` — `lsp.schema` option

```nix
lsp.schema = lib.mkOption {
  type = lib.types.nullOr lib.types.json;
  default = null;
  description = "Inline schema override, passed as initializationOptions.schema.";
};
```

Wired into the existing `vim.lsp.config("storyteller", …)` block as
`init_options` when non-null.

---

## Phase B — Field-typed LSP depth

### B1. Completion via field defs (`main.rs:652`)

The current `in_yaml` (main.rs:288) conflates chapter frontmatter and scene
blocks; they have different field sets. First add a block-kind helper
(`Frontmatter | Scene | OtherYaml | Prose` — frontmatter is between the
leading `---` pair; `Scene` is a ` ```yaml ` block whose first line is the
`scene_sentinel`), then:

```rust
let schema = self.schema.read().unwrap();
let idx = self.index.read().unwrap();
match self.block_kind(&lines, pos.line as usize) {
    Prose => self.name_items(&mut items),
    kind => {
        if let Some(field) = Self::field_on_line(&line) {
            let defs = match kind {
                Frontmatter => &schema.chapter_field_defs,
                _ => &schema.scene_field_defs,
            };
            if let Some(def) = defs.get(&field) {
                match def.kind.as_str() {
                    "enum" => for v in schema.enum_values(def.from.as_deref().unwrap_or("statuses")) {
                        push_enum(&mut items, v)
                    },
                    "reference" | "reference-list" =>
                        push_names_of_type(&mut items, &idx,
                            def.ref_type.as_deref().and_then(|t| schema.dir_of(t))),
                    "thread-key" => for k in index::thread_keys(&idx) {
                        push_thread_key(&mut items, k)
                    },
                    _ => {}
                }
            } else if schema.is_list(&field) || idx.reference_dirs.contains(&field) {
                // codex folder-named list fields (e.g. `creatures:`)
                push_names_of_type(&mut items, &idx, Some(&field));
            }
        }
        // Always offer field names for this block kind.
        for field in match kind { Frontmatter => &schema.chapter_fields,
                                  _ => &schema.scene_fields } {
            push_field(&mut items, field)
        }
    }
}
```

New `index::thread_keys(&Index) -> Vec<String>`: the deduped, sorted union of
all `setup`/`payoff` values across scenes (string scalars and list items).
`push_names_of_type` filters `idx.cards` by `rtype == dir` (all dirs when
`None`), keeping the existing `detail` = folder.

### B2. Diagnostics expansion (`main.rs:233` `publish_diagnostics`)

New pure functions (each `(index, schema) -> Vec<(Url, Diagnostic)>`), all
guarded by `schema.flag(...)`:

| Rule | Description | Gate | Severity |
| --- | --- | --- | --- |
| `unknown_field` | a key in a **scene YAML block** outside `scene_fields` (the `storyteller` sentinel excluded). Chapter frontmatter is free-form and never checked. | `unknown_field` | WARNING |
| `invalid_enum` | a value of an `enum`-typed field not in its `from` list (default case: `status:` vs `statuses`) | `invalid_enum` | WARNING |
| `missing_id` | a scene block without an `id:` field | `missing_id` | HINT (default off) |
| `unresolved_setup` | a scene with `setup: <key>` where no scene has `payoff: <key>` | `unresolved_setup` | HINT |
| `unresolved_payoff` | a scene with `payoff: <key>` where no scene has `setup: <key>` | `unresolved_payoff` | HINT |
| `timeline_regression` | numeric `time:` values that decrease in document order within a chapter (see Time spec) | `timeline_regression` | HINT |
| `duplicate_alias` | the same normalized alias key maps to ≥2 cards | `duplicate_alias` | HINT |
| `missing_min_fields` | a card of a declared type lacks **any** of its `min_fields` bullets | `missing_min_fields` | HINT |

Keep the two existing hint diagnostics unchanged. New ones default to `HINT`
severity except `invalid_enum`/`unknown_field` → `WARNING` (editors already
paint them; consistent with the "nudge, never bomb" philosophy — all are
configurable per-flag through the schema).

### B3. Code actions (`main.rs:732`)

Add, reusing existing `resolve_pos` / `link_edit` machinery:

1. **Extract selection → card + link** — one combined action (the delta from
   the existing "Create … card" actions, which create only): create the card
   for the selection (via `card_uri`/`card_content`), **and** apply
   `link_edit` into the enclosing scene block when one exists, and open the
   new card.
2. **Promote section → scene** — insert a ` ```yaml storyteller: scene ``` `
   block directly under the `## ` heading of the selection (or current line).
   Only add a `## Title` heading if the selection does not already start with
   one.
3. **Cycle status** — when the cursor is inside a scene block with a valid
   `status`, offer an action producing the next status using `status_next`.
4. **Insert setup/payoff** — for a scene block without `setup:`, offer one
   action per known thread key (from `index::thread_keys`) inserting
   `setup: <key>`; symmetric for `payoff:`.

### B4. Navigation polish

- `documentHighlight` — scan the current document for the resolved alias set
  (the existing `mentions()` logic restricted to one buffer) and return
  `DocumentHighlight { kind: TEXT }`. Register
  `document_highlight_provider: Simple(true)`.
- Semantic tokens (defer if time-boxed): legend
  `["name","field","status","string"]`; prose words that resolve → `name`,
  YAML keys in scene blocks → `field`, matched statuses → `status`. Not
  required for the other phases; mark optional.

---

## Phase C — Headless + automation

### C1. CLI in `main()` (one binary, argv dispatch before the server loop)

```rust
#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("report" | "check" | "index" | "completions" | "version" | "help") => {
            std::process::exit(cli::run(&args[1..]));   // sync; no async work
        }
        _ => {
            let stdin = tokio::io::stdin();
            let stdout = tokio::io::stdout();
            let (service, socket) = LspService::new(Backend::new);
            Server::new(stdin, stdout, socket).serve(service).await;
        }
    }
}
```

New `server/src/cli.rs` (sync; reuses `Schema::load`, `index::scan`, and the
B2 rules):

| Subcommand | Output | Exit code |
| --- | --- | --- |
| `report` | word totals, status distribution, per-scene field coverage, alias dupes | 0 |
| `check` | every diagnostic; `--json` for machine consumption | 0 clean / 1 on any WARNING-or-above / 2 usage or unreadable project |
| `index` | resolved name map + alias sets, `--json` | 0 |
| `completions` | schema-driven completion catalog (names, enums, fields, thread keys) | 0 |
| `version` / `help` | version string / usage | 0 |

Flags: `--project <dir>` (default `.`), `--json`. HINT diagnostics never fail
`check` — CI gates on warnings.

### C2. Abstraction: `server/src/diagnostics.rs`

Move the B2 rule functions here; both `publish_diagnostics` (via
`client.publish_diagnostics`) and `cli::check` consume
`project_diagnostics(&Index, &Schema) -> Vec<(PathBuf, Diagnostic)>`.
Publishing keeps the existing render (urls, hint severity).

### C3. `workspace/executeCommand` — automation bus

Initialize capability:

```rust
workspace: Some(WorkspaceServerCapabilities {
    execute_command_provider: Some(ExecuteCommandOptions {
        commands: ["storyteller.link", "storyteller.createCard", "storyteller.compile",
                   "storyteller.manuscript", "storyteller.detect",
                   "storyteller.statusCycle"].into_iter().map(Into::into).collect(),
    }),
    ..Default::default()
}),
```

Handlers (new `server/src/commands.rs`, mirror the Lua modules). **Mutating
commands never write to disk directly** — they return a `WorkspaceEdit` in the
result (or send `workspace/applyEdit`) so the client's unsaved buffers are
never clobbered:

| Command | Arguments | Returns |
| --- | --- | --- |
| `storyteller.link` | `{name, type}` | `{ok, edit}` — the `link_edit` WorkspaceEdit for the current scene |
| `storyteller.createCard` | `{name, type}` | `{ok, uri, content, edit}` — edit creates the card file |
| `storyteller.compile` | `{}` | `{ok, text}` — compiled manuscript (port of `compile.lua:strip_metadata` to `server/src/compile.rs`) |
| `storyteller.manuscript` | `{}` | `{ok, text}` — same, with `# ` chapter separators |
| `storyteller.detect` | `{scene?}` | `{ok, suggestions: [{name, type, confidence}]}` for a scene or project |
| `storyteller.statusCycle` | `{path, line}` | `{ok, old, new, edit}` |

### C4. Plugin delegation — `lua/storyteller/lsp.lua` (new)

```lua
local M = {}
M.client = function() return vim.lsp.get_clients({ name = "storyteller" })[1] end
M.available = function() return M.client() ~= nil end
M.command = function(name, args, cb)
  local client = M.client()
  if not client then return nil end
  -- Heavy commands must not block the main thread:
  if name == "storyteller.compile" or name == "storyteller.manuscript" then
    client:request("workspace/executeCommand", { command = name, arguments = args }, cb)
    return
  end
  return client.request_sync("workspace/executeCommand", { command = name, arguments = args }, 3000)
end
return M
```

`commands.lua` `:Story detect` / `:Story status` / `:Story capture` delegate to
`lsp.command(...)` when attached, falling back to the Lua path — matching the
intent already documented in the `capture.lua` file header.

---

## Time spec (free text, locked)

- `time:` accepts any string.
- **Fast path**: a `time` that is numeric is a "story day" ordinal; two
  numeric times order numerically. Note `time: 3` parses to `Value::Number`
  via `meta.rs` `scalar()`, so the helper takes a YAML value, not a string:
  `parse_story_day(v: &Value) -> Option<i64>` — `Number` → `as_i64()`;
  `String` → `trim().parse::<i64>()`; anything else → `None`.
- **Free text**: everything else — never order-compared.
- `timeline_regression` (default `on`):
  - within a chapter, for scenes whose `time` is numeric: warn if the value
    decreases vs the previous numeric time;
  - mixed numeric/free-text in one chapter: no warning by default
    (configurable `timeline_mixed_format` flag, default `false`).
- No other diagnostics depend on time ordering; setup/payoff and POV checks
  are order-independent.
- Rust helper `server/src/time.rs`: `parse_story_day` + unit tests (number,
  quoted number, free text, negative day, blank).

## Testing

Rust (`cargo test`, already wired via `doCheck = true`):

- `schema.rs`: `merge_values` (scalar/array replace, per-key map merge,
  partial FieldDef override, `null`/`{remove:true}` deletion, empty-`dir`
  deletion); `load` precedence embedded < project < init; discovery across all
  three sources (tmp dir fixtures); malformed layer skipped with warning;
  `flag()` defaults (`missing_id` false, unknown key true); `dir_index`.
- `time.rs`: `parse_story_day` over `Value::Number`/`String`/free text.
- `diagnostics.rs`: one fixture per rule (setup without payoff, payoff without
  setup, numeric time regression, duplicate alias, missing min field,
  unknown field in scene block, unknown key in frontmatter **not** flagged,
  missing id gated off by default).
- `cli.rs`: `check` on a fixture with a warning returns exit 1; hints alone
  return 0; `--json` parses; `version` prints.
- Integration (new `server/tests/stdio.rs`, spawning
  `env!("CARGO_BIN_EXE_storyteller-lsp")` — cargo builds the binary first, so
  this works under the flake's `doCheck`):
  - initialize with `initializationOptions.schema` defining a **custom type
    only in the client schema** → hover resolves and the create-card code
    action targets `references/<custom>/` (runtime schema drives code actions);
  - schema hot-reload: write a project schema file, send
    `didChangeWatchedFiles`, verify the new type resolves.

Lua (extend `tests/storyteller_spec.lua`):

- Extend the existing mirror test (spec lines 243-266, which already asserts
  `schema.lua` ≡ `server/schema.json`) to the v2 keys: `status_next`,
  `scene_field_defs`, `chapter_field_defs`, `enums`, `diagnostics`,
  `min_fields`.
- `merge_values` parity: a project schema with
  `reference_types.item = null` deletes the type; an array override replaces;
  `diagnostics.unknown_field = false` disables the gate.
- `.storyteller.toml` with `[storyteller] schema = "config/schema.json"` → a
  custom `factions` type is labeled/linked/created everywhere.
- `schema.load` caching + `invalidate`; `:Story schema write` round-trip
  (write → invalidate → load → `vim.deep_equal`).

Docs:

- Update `docs/language-server.md`: schema-override section + CLI section.
- New `docs/schema.md`: v2 reference, the shared merge recipe, per-client
  setup (nvim / helix / vscode / emacs / obsidian), CLI examples, time spec.

## Suggested order of work

Each step ends green: `cargo test` + headless spec
(`nvim --headless -u NONE -l tests/storyteller_spec.lua`).

1. `schema.json` v2 (A3) + `server/src/schema.rs` with `merge_values`/`load`
   (A1) — server still compiles with `RwLock<Schema>` and unchanged behavior.
2. A2: `init_schema`, card content from schema `body`, `card_uri` fix,
   watcher advertisement + registration.
3. A4: `cargo add toml@0.8` + `.storyteller.toml` discovery.
4. A5: Lua `schema.lua` load/apply + `:Story schema write` + extended mirror
   test.
5. A6: `nixvim.nix` `lsp.schema` option.
6. B1 field-def completion (smallest behavior change, high payoff).
7. B2 diagnostics module + C1/C2 CLI `check`/`report` (one extraction pays
   both).
8. B3 code actions, C3 executeCommand, C4 delegation.
9. Docs + VHS demo updates.

## Rejected / deferred (recorded here so they are not re-decided)

- `setup`/`payoff` as scene refs (pointing at scene ids) — rejected in favor
  of thread keys (locked decision 3); threads must survive scene
  renumbering.
- `template` string for card bodies — rejected; the `body` array is
  equivalent and overridable.
- Semantic tokens — optional, after B4 `documentHighlight`.
- Scrivener-style character arcs / relationship graphs — out of scope for the
  LSP; plugin-side feature.
