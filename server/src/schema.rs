// Runtime schema: types, field definitions, enums, and diagnostics toggles
// that drive completion, diagnostics, code actions, and the CLI. Loaded from
// three layers (embedded defaults < project file < client override) and merged
// with a shared recipe that is mirrored in Lua (storyteller.schema).

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

const EMBEDDED: &str = include_str!("../schema.json");

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
    pub kind: String, // enum | reference | reference-list | thread-key | string
    #[serde(default)]
    pub from: Option<String>, // enum source: "statuses" or an `enums` key
    #[serde(default)]
    pub ref_type: Option<String>, // reference type id (singular, e.g. "character")
    #[serde(default)]
    pub completion: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Schema {
    #[serde(default)]
    pub statuses: Vec<String>,
    #[serde(default)]
    pub status_next: HashMap<String, String>,
    #[serde(default)]
    pub enums: HashMap<String, Vec<String>>,
    #[serde(default)]
    pub scene_fields: Vec<String>,
    #[serde(default)]
    pub scene_field_defs: HashMap<String, FieldDef>,
    #[serde(default)]
    pub chapter_fields: Vec<String>,
    #[serde(default)]
    pub chapter_field_defs: HashMap<String, FieldDef>,
    #[serde(default)]
    pub list_fields: Vec<String>,
    #[serde(default)]
    pub scene_sentinel: String,
    #[serde(default)]
    pub reference_types: HashMap<String, RefType>,
    #[serde(default)]
    pub diagnostics: HashMap<String, bool>,
    #[serde(skip)]
    pub dir_index: HashMap<String, String>, // dir -> type id
}

impl Schema {
    pub fn defaults() -> Schema {
        let v: Value = serde_json::from_str(EMBEDDED).expect("embedded schema is valid JSON");
        Schema::from_value(v).expect("embedded schema deserializes")
    }

    pub fn load(root: Option<&Path>, init: Option<&Value>) -> (Schema, Vec<String>) {
        let mut warnings = Vec::new();
        let mut merged = serde_json::to_value(Schema::defaults()).unwrap_or(Value::Null);

        if let Some(root) = root {
            if let Some(path) = find_schema_file(root) {
                match std::fs::read_to_string(&path) {
                    Ok(text) => match serde_json::from_str::<Value>(&text) {
                        Ok(v) => merged = merge_values(merged, v),
                        Err(e) => warnings.push(format!("{}: {}", path.display(), e)),
                    },
                    Err(e) => warnings.push(format!("{}: {}", path.display(), e)),
                }
            }
        }

        if let Some(init) = init {
            merged = merge_values(merged, init.clone());
        }

        match Schema::from_value(merged) {
            Ok(schema) => (schema, warnings),
            Err(e) => {
                warnings.push(format!("merged schema invalid, using defaults: {e}"));
                (Schema::defaults(), warnings)
            }
        }
    }

    pub fn from_value(v: Value) -> Result<Schema, String> {
        let mut schema: Schema = serde_json::from_value(v).map_err(|e| e.to_string())?;
        // An entry with an empty dir is a deletion convenience (see merge
        // semantics); drop it and build the dir -> type-id index for the rest.
        schema.reference_types.retain(|_, t| !t.dir.is_empty());
        for (id, t) in &schema.reference_types {
            schema.dir_index.insert(t.dir.clone(), id.clone());
        }
        Ok(schema)
    }

    // Diagnostics toggle; unknown keys default on (so new rules are not silent).
    pub fn flag(&self, key: &str) -> bool {
        self.diagnostics.get(key).copied().unwrap_or(true)
    }

    pub fn ref_type(&self, dir: &str) -> Option<&RefType> {
        let id = self.dir_index.get(dir)?;
        self.reference_types.get(id)
    }

    pub fn dir_of(&self, type_id: &str) -> Option<&str> {
        self.reference_types.get(type_id).map(|t| t.dir.as_str())
    }

    pub fn scene_field_def(&self, key: &str) -> Option<&FieldDef> {
        self.scene_field_defs.get(key)
    }

    pub fn enum_values(&self, from: &str) -> Vec<String> {
        if from == "statuses" {
            return self.statuses.clone();
        }
        self.enums.get(from).cloned().unwrap_or_default()
    }

    pub fn next_status(&self, s: &str) -> String {
        self.status_next
            .get(s)
            .cloned()
            .unwrap_or_else(|| self.statuses.first().cloned().unwrap_or_default())
    }

    pub fn is_list(&self, key: &str) -> bool {
        self.list_fields.iter().any(|f| f == key)
    }
}

// --- Merge recipe (shared with Lua; keep in lockstep) ------------------------

fn is_removal(v: &Value) -> bool {
    match v {
        Value::Null => true,
        Value::Object(o) => o.get("remove").and_then(|r| r.as_bool()) == Some(true),
        _ => false,
    }
}

fn merge_values(base: Value, over: Value) -> Value {
    match (base, over) {
        (Value::Object(mut b), Value::Object(o)) => {
            for (k, v) in o {
                if is_removal(&v) {
                    b.remove(&k);
                } else {
                    let merged = merge_values(b.get(&k).cloned().unwrap_or(Value::Null), v);
                    b.insert(k, merged);
                }
            }
            Value::Object(b)
        }
        (_, over) => over, // scalars and arrays: override replaces
    }
}

