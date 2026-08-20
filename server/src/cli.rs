// Headless CLI: `storyteller-lsp report|check|index|completions|version|help`.
// Reuses Schema::load, index::scan, and the diagnostics module so the LSP and
// the CLI share one implementation. Runs synchronously (no async work).

use crate::diagnostics::{self, Severity};
use crate::index::{self, Index};
use crate::schema::Schema;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        print_help();
        return 2;
    }
    let cmd = args[0].as_str();
    if cmd == "help" {
        print_help();
        return 0;
    }
    if cmd == "version" {
        println!("storyteller-lsp {}", env!("CARGO_PKG_VERSION"));
        return 0;
    }

    let mut project = PathBuf::from(".");
    let mut json = false;
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--project" => {
                if i + 1 < args.len() {
                    project = PathBuf::from(&args[i + 1]);
                    i += 1;
                }
            }
            "--json" => json = true,
            _ => {}
        }
        i += 1;
    }

    match cmd {
        "report" => report(&project, json),
        "check" => check(&project, json),
        "index" => index_cmd(&project, json),
        "completions" => completions(&project, json),
        _ => {
            eprintln!("storyteller-lsp: unknown command: {cmd}");
            2
        }
    }
}

fn print_help() {
    println!(
        "storyteller-lsp {version}\n\n\
         Usage: storyteller-lsp <command> [--project <dir>] [--json]\n\n\
         Commands:\n\
         \x20 report       word totals, status distribution, field coverage\n\
         \x20 check        every diagnostic (exit 1 on warning-or-above)\n\
         \x20 index        resolved name map + alias sets\n\
         \x20 completions  completion catalog (names, enums, fields, threads)\n\
         \x20 version      print the version\n\
         \x20 help         this help\n\n\
         With no command the server runs the LSP loop over stdin/stdout.",
        version = env!("CARGO_PKG_VERSION")
    );
}

fn load(project: &Path) -> (Schema, Index) {
    let (schema, warnings) = Schema::load(Some(project), None);
    for w in warnings {
        eprintln!("warning: {w}");
    }
    let index = index::scan(project);
    (schema, index)
}

// --- report ------------------------------------------------------------------

fn report(project: &Path, json: bool) -> i32 {
    let (schema, index) = load(project);

    let total_words: usize = index
        .chapters
        .iter()
        .flat_map(|c| c.scenes.iter())
        .map(|s| index::scene_words(s))
        .sum();

    let mut status_counts: HashMap<String, usize> = HashMap::new();
    let mut coverage: HashMap<String, usize> = HashMap::new();
    let mut scene_count = 0usize;
    for ch in &index.chapters {
        for sc in &ch.scenes {
            scene_count += 1;
            if let Some(st) = sc.meta.get("status").and_then(crate::meta::value_to_string) {
                *status_counts.entry(st).or_default() += 1;
            }
            for field in &schema.scene_fields {
                if sc
                    .meta
                    .get(field)
                    .map(|v| !crate::meta::value_to_string(v).unwrap_or_default().trim().is_empty())
                    .unwrap_or(false)
                {
                    *coverage.entry(field.clone()).or_default() += 1;
                }
            }
        }
    }

    let alias_dupes = diagnostics::project_diagnostics(&index, &schema)
        .into_iter()
        .filter(|d| d.message.contains("maps to multiple cards"))
        .count();

    if json {
        let mut status_json = serde_json::Map::new();
        for (k, v) in &status_counts {
            status_json.insert(k.clone(), serde_json::json!(v));
        }
        let mut coverage_json = serde_json::Map::new();
        for (k, v) in &coverage {
            coverage_json.insert(k.clone(), serde_json::json!(v));
        }
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "words": total_words,
                "chapters": index.chapters.len(),
                "scenes": scene_count,
                "cards": index.cards.len(),
                "statuses": status_json,
                "field_coverage": coverage_json,
                "alias_duplicates": alias_dupes,
            }))
            .unwrap()
        );
    } else {
        println!("Words: {total_words}");
        println!("Chapters: {} · Scenes: {} · Cards: {}", index.chapters.len(), scene_count, index.cards.len());
        println!();
        println!("Status distribution:");
        let mut statuses: Vec<_> = status_counts.into_iter().collect();
        statuses.sort_by(|a, b| b.1.cmp(&a.1));
        for (status, n) in statuses {
            println!("  {status:<12} {n}");
        }
        println!();
        println!("Scene field coverage:");
        for field in &schema.scene_fields {
            let n = coverage.get(field).copied().unwrap_or(0);
            println!("  {field:<14} {n}/{scene_count}");
        }
        if alias_dupes > 0 {
            println!();
            println!("Alias duplicates: {alias_dupes}");
        }
    }
    0
}

// --- check -------------------------------------------------------------------

