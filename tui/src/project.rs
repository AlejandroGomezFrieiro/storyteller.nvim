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
}

#[derive(Debug, Clone, Default)]
pub struct Chapter {
    pub title: String,
    pub file: PathBuf,
    pub words: usize,
}

#[derive(Debug, Clone, Default)]
pub struct Project {
    pub root: PathBuf,
    pub chapters: Vec<Chapter>,
    pub scenes: Vec<Scene>,
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
    (
        scene_field(block, "status"),
        scene_field(block, "pov"),
        scene_field(block, "location"),
        scene_field(block, "day").and_then(|d| d.trim().parse().ok()),
    )
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
        };
        let mut in_fence = false;
        let mut current: Option<Scene> = None;
        let mut yaml_block: Vec<&str> = Vec::new();
        let mut in_yaml = false;

        for (i, line) in lines.iter().enumerate() {
            if line.starts_with("# ") && chapter.title == file.file_stem().unwrap_or_default().to_string_lossy() {
                chapter.title = line[2..].trim().to_string();
            }
            if let Some(title) = line.strip_prefix("## ") {
                if let Some(mut sc) = current.take() {
                    let (status, pov, location, day) = parse_scene_block(&yaml_block);
                    sc.status = status;
                    sc.pov = pov;
                    sc.location = location;
                    sc.day = day;
                    prj.scenes.push(sc);
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
        if let Some(mut sc) = current.take() {
            let (status, pov, location, day) = parse_scene_block(&yaml_block);
            sc.status = status;
            sc.pov = pov;
            sc.location = location;
            sc.day = day;
            prj.scenes.push(sc);
        }
        chapter.words = prj.scenes
            .iter()
            .filter(|s| s.file == file)
            .map(|s| s.words)
            .sum();
        prj.total_words += chapter.words;
        prj.chapters.push(chapter);
    }
    Ok(prj)
}

impl Project {
    // Timeline order: numeric days first (ascending), then manuscript order.
    pub fn timeline(&self) -> Vec<&Scene> {
        let mut scenes: Vec<&Scene> = self.scenes.iter().collect();
        scenes.sort_by_key(|s| (s.day.unwrap_or(i64::MAX), 0usize));
        scenes
    }

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

        let tl = prj.timeline();
        assert_eq!(tl[0].title, "The warning");
        assert_eq!(tl[1].title, "The storm"); // unscheduled sorts last

        fs::remove_dir_all(&dir).ok();
    }
}
