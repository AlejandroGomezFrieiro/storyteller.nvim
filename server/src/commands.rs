// Automation-bus helpers for `workspace/executeCommand`. The read-only helpers
// live here as pure functions; the document-dependent edits are produced in
// main.rs (which owns the buffer cache). Mirrors storyteller.detect on the
// Lua side.

use crate::index::{self, Index};
use serde_json::Value;

// Suggest reference links for every scene, as { name, type, confidence, path }.
pub fn detect_suggestions(index: &Index) -> Vec<Value> {
    let mut out = Vec::new();
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let prose = index::scene_prose(sc);
            let tokens = index::tokenize(&prose);
            for w in (1..=3usize).rev() {
                if tokens.len() < w {
                    continue;
                }
                for i in 0..=(tokens.len() - w) {
                    let phrase = tokens[i..i + w]
                        .iter()
                        .map(|t| t.word.as_str())
                        .collect::<Vec<_>>()
                        .join(" ")
                        .to_lowercase();
                    if let Some(entries) = index.names.get(&phrase) {
                        if let Some(e) = entries
                            .iter()
                            .max_by(|a, b| a.confidence.partial_cmp(&b.confidence).unwrap())
                        {
                            out.push(serde_json::json!({
                                "name": e.name,
                                "type": e.rtype,
                                "confidence": e.confidence,
                                "path": sc.path.to_string_lossy(),
                            }));
                        }
                    }
                }
            }
        }
    }
    // Dedupe by (name, type) keeping the highest confidence.
    out.sort_by(|a, b| {
        let c = b["confidence"].as_f64().unwrap_or(0.0)
            .partial_cmp(&a["confidence"].as_f64().unwrap_or(0.0))
            .unwrap();
        c
    });
    let mut seen = std::collections::HashSet::new();
    out.retain(|v| {
        let key = (
            v["name"].as_str().unwrap_or("").to_string(),
            v["type"].as_str().unwrap_or("").to_string(),
        );
        seen.insert(key)
    });
    out
}
