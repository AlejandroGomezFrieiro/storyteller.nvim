// Project-wide story diagnostics beyond the bare-name and never-mentioned
// checks in main.rs: duplicate scene ids, incomplete beats, pacing, character
// coverage, timeline ordering, unknown/invalid fields, plot-thread resolution,
// alias collisions, and required card fields.
//
// Pure functions over the index + schema; main.rs maps them to LSP diagnostics
// and the CLI (`storyteller-lsp check`) consumes the same rules.

use crate::index::{Index, RefCard, Scene};
use crate::meta;
use crate::schema::Schema;
use serde_yaml::Value;
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Hint,
    Warning,
}

#[derive(Clone, Debug)]
pub struct ProjectDiagnostic {
    pub path: PathBuf,
    pub line: u32,
    pub start_byte: usize,
    pub end_byte: usize,
    pub severity: Severity,
    pub message: String,
}

pub fn project_diagnostics(index: &Index, schema: &Schema) -> Vec<ProjectDiagnostic> {
    let mut out = Vec::new();
    if schema.flag("duplicate_id") {
        duplicate_ids(index, &mut out);
    }
    if schema.flag("incomplete_beat") {
        incomplete_beats(index, &mut out);
    }
    if schema.flag("over_target") {
        pacing(index, &mut out);
    }
    if schema.flag("chars_not_mentioned") {
        chars_not_mentioned(index, &mut out);
    }
    if schema.flag("timeline_regression") {
        timeline(index, &mut out);
    }
    if schema.flag("unknown_field") {
        unknown_fields(index, schema, &mut out);
    }
    if schema.flag("invalid_enum") {
        invalid_enums(index, schema, &mut out);
    }
    if schema.flag("missing_id") {
        missing_ids(index, &mut out);
    }
    thread_resolution(index, schema, &mut out);
    if schema.flag("duplicate_alias") {
        duplicate_aliases(index, &mut out);
    }
    if schema.flag("missing_min_fields") {
        missing_min_fields(index, schema, &mut out);
    }
    out
}

// Lowercase and collapse whitespace so phrases compare cleanly.
fn norm(s: &str) -> String {
    s.to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

// Does the (space-joined) prose contain `phrase` as a whole word sequence?
fn phrase_in(prose: &str, phrase: &str) -> bool {
    let phrase = phrase.trim();
    if phrase.is_empty() {
        return false;
    }
    format!(" {} ", prose).contains(&format!(" {} ", phrase))
}

fn has_text(v: Option<&Value>) -> bool {
    v.and_then(meta::value_to_string)
        .map(|s| !s.trim().is_empty())
        .unwrap_or(false)
}

fn push_scene(out: &mut Vec<ProjectDiagnostic>, scene: &Scene, severity: Severity, message: String) {
    out.push(ProjectDiagnostic {
        path: scene.path.clone(),
        line: scene.start_line,
        start_byte: 0,
        end_byte: usize::MAX,
        severity,
        message,
    });
}

fn push_card(out: &mut Vec<ProjectDiagnostic>, card: &RefCard, severity: Severity, message: String) {
    out.push(ProjectDiagnostic {
        path: card.path.clone(),
        line: 0,
        start_byte: 0,
        end_byte: usize::MAX,
        severity,
        message,
    });
}

// Scene `id:` values must be unique across the project.
fn duplicate_ids(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    let mut seen: HashMap<String, Vec<&Scene>> = HashMap::new();
    for ch in &index.chapters {
        for sc in &ch.scenes {
            if let Some(id) = sc.meta.get("id").and_then(meta::value_to_string) {
                let id = id.trim().to_string();
                if !id.is_empty() {
                    seen.entry(id).or_default().push(sc);
                }
            }
        }
    }
    for (id, scenes) in seen {
        if scenes.len() < 2 {
            continue;
        }
        let count = scenes.len();
        for sc in &scenes {
            push_scene(
                out,
                sc,
                Severity::Warning,
                format!("Scene id “{id}” is used by {count} scenes — ids must be unique."),
            );
        }
    }
}

// A scene with a goal but no conflict or outcome is a half-formed beat.
fn incomplete_beats(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    for ch in &index.chapters {
        for sc in &ch.scenes {
            if !has_text(sc.meta.get("goal")) {
                continue;
            }
            let missing: Vec<&str> = ["conflict", "outcome"]
                .iter()
                .filter(|k| !has_text(sc.meta.get(**k)))
                .copied()
                .collect();
            if !missing.is_empty() {
                push_scene(
                    out,
                    sc,
                    Severity::Hint,
                    format!(
                        "Scene has a goal but no {} — the beat is incomplete.",
                        missing.join(" / ")
                    ),
                );
            }
        }
    }
}

// Flag scenes that run far over their `target` word count (pacing).
fn pacing(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let target = sc
                .meta
                .get("target")
                .and_then(meta::value_to_string)
                .and_then(|s| s.parse::<usize>().ok());
            let Some(target) = target else { continue };
            if target == 0 {
                continue;
            }
            let words = crate::index::scene_words(sc);
            if words > target * 2 {
                push_scene(
                    out,
                    sc,
                    Severity::Hint,
                    format!("Scene runs {words} words against a target of {target} — consider splitting."),
                );
            }
        }
    }
}

