// storyteller-tui: project model
// A self-contained, read-only parser for Storyteller projects (Markdown +
// YAML scene blocks, same conventions as the standard). This module is the
// seam where `storyteller-core` (the standard repo's Rust library) takes
// over; until then it keeps the TUI dependency-free and honest.

use anyhow::Result;
use std::fs;
use std::path::{Path, PathBuf};

#[allow(dead_code)]
#[derive(Debug, Clone, Default)]
pub struct Scene {
    pub title: String,
    pub chapter: String,
    pub file: PathBuf,
    pub line: usize,
    pub status: Option<String>,
    pub pov: Option<String>,
    pub location: Option<String>,
    pub day: Option<i64>,
    pub words: usize,
    /// Primary axis (`timeline:`); None rides the implicit main axis.
    pub axis: Option<String>,
    /// narrative_mode — non-linear scenes are exempt from ordering checks.
    pub mode: Option<String>,
    /// Position along an attached plotline (`stage:`).
    pub stage: Option<String>,
    /// Plotline names this scene advances.
    pub plotlines: Vec<String>,
    /// Event names this scene depicts.
    pub events: Vec<String>,
    /// Secondary placements parsed out of `also:` flow-map strings.
    pub also: Vec<(String, String)>,
}

/// A plotline card under references/plotlines/.
#[allow(dead_code)]
#[derive(Debug, Clone, Default)]
pub struct Track {
    pub name: String,
    pub stages: Vec<String>,
    /// The character this lane arcs (`kind: arc_of` edge), when declared.
    pub arc_of: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Default)]
