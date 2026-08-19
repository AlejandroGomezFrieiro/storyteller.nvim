// Project indexing: chapters, scenes, and reference cards, plus a bare-name
// index for prose-aware resolution (the server-side counterpart of
// storyteller.index + storyteller.detect).

use crate::meta;
use serde_yaml::Value;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

#[derive(Clone, Debug)]
pub struct RefCard {
    pub name: String,
    pub aliases: Vec<String>,
    pub path: PathBuf,
    pub rtype: String,
    pub title: String,
    pub summary: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct Scene {
    pub path: PathBuf,
    pub title: String,
    pub start_line: u32,
    pub end_line: u32,
    pub meta: HashMap<String, Value>,
}

#[derive(Clone, Debug)]
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
    // Reference type folders discovered under references/ (e.g. "characters",
    // "creatures", ...). Lets the code actions offer any folder as a type.
    pub reference_dirs: Vec<String>,
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
    let rest = h1
        .strip_prefix("Chapter ")
        .or_else(|| h1.strip_prefix("chapter "))
        .unwrap_or("");
    let mut num = String::new();
    for c in rest.chars() {
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
    let k = norm_key(key);
    let list = names.entry(k).or_default();
    if !list.iter().any(|e| e.name == entry.name) {
        list.push(entry);
    }
}

// Lowercase and strip punctuation so alias keys match the space-joined token
// phrases used by `resolve_at` (e.g. "Capt. Clark" → "capt clark").
fn norm_key(key: &str) -> String {
    key.chars()
        .map(|c| if c.is_alphanumeric() || c == '\'' || c == ' ' { c } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
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

    if refs_dir.is_dir() {
        // Any subfolder under references/ is a reference type (folder = type id).
        let mut dirs = Vec::new();
        let entries = std::fs::read_dir(&refs_dir).into_iter().flatten().filter_map(|e| e.ok());
        for entry in entries {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let name = path
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_default();
            if is_excluded(&name) {
                continue;
            }
            dirs.push(name);
        }
        dirs.sort();
        index.reference_dirs = dirs.clone();
        for t in dirs {
            for p in list_md(&refs_dir.join(&t)) {
                if let Some(card) = parse_card(&p, &t) {
                    index.cards.push(card);
                }
            }
        }
    }

    // First pass: full names + aliases; count character first-name frequency.
    let mut first_counts: HashMap<String, usize> = HashMap::new();
    for card in &index.cards {
        if card.rtype == "characters" {
            if let Some(first) = card.name.split_whitespace().next() {
                *first_counts.entry(first.to_lowercase()).or_default() += 1;
            }
        }
    }
    for card in index.cards.clone() {
        for (i, a) in card.aliases.iter().enumerate() {
            let conf = if i == 0 { 1.0 } else { 0.9 };
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
        }
        // Unique first name for multi-word character names (confidence 0.7).
        if card.rtype == "characters" {
            let words: Vec<&str> = card.name.split_whitespace().collect();
            if words.len() > 1 {
                let first = words[0].to_lowercase();
                if first_counts.get(&first).copied().unwrap_or(0) == 1 {
                    push_name(
                        &mut index.names,
                        &first,
                        NameEntry {
                            name: words[0].to_string(),
                            path: card.path.clone(),
                            rtype: card.rtype.clone(),
                            confidence: 0.7,
                        },
                    );
                }
            }
        }
    }

    index
}

// --- Name resolution --------------------------------------------------------

#[derive(Clone, Debug)]
pub struct Token {
    pub start: usize,
    pub end: usize,
    pub word: String,
}

pub fn tokenize(line: &str) -> Vec<Token> {
    let mut out = Vec::new();
    let bytes = line.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = line[i..].chars().next().unwrap();
        if c.is_alphanumeric() || c == '\'' {
            let start = i;
            while i < bytes.len() {
                let ch = line[i..].chars().next().unwrap();
                if ch.is_alphanumeric() || ch == '\'' {
                    i += ch.len_utf8();
                } else {
                    break;
                }
            }
            out.push(Token {
                start,
                end: i,
                word: line[start..i].to_string(),
            });
        } else {
            i += c.len_utf8();
        }
    }
    out
}

// Resolve a single word to reference entries.
pub fn resolve(index: &Index, word: &str) -> Vec<NameEntry> {
    let w = word.trim().to_lowercase();
    index.names.get(&w).cloned().unwrap_or_default()
}

fn best(entries: &[NameEntry]) -> Option<&NameEntry> {
    entries
        .iter()
        .max_by(|a, b| a.confidence.partial_cmp(&b.confidence).unwrap())
}

// Resolve the name under a byte offset using 3-, 2-, and 1-word n-grams, so
// multi-word names like "Captain Greg" resolve. Returns (entry, byte range).
pub fn resolve_at<'a>(index: &'a Index, line: &str, cursor_byte: usize) -> Option<(&'a NameEntry, (usize, usize))> {
    let tokens = tokenize(line);
    if tokens.is_empty() {
        return None;
    }
    let mut ti = None;
    for (i, t) in tokens.iter().enumerate() {
        if cursor_byte >= t.start && cursor_byte <= t.end {
            ti = Some(i);
            break;
        }
    }
    let ti = match ti {
        Some(i) => i,
        None => {
            // cursor past the last token: use the last token if it is the nearest word
            if cursor_byte > tokens.last().unwrap().end {
                tokens.len() - 1
            } else {
                return None;
            }
        }
    };

    for w in (1..=3usize).rev() {
        for s in (0..=ti).rev() {
            if s + w > tokens.len() {
                continue;
            }
            if !(s <= ti && ti < s + w) {
                continue;
            }
            let phrase: Vec<&str> = tokens[s..s + w].iter().map(|t| t.word.as_str()).collect();
            let key = phrase.join(" ").to_lowercase();
            if let Some(entries) = index.names.get(&key) {
                if let Some(e) = best(entries) {
                    let range = (tokens[s].start, tokens[s + w - 1].end);
                    return Some((e, range));
                }
            }
        }
    }
    None
}