// A character listed in `chars:` but absent from the scene's prose is likely
// stale metadata.
fn chars_not_mentioned(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    let mut alias_map: HashMap<String, Vec<String>> = HashMap::new();
    for card in &index.cards {
        let mut aliases: Vec<String> = card.aliases.iter().map(|a| norm(a)).collect();
        aliases.sort();
        aliases.dedup();
        alias_map.entry(norm(&card.name)).or_insert(aliases);
    }

    for ch in &index.chapters {
        for sc in &ch.scenes {
            let chars = sc.meta.get("chars").map(meta::value_to_list).unwrap_or_default();
            if chars.is_empty() {
                continue;
            }
            let prose = norm(&crate::index::scene_prose(sc));
            if prose.is_empty() {
                continue;
            }
            let mut absent = Vec::new();
            for c in &chars {
                let key = norm(c);
                let aliases = alias_map.get(&key).cloned().unwrap_or_else(|| vec![key.clone()]);
                if !aliases.iter().any(|a| phrase_in(&prose, a)) {
                    absent.push(c.clone());
                }
            }
            if !absent.is_empty() {
                push_scene(
                    out,
                    sc,
                    Severity::Hint,
                    format!("Listed but not mentioned in this scene: {}.", absent.join(", ")),
                );
            }
        }
    }
}

// Numeric `day:` / `time:` values must not decrease in document order.
fn timeline(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    let mut prev: Option<i64> = None;
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let day = sc
                .meta
                .get("day")
                .and_then(meta::parse_story_day)
                .or_else(|| sc.meta.get("time").and_then(meta::parse_story_day));
            let Some(day) = day else { continue };
            if let Some(p) = prev {
                if day < p {
                    push_scene(
                        out,
                        sc,
                        Severity::Hint,
                        format!("Timeline moves backwards: day {day} after day {p}."),
                    );
                }
            }
            prev = Some(day);
        }
    }
}

// A key in a scene YAML block outside the scene field allowlist.
fn unknown_fields(index: &Index, schema: &Schema, out: &mut Vec<ProjectDiagnostic>) {
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let mut unknown: Vec<String> = sc
                .meta
                .keys()
                .filter(|k| !schema.scene_fields.iter().any(|f| f == *k))
                .cloned()
                .collect();
            if unknown.is_empty() {
                continue;
            }
            unknown.sort();
            push_scene(
                out,
                sc,
                Severity::Warning,
                format!("Unknown scene field(s): {}.", unknown.join(", ")),
            );
        }
    }
}

