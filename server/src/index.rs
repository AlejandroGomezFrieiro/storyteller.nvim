// Project indexing: chapters, scenes, and reference cards, plus a bare-name
// index for prose-aware resolution (the server-side counterpart of
// storyteller.index + storyteller.detect).

use crate::meta;
use serde_yaml::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct RefCard {
    pub name: String,
    pub aliases: Vec<String>,
    pub path: PathBuf,
    pub rtype: String,
    pub title: String,
    pub summary: Vec<String>,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct Scene {
    pub path: PathBuf,
    pub title: String,
    pub start_line: u32,
    pub end_line: u32,
    pub meta: HashMap<String, Value>,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
pub struct Chapter {
    pub path: PathBuf,
    pub title: String,
    pub number: Option<u32>,
    pub target: Option<u32>,
    pub scenes: Vec<Scene>,
}

#[derive(Clone, Debug)]
pub struct NameEntry {
    pub name: String,
    pub path: PathBuf,
    pub rtype: String,
    pub confidence: f64,
}

#[derive(Default, Clone, Debug)]
pub struct Index {
    pub cards: Vec<RefCard>,
    pub chapters: Vec<Chapter>,
    pub names: HashMap<String, Vec<NameEntry>>,
}

fn is_excluded(rel: &str) -> bool {
    rel.split('/').any(|p| p.starts_with('_') || p.starts_with('.'))
}

fn list_md(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let walker = walkdir::WalkDir::new(dir).into_iter().filter_map(|e| e.ok());
    for entry in walker {
        if entry.file_type().is_file() {
            if let Some(ext) = entry.path().extension() {
                if ext == "md" {
                    let rel = entry.path().strip_prefix(dir).unwrap_or(entry.path());
                    if !is_excluded(&rel.to_string_lossy()) {
                        out.push(entry.path().to_path_buf());
                    }
                }
            }
        }
    }
    out.sort();
    out
}

fn read_lines(path: &Path) -> Vec<String> {
    std::fs::read_to_string(path)
        .map(|s| s.lines().map(|l| l.to_string()).collect())
        .unwrap_or_default()
}

fn chapter_title(h1: &str) -> (Option<u32>, String) {
    // "Chapter N — Title" / "Chapter N: Title"
    let rest = h1
        .strip_prefix("Chapter ")
        .or_else(|| h1.strip_prefix("chapter "))
        .unwrap_or("");
    let mut chars = rest.chars();
    let mut num = String::new();
    for c in chars.by_ref() {
        if c.is_ascii_digit() {
            num.push(c);
        } else {
            break;
        }
    }
    if num.is_empty() {
        return (None, h1.trim().to_string());
    }
    let title = rest[num.len()..]
        .trim_start_matches(|c: char| c.is_whitespace() || matches!(c, ':' | '.' | '-' | '–' | '—'))
        .trim()
        .to_string();
    let number = num.parse::<u32>().ok();
    let title = if title.is_empty() { h1.to_string() } else { title };
    (number, title)
}

fn parse_chapter(path: &Path) -> Option<Chapter> {
    let lines = read_lines(path);
    if lines.is_empty() {
        return None;
    }
    let mut title = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    let mut number = None;
    let mut target = None;

    for l in &lines {
        if let Some(h1) = l.strip_prefix("# ") {
            let (n, t) = chapter_title(h1);
            number = n;
            title = t;
            break;
        }
    }

    // target from frontmatter, else a `# Target: N` / `> Target: N` line.
    if let Some((fm, _)) = meta::parse_frontmatter(&lines) {
        if let Some(t) = fm.get("target").and_then(meta::value_to_string) {
            target = t.parse::<u32>().ok();
        }
    }
    if target.is_none() {
        for l in &lines {
            let t = l.trim_start();
            if t.starts_with("Target:") {
                if let Some(n) = t[7..].trim().split_whitespace().next() {
                    target = n.parse::<u32>().ok();
                    break;
                }
            }
        }
    }

    let mut scenes = Vec::new();
    let mut cur: Option<(String, usize)> = None;
    for (i, l) in lines.iter().enumerate() {
        if let Some(h2) = l.strip_prefix("## ") {
            if let Some((t, s)) = cur.take() {
                scenes.push((t, s, i - 1));
            }
            cur = Some((h2.trim().to_string(), i));
        }
    }
    if let Some((t, s)) = cur {
        scenes.push((t, s, lines.len().saturating_sub(1)));
    }

    let scenes = scenes
        .into_iter()
        .map(|(title, start, end)| {
            let (sm, _) = meta::parse_scene_block(&lines, start, end);
            Scene {
                path: path.to_path_buf(),
                title,
                start_line: start as u32,
                end_line: end as u32,
                meta: sm,
            }
        })
        .collect();

    Some(Chapter {
        path: path.to_path_buf(),
        title,
        number,
        target,
        scenes,
    })
}

fn parse_card(path: &Path, rtype: &str) -> Option<RefCard> {
    let lines = read_lines(path);
    if lines.is_empty() {
        return None;
    }
    let mut title = path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    for l in lines.iter().take(16) {
        if l.starts_with("# ") || l.starts_with("## ") {
            title = l.trim_start_matches('#').trim().to_string();
            break;
        }
    }
    let name = title
        .split(|c: char| matches!(c, '—' | '–' | ':'))
        .next()
        .unwrap_or("")
        .trim()
        .to_string();
    let name = if name.is_empty() { title.clone() } else { name };

    let mut aliases = Vec::new();
    let mut summary = Vec::new();
    if let Some((fm, _)) = meta::parse_frontmatter(&lines) {
        aliases = fm.get("names").map(meta::value_to_list).unwrap_or_default();
    }
    for l in &lines {
        if l.starts_with("- ") {
            summary.push(l.trim().to_string());
        }
    }
    if aliases.is_empty() {
        aliases = vec![name.clone()];
    }

    Some(RefCard {
        name: name.clone(),
        aliases,
        path: path.to_path_buf(),
        rtype: rtype.to_string(),
        title,
        summary,
    })
}

fn push_name(names: &mut HashMap<String, Vec<NameEntry>>, key: &str, entry: NameEntry) {
    let k = key.to_lowercase();
    let list = names.entry(k).or_default();
    if !list.iter().any(|e| e.name == entry.name) {
        list.push(entry);
    }
}

pub fn scan(root: &Path) -> Index {
    let mut index = Index::default();
    let chapters_dir = root.join("chapters");
    let refs_dir = root.join("references");

    if chapters_dir.is_dir() {
        for p in list_md(&chapters_dir) {
            if let Some(ch) = parse_chapter(&p) {
                index.chapters.push(ch);
            }
        }
    }

    let types = ["characters", "locations", "items", "organizations"];
    if refs_dir.is_dir() {
        for t in types {
            let dir = refs_dir.join(t);
            if dir.is_dir() {
                for p in list_md(&dir) {
                    if let Some(card) = parse_card(&p, t) {
                        let mut conf = 1.0;
                        for a in &card.aliases {
                            push_name(
                                &mut index.names,
                                a,
                                NameEntry {
                                    name: a.clone(),
                                    path: card.path.clone(),
                                    rtype: card.rtype.clone(),
                                    confidence: conf,
                                },
                            );
                            conf = 0.9;
                        }
                        index.cards.push(card);
                    }
                }
            }
        }
    }

    index
}

// --- Name resolution --------------------------------------------------------

// Resolve the name (single word) under the cursor to a reference card.
pub fn resolve(index: &Index, word: &str) -> Vec<NameEntry> {
    let w = word.trim().to_lowercase();
    index.names.get(&w).cloned().unwrap_or_default()
}