fn check(project: &Path, json: bool) -> i32 {
    let (schema, index) = load(project);

    let mut diags = diagnostics::project_diagnostics(&index, &schema);

    for card in &index.cards {
        if index::mention_count(&index, card) == 0 {
            diags.push(diagnostics::ProjectDiagnostic {
                path: card.path.clone(),
                line: 0,
                start_byte: 0,
                end_byte: usize::MAX,
                severity: Severity::Hint,
                message: format!("“{}” is never mentioned in the manuscript.", card.name),
            });
        }
    }
    for ch in &index.chapters {
        let text = std::fs::read_to_string(&ch.path).unwrap_or_default();
        for (line, byte, word) in index::unknown_names(&index, &text) {
            diags.push(diagnostics::ProjectDiagnostic {
                path: ch.path.clone(),
                line: line as u32,
                start_byte: byte,
                end_byte: byte + word.len(),
                severity: Severity::Hint,
                message: format!("No reference card for “{word}”."),
            });
        }
    }

    let has_warning = diags.iter().any(|d| d.severity == Severity::Warning);

    if json {
        let out: Vec<serde_json::Value> = diags
            .iter()
            .map(|d| {
                serde_json::json!({
                    "path": d.path.to_string_lossy(),
                    "line": d.line + 1,
                    "severity": if d.severity == Severity::Warning { "warning" } else { "hint" },
                    "message": d.message,
                })
            })
            .collect();
        println!("{}", serde_json::to_string_pretty(&serde_json::json!(out)).unwrap());
    } else {
        for d in &diags {
            let sev = if d.severity == Severity::Warning { "warning" } else { "hint" };
            println!("{}:{}: {sev}: {}", d.path.to_string_lossy(), d.line + 1, d.message);
        }
        if diags.is_empty() {
            println!("Clean.");
        }
    }

    if has_warning {
        1
    } else {
        0
    }
}

// --- index -------------------------------------------------------------------

fn index_cmd(project: &Path, json: bool) -> i32 {
    let (schema, index) = load(project);
    let _ = schema;

    let mut cards: Vec<serde_json::Value> = index
        .cards
        .iter()
        .map(|c| {
            serde_json::json!({
                "name": c.name,
                "aliases": c.aliases,
                "type": c.rtype,
                "path": c.path.to_string_lossy(),
            })
        })
        .collect();
    cards.sort_by(|a, b| a["name"].as_str().cmp(&b["name"].as_str()));

    if json {
        println!("{}", serde_json::to_string_pretty(&serde_json::json!({ "cards": cards })).unwrap());
    } else {
        for c in &cards {
            let aliases = c["aliases"].as_array().map(|a| a.len()).unwrap_or(0);
            println!(
                "{:<24} {:<12} {} alias(es)",
                c["name"].as_str().unwrap_or(""),
                c["type"].as_str().unwrap_or(""),
                aliases
            );
        }
    }
    0
}

// --- completions -------------------------------------------------------------

fn completions(project: &Path, json: bool) -> i32 {
    let (schema, index) = load(project);

    let mut names: Vec<String> = index
        .cards
        .iter()
        .flat_map(|c| c.aliases.iter().chain(std::iter::once(&c.name)).cloned())
        .collect();
    names.sort();
    names.dedup();

    let mut fields: Vec<String> = schema
        .scene_fields
        .iter()
        .chain(schema.chapter_fields.iter())
        .cloned()
        .collect();
    fields.sort();
    fields.dedup();

    let statuses = schema.enum_values("statuses");
    let threads = index::thread_keys(&index);

    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "names": names,
                "fields": fields,
                "statuses": statuses,
                "thread_keys": threads,
            }))
            .unwrap()
        );
    } else {
        println!("Names:");
        for n in &names {
            println!("  {n}");
        }
        println!("Fields:");
        for f in &fields {
            println!("  {f}");
        }
        println!("Statuses:");
        for s in &statuses {
            println!("  {s}");
        }
        println!("Thread keys:");
        for t in &threads {
            println!("  {t}");
        }
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("storyteller-cli-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("chapters")).unwrap();
        std::fs::create_dir_all(dir.join("references/characters")).unwrap();
        dir
    }

    #[test]
    fn check_returns_zero_for_hints_only() {
        let dir = fixture("hints");
        std::fs::write(
            dir.join("chapters/01.md"),
            "# Chapter 1\n\n## S1\n\n```yaml\nstoryteller: scene\nstatus: draft\ngoal: escape\n```\n\nProse here.\n",
        )
        .unwrap();
        assert_eq!(check(&dir, false), 0);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn check_returns_one_for_warning() {
        let dir = fixture("warning");
        std::fs::write(
            dir.join("chapters/01.md"),
            "# Chapter 1\n\n## S1\n\n```yaml\nstoryteller: scene\nid: dup\n```\n\nA.\n\n## S2\n\n```yaml\nstoryteller: scene\nid: dup\n```\n\nB.\n",
        )
        .unwrap();
        assert_eq!(check(&dir, false), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn report_and_completions_run() {
        let dir = fixture("report");
        std::fs::write(
            dir.join("chapters/01.md"),
            "# Chapter 1\n\n## S1\n\n```yaml\nstoryteller: scene\nstatus: draft\n```\n\nProse.\n",
        )
        .unwrap();
        assert_eq!(report(&dir, true), 0);
        assert_eq!(completions(&dir, true), 0);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