fn find_schema_file(root: &Path) -> Option<PathBuf> {
    let a = root.join(".storyteller").join("schema.json");
    if a.is_file() {
        return Some(a);
    }
    let b = root.join("storyteller.schema.json");
    if b.is_file() {
        return Some(b);
    }
    let toml_path = root.join(".storyteller.toml");
    if toml_path.is_file() {
        if let Ok(text) = std::fs::read_to_string(&toml_path) {
            if let Ok(parsed) = text.parse::<toml::Value>() {
                let key = parsed
                    .get("storyteller")
                    .and_then(|s| s.get("schema"))
                    .or_else(|| parsed.get("schema"));
                if let Some(path) = key.and_then(|k| k.as_str()) {
                    let abs = root.join(path);
                    if abs.is_file() {
                        return Some(abs);
                    }
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("storyteller-schema-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn scalar_and_array_overrides_replace() {
        let base = serde_json::json!({ "statuses": ["a", "b"], "n": 1 });
        let over = serde_json::json!({ "statuses": ["c"], "n": 2 });
        let merged = merge_values(base, over);
        assert_eq!(merged["statuses"], serde_json::json!(["c"]));
        assert_eq!(merged["n"], serde_json::json!(2));
    }

    #[test]
    fn maps_merge_per_key() {
        let base = serde_json::json!({ "field_defs": { "a": { "type": "enum", "completion": true } } });
        let over = serde_json::json!({ "field_defs": { "a": { "completion": false } } });
        let merged = merge_values(base, over);
        assert_eq!(merged["field_defs"]["a"]["type"], serde_json::json!("enum"));
        assert_eq!(merged["field_defs"]["a"]["completion"], serde_json::json!(false));
    }

    #[test]
    fn null_and_remove_delete_keys() {
        let base = serde_json::json!({ "reference_types": { "item": { "dir": "items" } }, "x": 1 });
        let over = serde_json::json!({ "reference_types": { "item": null }, "x": { "remove": true } });
        let merged = merge_values(base, over);
        assert!(merged["reference_types"].get("item").is_none());
        assert!(merged.get("x").is_none());
    }

    #[test]
    fn empty_dir_deletes_type() {
        let base = serde_json::json!({ "reference_types": { "item": { "dir": "items", "label": "Item" } } });
        let over = serde_json::json!({ "reference_types": { "item": { "dir": "" } } });
        let merged = merge_values(base, over);
        let schema = Schema::from_value(merged).unwrap();
        assert!(!schema.reference_types.contains_key("item"));
    }

    #[test]
    fn load_precedence_embedded_project_init() {
        let dir = tmp_dir("precedence");
        let root = dir.join("proj");
        std::fs::create_dir_all(root.join(".storyteller")).unwrap();
        std::fs::write(
            root.join(".storyteller").join("schema.json"),
            r#"{ "statuses": ["project-only"] }"#,
        )
        .unwrap();

        let init = serde_json::json!({ "statuses": ["init-only"] });

        let (schema, warnings) = Schema::load(Some(&root), Some(&init));
        assert!(warnings.is_empty());
        assert_eq!(schema.statuses, vec!["init-only".to_string()]);

        let (schema, _) = Schema::load(Some(&root), None);
        assert_eq!(schema.statuses, vec!["project-only".to_string()]);

        let (schema, _) = Schema::load(None, None);
        assert!(schema.statuses.contains(&"draft".to_string()));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn toml_discovery_points_at_schema() {
        let dir = tmp_dir("toml");
        let root = dir.join("proj");
        std::fs::create_dir_all(root.join("config")).unwrap();
        std::fs::write(
            root.join("config").join("schema.json"),
            r#"{ "statuses": ["from-toml"] }"#,
        )
        .unwrap();
        std::fs::write(
            root.join(".storyteller.toml"),
            "[storyteller]\nschema = \"config/schema.json\"\n",
        )
        .unwrap();

        let (schema, warnings) = Schema::load(Some(&root), None);
        assert!(warnings.is_empty());
        assert_eq!(schema.statuses, vec!["from-toml".to_string()]);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn malformed_layer_is_skipped_with_warning() {
        let dir = tmp_dir("malformed");
        let root = dir.join("proj");
        std::fs::create_dir_all(root.join(".storyteller")).unwrap();
        std::fs::write(root.join(".storyteller").join("schema.json"), "{ not json").unwrap();

        let (schema, warnings) = Schema::load(Some(&root), None);
        assert_eq!(warnings.len(), 1);
        assert!(schema.statuses.contains(&"draft".to_string()));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn flag_defaults_and_dir_index() {
        let schema = Schema::defaults();
        assert!(!schema.flag("missing_id"));
        assert!(schema.flag("totally_unknown_flag"));
        assert_eq!(schema.ref_type("characters").map(|t| t.label.as_str()), Some("Character"));
        assert_eq!(schema.dir_of("character"), Some("characters"));
        assert_eq!(schema.enum_values("statuses").len(), 5);
    }
}