// An enum-typed field whose value is not in its `from` list.
fn invalid_enums(index: &Index, schema: &Schema, out: &mut Vec<ProjectDiagnostic>) {
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let mut bad = Vec::new();
            for (key, val) in &sc.meta {
                if let Some(def) = schema.scene_field_def(key) {
                    if def.kind == "enum" {
                        let allowed = schema.enum_values(def.from.as_deref().unwrap_or("statuses"));
                        if let Some(v) = meta::value_to_string(val) {
                            if !allowed.iter().any(|a| a == &v) {
                                bad.push(format!("{key}: {v}"));
                            }
                        }
                    }
                }
            }
            if !bad.is_empty() {
                push_scene(
                    out,
                    sc,
                    Severity::Warning,
                    format!("Invalid enum value(s): {}.", bad.join(", ")),
                );
            }
        }
    }
}

// A scene block without an `id:` field.
fn missing_ids(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    for ch in &index.chapters {
        for sc in &ch.scenes {
            let has_id = sc
                .meta
                .get("id")
                .map(|v| has_text(Some(v)))
                .unwrap_or(false);
            if !has_id {
                push_scene(out, sc, Severity::Hint, "Scene has no id.".into());
            }
        }
    }
}

// `setup:` / `payoff:` thread keys must pair up (either order, any scenes).
fn thread_resolution(index: &Index, schema: &Schema, out: &mut Vec<ProjectDiagnostic>) {
    let mut setups: HashMap<String, Vec<&Scene>> = HashMap::new();
    let mut payoffs: HashMap<String, Vec<&Scene>> = HashMap::new();
    for ch in &index.chapters {
        for sc in &ch.scenes {
            for key in sc.meta.get("setup").map(meta::value_to_list).unwrap_or_default() {
                if !key.trim().is_empty() {
                    setups.entry(key).or_default().push(sc);
                }
            }
            for key in sc.meta.get("payoff").map(meta::value_to_list).unwrap_or_default() {
                if !key.trim().is_empty() {
                    payoffs.entry(key).or_default().push(sc);
                }
            }
        }
    }
    if schema.flag("unresolved_setup") {
        for (key, scenes) in &setups {
            if !payoffs.contains_key(key) {
                for sc in scenes {
                    push_scene(out, sc, Severity::Hint, format!("setup “{key}” has no matching payoff."));
                }
            }
        }
    }
    if schema.flag("unresolved_payoff") {
        for (key, scenes) in &payoffs {
            if !setups.contains_key(key) {
                for sc in scenes {
                    push_scene(out, sc, Severity::Hint, format!("payoff “{key}” has no matching setup."));
                }
            }
        }
    }
}

// The same normalized alias key mapping to two or more cards.
fn duplicate_aliases(index: &Index, out: &mut Vec<ProjectDiagnostic>) {
    let mut map: HashMap<String, Vec<&RefCard>> = HashMap::new();
    for card in &index.cards {
        for alias in &card.aliases {
            map.entry(alias.to_lowercase()).or_default().push(card);
        }
    }
    for (alias, cards) in map {
        if cards.len() < 2 {
            continue;
        }
        let mut seen = HashSet::new();
        for card in cards {
            let key = card.path.to_string_lossy().to_string();
            if seen.insert(key) {
                push_card(
                    out,
                    card,
                    Severity::Hint,
                    format!("Alias “{alias}” maps to multiple cards."),
                );
            }
        }
    }
}

// Does a card's bullet list contain a field (`- **Field:** value` or `- **Field**`)?
fn summary_has(card: &RefCard, field: &str) -> bool {
    let a = format!("**{field}:**");
    let b = format!("**{field}**");
    card.summary.iter().any(|s| s.contains(&a) || s.contains(&b))
}