pub struct Chapter {
    pub title: String,
    pub file: PathBuf,
    pub words: usize,
    pub target: Option<u64>,
    // Frontmatter status: `unused` shelves the whole chapter from word
    // totals and views, matching its exclusion from compilation.
    pub status: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct Project {
    pub root: PathBuf,
    pub chapters: Vec<Chapter>,
    pub scenes: Vec<Scene>,
    pub tracks: Vec<Track>,
    pub total_words: usize,
}

fn is_excluded(rel: &str) -> bool {
    rel.split('/').any(|part| part.starts_with('_') || part.starts_with('.'))
}

fn count_prose(line: &str, in_fence: &mut bool) -> usize {
    let trimmed = line.trim_start();
    if trimmed.starts_with("```") {
        *in_fence = !*in_fence;
        return 0;
    }
    if *in_fence || trimmed.starts_with('#') {
        return 0;
    }
    if trimmed.starts_with("- **") && trimmed.contains("**:") {
        return 0; // inline metadata bullets
    }
    trimmed.split_whitespace().count()
}

// Minimal YAML scene-block field extraction: `key: value` lines.
fn scene_field(block: &[&str], key: &str) -> Option<String> {
    block.iter().find_map(|l| {
        let (k, v) = l.split_once(':')?;
        k.trim().eq_ignore_ascii_case(key).then(|| v.trim().to_string()).filter(|s| !s.is_empty())
    })
}

/// A YAML list field as raw item strings (`plotlines:`, `also:`, `events:`).
fn scene_list(block: &[&str], key: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < block.len() {
        let is_key = block[i]
            .split_once(':')
            .map(|(k, v)| k.trim().eq_ignore_ascii_case(key) && v.trim().is_empty())
            .unwrap_or(false);
        if is_key {
            for l in &block[i + 1..] {
                match l.trim_start().strip_prefix("- ") {
                    Some(item) => out.push(item.trim().to_string()),
                    None => break,
                }
            }
            return out;
        }
        i += 1;
    }
    out
}

/// Parse an `also:` placement string: `{ timeline: Past, at: 40 }` →
/// ("Past", "40"). Placement strings are opaque everywhere else.
fn parse_placement(item: &str) -> Option<(String, String)> {
    let inner = item.trim().strip_prefix('{')?.strip_suffix('}')?;
    let mut axis = None;
    let mut coord = String::new();
    for part in inner.split(',') {
        let (k, v) = part.split_once(':')?;
        match k.trim() {
            "timeline" => axis = Some(v.trim().to_string()),
            "at" | "day" | "time" => coord = v.trim().to_string(),
            _ => {}
        }
    }
    Some((axis?, coord))
}

type Extras = (Option<String>, Option<String>, Option<String>, Vec<String>, Vec<String>, Vec<(String, String)>);

fn parse_scene_extras(block: &[&str]) -> Extras {
    let also = scene_list(block, "also")
        .iter()
        .filter_map(|s| parse_placement(s))
        .collect();
    (
        scene_field(block, "timeline"),
        scene_field(block, "narrative_mode"),
        scene_field(block, "stage"),
        scene_list(block, "plotlines"),
        scene_list(block, "events"),
        also,
    )
}

// --- Reference cards ----------------------------------------------------------

/// Frontmatter of a card as top-level key → scalar-or-list items.
fn card_meta(path: &Path) -> std::collections::HashMap<String, Vec<String>> {
    let mut out = std::collections::HashMap::new();
    let Ok(text) = fs::read_to_string(path) else { return out };
    let lines: Vec<&str> = text.lines().collect();
    if lines.first().copied() != Some("---") {
        return out;
    }
    let Some(close) = lines.iter().skip(1).position(|l| l.trim() == "---").map(|p| p + 1) else {
        return out;
    };
    let mut i = 1;
    while i < close {
        let Some((k, v)) = lines[i].split_once(':') else { i += 1; continue };
        let key = k.trim().to_string();
        if v.trim().is_empty() {
            let mut items = Vec::new();
            for l in &lines[i + 1..close] {
                match l.trim_start().strip_prefix("- ") {
                    Some(item) => items.push(item.trim().to_string()),
                    None => break,
                }
            }
            let count = items.len();
            out.insert(key, items);
            i += 1 + count;
        } else {
            out.insert(key, vec![v.trim().trim_matches('"').to_string()]);
            i += 1;
        }
    }
    out
}

/// The primary name of a card file: its first heading up to a dash/colon.
fn card_name(path: &Path, meta: &std::collections::HashMap<String, Vec<String>>) -> String {
    if let Ok(text) = fs::read_to_string(path) {
        for line in text.lines().take(16) {
            if let Some(h) = line.strip_prefix("# ").or_else(|| line.strip_prefix("## ")) {
                return h.split(['—', '–', ':']).next().unwrap_or(h).trim().to_string();
            }
        }
    }
    // Fall back to the declared alias set, then the file stem.
    meta.get("names")
        .and_then(|n| n.first().cloned())
        .unwrap_or_else(|| path.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default())
}

fn load_tracks(root: &Path) -> Vec<Track> {
    let mut out = Vec::new();
    for p in list_md(&root.join("references/plotlines")).unwrap_or_default() {
        let meta = card_meta(&p);
        if std::env::var("ST_DEBUG").is_ok() { eprintln!("track {:?} meta = {:?}", p, meta); }
        let stages = meta.get("stages").cloned().unwrap_or_default();
        let arc_of = meta.get("relations").and_then(|rels| {
            rels.iter()
                .filter(|r| r.contains("arc_of"))
                .find_map(|r| {
                    // The arc target is the edge's `to:` — flow map or pair.
                    let inner =
                        r.trim().strip_prefix('{').and_then(|s| s.strip_suffix('}')).unwrap_or(r);
                    inner.split(',').find_map(|part| {
                        let (k, v) = part.split_once(':')?;
                        (k.trim() == "to").then(|| v.trim().to_string())
                    })
                })
        });
        out.push(Track {
            name: card_name(&p, &meta),
            stages,
            arc_of,
        });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
}

fn list_md(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    if !dir.is_dir() {
        return Ok(out);
    }
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in fs::read_dir(&d)? {
            let entry = entry?;
            let path = entry.path();
            let rel = path
                .strip_prefix(dir)
                .unwrap_or(&path)
                .to_string_lossy()
                .to_string();
            if is_excluded(&rel) {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().map(|e| e == "md").unwrap_or(false) {
                out.push(path);
            }
        }
    }
    out.sort();
    Ok(out)
}

fn parse_scene_block(block: &[&str]) -> (Option<String>, Option<String>, Option<String>, Option<i64>) {
    // Coordinate precedence matches the standard: `at` › `day` › `time`.
    let coord = ["at", "day", "time"]
        .iter()
        .find_map(|k| scene_field(block, k).and_then(|v| v.trim().parse().ok()));
    (
        scene_field(block, "status"),
        scene_field(block, "pov"),
        scene_field(block, "location"),
        coord,
    )
}

/// Apply every parsed field to a freshly-opened scene.
fn finalize_scene(mut sc: Scene, block: &[&str]) -> Scene {
    let (status, pov, location, day) = parse_scene_block(block);
    let (axis, mode, stage, plotlines, events, also) = parse_scene_extras(block);
    sc.status = status;
    sc.pov = pov;
    sc.location = location;
    sc.day = day;
    sc.axis = axis;
    sc.mode = mode;
    sc.stage = stage;
    sc.plotlines = plotlines;
    sc.events = events;
    sc.also = also;
    sc
}

pub fn load(root: &Path) -> Result<Project> {
    let mut prj = Project { root: root.to_path_buf(), ..Default::default() };
    for file in list_md(&root.join("chapters"))? {
        let text = fs::read_to_string(&file)?;
        let lines: Vec<&str> = text.lines().collect();
        let mut chapter = Chapter {
            title: file.file_stem().unwrap_or_default().to_string_lossy().to_string(),
            file: file.clone(),
            words: 0,
            target: None,
            status: None,
        };
        let mut in_fence = false;
        let mut current: Option<Scene> = None;
        let mut yaml_block: Vec<&str> = Vec::new();
        let mut in_yaml = false;
        // Scenes of this file, buffered so a shelved chapter can drop them.
        let mut file_scenes: Vec<Scene> = Vec::new();

        for (i, line) in lines.iter().enumerate() {
            // Chapter frontmatter keys (before the first scene heading).
            if current.is_none() {
                if let Some(rest) = line.strip_prefix("target:") {
                    if chapter.target.is_none() {
                        chapter.target = rest.trim().parse().ok();
                    }
                }
                if chapter.status.is_none() {
                    if let Some(rest) = line.strip_prefix("status:") {
                        let s = rest.trim();
                        if !s.is_empty() {
                            chapter.status = Some(s.to_string());
                        }
                    }
                }
            }
            if line.starts_with("# ") && chapter.title == file.file_stem().unwrap_or_default().to_string_lossy() {
                chapter.title = line[2..].trim().to_string();
            }
            if let Some(title) = line.strip_prefix("## ") {
                if let Some(sc) = current.take() {
                    file_scenes.push(finalize_scene(sc, &yaml_block));
                }
                yaml_block.clear();
                in_yaml = false;
                current = Some(Scene {
                    title: title.trim().to_string(),
                    chapter: chapter.title.clone(),
                    file: file.clone(),
                    line: i + 1,
                    words: 0,
                    ..Default::default()
                });
                continue;
            }
            if let Some(sc) = current.as_mut() {
                if line.trim() == "```yaml" && yaml_block.is_empty() {
                    in_yaml = true;
                    continue;
                }
                if in_yaml {
                    if line.trim() == "```" {
                        in_yaml = false;
                    } else {
                        yaml_block.push(line);
                    }
                    continue;
                }
                sc.words += count_prose(line, &mut in_fence);
            } else {
                let _ = count_prose(line, &mut in_fence);
            }
        }
        if let Some(sc) = current.take() {
            file_scenes.push(finalize_scene(sc, &yaml_block));
        }
        // The standard's shelving rule: `status: unused` scenes and whole
        // chapters stay out of views and word totals, matching their
        // exclusion from compilation.
        if chapter.status.as_deref() != Some("unused") {
            let kept: Vec<Scene> = file_scenes
                .into_iter()
                .filter(|s| s.status.as_deref() != Some("unused"))
                .collect();
            chapter.words = kept.iter().map(|s| s.words).sum();
            prj.total_words += chapter.words;
            prj.scenes.extend(kept);
        }
        prj.chapters.push(chapter);
    }
    prj.tracks = load_tracks(root);
    Ok(prj)
}

impl Project {
    #[allow(dead_code)]
    pub fn by_status(&self, status: &str) -> Vec<&Scene> {
        self.scenes
            .iter()
            .filter(|s| s.status.as_deref().unwrap_or("outline") == status)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn parses_chapters_scenes_and_metadata() {
        let dir = std::env::temp_dir().join(format!("st-tui-test-{}", std::process::id()));
        fs::create_dir_all(dir.join("chapters")).unwrap();
        fs::write(dir.join(".storyteller"), "").unwrap();
        fs::write(
            dir.join("chapters/01.md"),
            "# Chapter One\n\n## The warning\n```yaml\nstoryteller: scene\nstatus: draft\npov: Odysseus\nday: 1\n```\nThe rain had not stopped.\n\n## The storm\n```yaml\nstoryteller: scene\nstatus: done\n```\nWords words words.\n",
        )
        .unwrap();
        fs::write(
            dir.join("chapters/_unused.md"),
            "# Skipped\n\n## Hidden\nprose",
        )
        .unwrap();

        let prj = load(&dir).unwrap();
        assert_eq!(prj.chapters.len(), 1);
        assert_eq!(prj.chapters[0].title, "Chapter One");
        assert_eq!(prj.scenes.len(), 2);
        assert_eq!(prj.scenes[0].status.as_deref(), Some("draft"));
        assert_eq!(prj.scenes[0].pov.as_deref(), Some("Odysseus"));
        assert_eq!(prj.scenes[0].day, Some(1));
        assert_eq!(prj.scenes[0].words, 5);
        assert_eq!(prj.scenes[1].status.as_deref(), Some("done"));
        // Unscheduled scenes sort after scheduled ones in story order.
        let axes = storyteller_core::axes::Axes { by_name: std::collections::HashMap::new() };
        let ctx = crate::ui::TlCtx {
            axes: &axes,
            axis: "main",
            story_order: true,
            swimlane: crate::ui::Swimlane::Off,
            staged: &[],
        };
        let rows = crate::ui::timeline_rows(&prj, &ctx);
        assert_eq!(rows[0].scene.title, "The warning");
        assert_eq!(rows[1].scene.title, "The storm");

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn shelved_scenes_and_chapters_are_excluded() {
        let dir = std::env::temp_dir().join(format!("st-tui-shelf-{}", std::process::id()));
        fs::create_dir_all(dir.join("chapters")).unwrap();
        fs::write(
            dir.join("chapters/01.md"),
            "# Chapter One\n\n## Kept\n```yaml\nstoryteller: scene\nday: 1\n```\nFive words here now.\n\n## Shelved\n```yaml\nstoryteller: scene\nstatus: unused\nday: 2\n```\nTen words that should not count at all.\n",
        )
        .unwrap();
        fs::write(
            dir.join("chapters/02-cave.md"),
            "---\nstatus: unused\n---\n\n# Chapter Two\n\n## The cave\nprose words words\n",
        )
        .unwrap();

        let prj = load(&dir).unwrap();
        assert_eq!(prj.chapters.len(), 2);
        assert_eq!(prj.chapters[1].status.as_deref(), Some("unused"));
        // Only the kept scene survives; the unused chapter contributes nothing.
        assert_eq!(prj.scenes.len(), 1);
        assert_eq!(prj.scenes[0].title, "Kept");
        assert_eq!(prj.total_words, 4);
        assert_eq!(prj.chapters[0].words, 4);
        assert_eq!(prj.chapters[1].words, 0);

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn coordinate_falls_back_at_then_day_then_time() {
        let dir = std::env::temp_dir().join(format!("st-tui-coord-{}", std::process::id()));
        fs::create_dir_all(dir.join("chapters")).unwrap();
        fs::write(
            dir.join("chapters/01.md"),
            "# C\n\n## A\n```yaml\nstoryteller: scene\nat: 5\nday: 9\n```\nx\n\n## B\n```yaml\nstoryteller: scene\ntime: 3\n```\nx\n",
        )
        .unwrap();
        let prj = load(&dir).unwrap();
        assert_eq!(prj.scenes[0].day, Some(5), "at wins over day");
        assert_eq!(prj.scenes[1].day, Some(3), "numeric time is a coordinate");

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn parses_placements_modes_stages_and_tracks() {
        let dir = std::env::temp_dir().join(format!("st-tui-v12-{}", std::process::id()));
        fs::create_dir_all(dir.join("chapters")).unwrap();
        fs::create_dir_all(dir.join("references/plotlines")).unwrap();
        fs::write(
            dir.join("references/plotlines/telemachy.md"),
            "---\nnames:\n  - Telemachy\nstages:\n  - helpless\n  - companion\nrelations:\n  - { to: Telemachus, kind: arc_of }\n---\n\n## Telemachy\n",
        )
        .unwrap();
        fs::write(
            dir.join("chapters/01.md"),
            "# C\n\n## The crossing\n```yaml\nstoryteller: scene\ntimeline: Present\nat: 12\nnarrative_mode: linear\nalso:\n  - { timeline: Past, at: 40 }\nplotlines:\n  - Telemachy\nstage: helpless\nevents:\n  - The Assembly\n```\nx\n",
        )
        .unwrap();

        let prj = load(&dir).unwrap();
        let sc = &prj.scenes[0];
        assert_eq!(sc.axis.as_deref(), Some("Present"));
        assert_eq!(sc.mode.as_deref(), Some("linear"));
        assert_eq!(sc.stage.as_deref(), Some("helpless"));
        assert_eq!(sc.plotlines, vec!["Telemachy".to_string()]);
        assert_eq!(sc.events, vec!["The Assembly".to_string()]);
        assert_eq!(sc.also, vec![("Past".to_string(), "40".to_string())]);

        assert_eq!(prj.tracks.len(), 1);
        assert_eq!(prj.tracks[0].name, "Telemachy");
        assert_eq!(prj.tracks[0].stages, vec!["helpless".to_string(), "companion".to_string()]);
        assert_eq!(prj.tracks[0].arc_of.as_deref(), Some("Telemachus"));

        fs::remove_dir_all(&dir).ok();
    }
}
