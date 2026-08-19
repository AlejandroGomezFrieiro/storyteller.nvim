// Markdown + YAML-subset parsing for Storyteller. Mirrors the Lua
// `storyteller.meta.serde` module so the server and plugin agree on the
// metadata vocabulary.

use serde_yaml::Value;
use std::collections::HashMap;

pub fn scalar(s: &str) -> Value {
    let t = s.trim().trim_matches('"').trim_matches('\'');
    if t == "true" {
        return Value::Bool(true);
    }
    if t == "false" {
        return Value::Bool(false);
    }
    if let Ok(n) = t.parse::<i64>() {
        return Value::Number(n.into());
    }
    Value::String(t.to_string())
}

fn strip_prefix<'a>(s: &'a str, prefix: &str) -> Option<&'a str> {
    if s.starts_with(prefix) {
        Some(&s[prefix.len()..])
    } else {
        None
    }
}

// Parse a bare `key: value` map over [start, end). Handles `key:` + `- item`.
pub fn parse_map(lines: &[String], start: usize, end: usize) -> HashMap<String, Value> {
    let mut meta = HashMap::new();
    let mut i = start;
    while i < end {
        let line = lines[i].as_str();
        let trimmed = line.trim_start();
        if line.trim().is_empty() || trimmed.starts_with('#') {
            i += 1;
            continue;
        }
        if let Some(colon) = line.find(':') {
            let key = line[..colon].trim().to_string();
            let rest = line[colon + 1..].trim();
            if rest.is_empty() {
                let mut items = Vec::new();
                let mut j = i + 1;
                while j < end {
                    match strip_prefix(lines[j].trim(), "- ") {
                        Some(v) => {
                            items.push(scalar(v.trim()));
                            j += 1;
                        }
                        None => break,
                    }
                }
                meta.insert(key, Value::Sequence(items));
                i = j;
            } else {
                meta.insert(key, scalar(rest));
                i += 1;
            }
        } else {
            i += 1;
        }
    }
    meta
}

// Parse frontmatter (between ^--- and ^---). Returns (meta, body_start).
pub fn parse_frontmatter(lines: &[String]) -> Option<(HashMap<String, Value>, usize)> {
    if lines.first().map(|s| s.trim()) != Some("---") {
        return None;
    }
    let mut close = None;
    for i in 1..lines.len() {
        if lines[i].trim() == "---" {
            close = Some(i);
            break;
        }
    }
    let close = close?;
    let meta = parse_map(lines, 1, close);
    Some((meta, close + 1))
}

// Parse a scene YAML block that begins right after a `## ` heading. The block
// must start with ```yaml followed by `storyteller: scene`. Returns
// (meta, content_start).
pub fn parse_scene_block(
    lines: &[String],
    start: usize,
    end: usize,
) -> (HashMap<String, Value>, usize) {
    let mut first = start + 1;
    while first <= end && lines[first].trim().is_empty() {
        first += 1;
    }
    if first > end || lines[first].trim() != "```yaml" {
        return (HashMap::new(), start + 1);
    }
    let mut close = None;
    for l in (first + 1)..=end {
        if lines[l].trim() == "```" {
            close = Some(l);
            break;
        }
    }
    let close = match close {
        Some(c) => c,
        None => return (HashMap::new(), start + 1),
    };
    if lines.get(first + 1).map(|s| s.trim()) != Some("storyteller: scene") {
        return (HashMap::new(), start + 1);
    }
    let meta = parse_map(lines, first + 2, close);
    (meta, close + 1)
}

pub fn value_to_string(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    }
}

pub fn value_to_list(v: &Value) -> Vec<String> {
    match v {
        Value::Sequence(items) => items.iter().filter_map(value_to_string).collect(),
        Value::String(s) => vec![s.clone()],
        _ => Vec::new(),
    }
}