// Every mention of any of a card's aliases across chapters.
pub fn mentions(index: &Index, card: &RefCard) -> Vec<(PathBuf, u32, u32, u32)> {
    let aliases: HashSet<String> = card.aliases.iter().map(|a| a.to_lowercase()).collect();
    let mut out = Vec::new();
    for ch in &index.chapters {
        if let Ok(text) = std::fs::read_to_string(&ch.path) {
            for (i, line) in text.lines().enumerate() {
                for t in tokenize(line) {
                    if aliases.contains(&t.word.to_lowercase()) {
                        out.push((
                            ch.path.clone(),
                            i as u32,
                            t.start as u32,
                            t.end as u32,
                        ));
                    }
                }
            }
        }
    }
    out
}

pub fn mention_count(index: &Index, card: &RefCard) -> usize {
    mentions(index, card).len()
}

// Capitalized words in prose that look like names but have no card. Returns
// (line, byte_start, word).
pub fn unknown_names(index: &Index, text: &str) -> Vec<(usize, usize, String)> {
    let stopwords: HashSet<&str> = [
        "I", "The", "A", "An", "It", "Its", "He", "She", "They", "We", "You", "His", "Her",
        "Their", "And", "But", "Or", "For", "Nor", "So", "Yet", "Then", "When", "While", "If",
        "As", "At", "By", "In", "On", "To", "Of", "From", "With", "Without", "Into", "Over",
        "Under", "Again", "Once", "Now", "There", "Here", "This", "That", "These", "Those",
        "No", "Yes", "Not", "All", "Some", "Any", "Each", "Every", "Either", "Neither", "Both",
        "My", "Our", "Your", "Mine", "Ours", "Day", "Night", "Morning", "Evening", "Chapter",
        "Scene", "Part", "Act",
    ]
    .iter()
    .copied()
    .collect();

    let mut out = Vec::new();
    for (li, line) in text.lines().enumerate() {
        let tokens = tokenize(line);
        for (i, t) in tokens.iter().enumerate() {
            let w = &t.word;
            // proper-noun heuristic: first char uppercase, rest not all-caps.
            let first = w.chars().next().unwrap_or(' ');
            if !first.is_uppercase() {
                continue;
            }
            if w.len() < 2 {
                continue;
            }
            if !w.chars().skip(1).any(|c| c.is_lowercase()) {
                continue; // ALLCAPS or acronym
            }
            if stopwords.contains(w.as_str()) {
                continue;
            }
            // skip words at the very start of a sentence (after . ? ! : — or line start)
            if i == 0 {
                continue;
            }
            let prev = &tokens[i - 1];
            if prev.word.ends_with(['.', '?', '!', ':', '—']) {
                continue;
            }
            if resolve(index, w).is_empty() {
                out.push((li, t.start, w.clone()));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokenizes_words() {
        let toks = tokenize("Odysseus watched the harbor's lights.");
        assert_eq!(toks[0].word, "Odysseus");
        assert_eq!(toks[3].word, "harbor's");
        assert_eq!(toks[3].start, "Odysseus watched the ".len());
    }

    #[test]
    fn resolves_multi_word_names() {
        let mut idx = Index::default();
        push_name(
            &mut idx.names,
            "Captain Greg",
            NameEntry {
                name: "Captain Greg".into(),
                path: PathBuf::from("/x.md"),
                rtype: "characters".into(),
                confidence: 1.0,
            },
        );
        let line = "Captain Greg boarded the ship.";
        let (entry, range) = resolve_at(&idx, line, "Captain G".len()).unwrap();
        assert_eq!(entry.name, "Captain Greg");
        assert_eq!(&line[range.0..range.1], "Captain Greg");
    }

    #[test]
    fn resolves_single_word() {
        let mut idx = Index::default();
        push_name(
            &mut idx.names,
            "Odysseus",
            NameEntry {
                name: "Odysseus".into(),
                path: PathBuf::from("/o.md"),
                rtype: "characters".into(),
                confidence: 1.0,
            },
        );
        let line = "pov: Odysseus";
        let (entry, _) = resolve_at(&idx, line, 6).unwrap();
        assert_eq!(entry.name, "Odysseus");
    }
}