// A card of a declared type lacking one of its required bullets.
fn missing_min_fields(index: &Index, schema: &Schema, out: &mut Vec<ProjectDiagnostic>) {
    for card in &index.cards {
        let min_fields = schema
            .ref_type(&card.rtype)
            .map(|t| t.min_fields.clone())
            .unwrap_or_default();
        if min_fields.is_empty() {
            continue;
        }
        let missing: Vec<String> = min_fields
            .iter()
            .filter(|f| !summary_has(card, f))
            .cloned()
            .collect();
        if !missing.is_empty() {
            push_card(
                out,
                card,
                Severity::Hint,
                format!("Missing required field(s) on card: {}.", missing.join(", ")),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scene(meta: Vec<(&str, Value)>) -> Scene {
        Scene {
            path: PathBuf::from("/x.md"),
            title: "Scene".into(),
            start_line: 0,
            end_line: 0,
            meta: meta.into_iter().map(|(k, v)| (k.to_string(), v)).collect(),
        }
    }

    fn chapter(scenes: Vec<Scene>) -> crate::index::Chapter {
        crate::index::Chapter {
            path: PathBuf::from("/ch1.md"),
            title: "Chapter".into(),
            number: None,
            target: None,
            scenes,
        }
    }

    fn idx(scenes: Vec<Scene>) -> Index {
        Index {
            chapters: vec![chapter(scenes)],
            ..Index::default()
        }
    }

    #[test]
    fn flags_duplicate_ids() {
        let diags = project_diagnostics(
            &idx(vec![scene(vec![("id", Value::from("s1"))]), scene(vec![("id", Value::from("s1"))])]),
            &Schema::defaults(),
        );
        assert!(diags.iter().any(|d| d.message.contains("must be unique")));
    }

    #[test]
    fn flags_incomplete_beat() {
        let diags = project_diagnostics(&idx(vec![scene(vec![("goal", Value::from("escape"))])]), &Schema::defaults());
        assert!(diags.iter().any(|d| d.message.contains("beat is incomplete")));
    }

    #[test]
    fn no_beat_flag_when_complete() {
        let diags = project_diagnostics(
            &idx(vec![scene(vec![
                ("goal", Value::from("escape")),
                ("conflict", Value::from("guards")),
                ("outcome", Value::from("flee")),
            ])]),
            &Schema::defaults(),
        );
        assert!(!diags.iter().any(|d| d.message.contains("beat")));
    }

    #[test]
    fn flags_timeline_regression() {
        let diags = project_diagnostics(
            &idx(vec![scene(vec![("day", Value::from(5))]), scene(vec![("day", Value::from(3))])]),
            &Schema::defaults(),
        );
        assert!(diags.iter().any(|d| d.message.contains("Timeline moves backwards")));
    }

    #[test]
    fn free_text_time_never_compares() {
        let diags = project_diagnostics(
            &idx(vec![scene(vec![("time", Value::from("morning"))]), scene(vec![("time", Value::from("dawn"))])]),
            &Schema::defaults(),
        );
        assert!(!diags.iter().any(|d| d.message.contains("Timeline")));
    }

    #[test]
    fn phrase_matching_is_word_boundary_aware() {
        assert!(phrase_in("captain greg boarded", "greg"));
        assert!(phrase_in("captain greg boarded", "captain greg"));
        assert!(!phrase_in("the aggregate total", "greg"));
    }

    #[test]
    fn flags_unknown_field() {
        let diags = project_diagnostics(&idx(vec![scene(vec![("frobnicate", Value::from("x"))])]), &Schema::defaults());
        assert!(diags.iter().any(|d| d.message.contains("Unknown scene field")));
    }

    #[test]
    fn known_fields_are_not_unknown() {
        let diags = project_diagnostics(&idx(vec![scene(vec![("status", Value::from("draft"))])]), &Schema::defaults());
        assert!(!diags.iter().any(|d| d.message.contains("Unknown scene field")));
    }

    #[test]
    fn flags_invalid_enum() {
        let diags = project_diagnostics(&idx(vec![scene(vec![("status", Value::from("bogus"))])]), &Schema::defaults());
        assert!(diags.iter().any(|d| d.message.contains("Invalid enum")));
    }

    #[test]
    fn missing_id_gated_off_by_default() {
        let diags = project_diagnostics(&idx(vec![scene(vec![])]), &Schema::defaults());
        assert!(!diags.iter().any(|d| d.message.contains("no id")));
    }

    #[test]
    fn flags_unresolved_threads() {
        let diags = project_diagnostics(&idx(vec![scene(vec![("setup", Value::from("sword"))])]), &Schema::defaults());
        assert!(diags.iter().any(|d| d.message.contains("no matching payoff")));
    }
}
