// Compilation: strip frontmatter/scene-metadata to a longform manuscript.
// Mirrors storyteller.compile.strip_metadata on the Lua side.

use crate::index::Index;

// Turn chapter lines into prose-only lines:
//   * drop the leading YAML front matter (--- ... ---)
//   * drop ```yaml storyteller: scene``` metadata blocks
//   * drop inline `- **Key:** value` metadata bullets
//   * drop `- [ ]` planning checklists
// Everything else (headings, prose, real lists, non-scene code fences) is
// preserved verbatim.
pub fn strip_metadata(lines: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    let mut start = 0usize;
    if lines.first().map(|l| l.trim()) == Some("---") {
        for i in 1..lines.len() {
            if lines[i].trim() == "---" {
                start = i + 1;
                break;
            }
        }
    }
    let mut in_scene_yaml = false;
    for i in start..lines.len() {
        let ln = lines[i].as_str();
        if ln == "```yaml" {
            if lines.get(i + 1).map(|n| n.trim()) == Some("storyteller: scene") {
                in_scene_yaml = true;
            } else {
                out.push(ln.to_string());
            }
        } else if in_scene_yaml {
            if ln == "```" {
                in_scene_yaml = false;
            }
        } else if !is_inline_meta(ln) && !is_checklist(ln) {
            out.push(ln.to_string());
        }
    }
    out
}

fn is_inline_meta(line: &str) -> bool {
    let t = line.trim_start();
    let Some(rest) = t.strip_prefix("- ") else {
        return false;
    };
    let rest = rest.trim_start();
    let Some(rest) = rest.strip_prefix("**") else {
        return false;
    };
    // `- **Key:** value` (or the `- **Key**: value` variant): a bold key
    // followed by a colon or the closing bold.
    let key_len = rest
        .chars()
        .take_while(|c| c.is_alphanumeric() || *c == '_')
        .count();
    if key_len == 0 {
        return false;
    }
    matches!(rest[key_len..].trim_start().chars().next(), Some(':') | Some('*'))
}

fn is_checklist(line: &str) -> bool {
    let t = line.trim_start();
    t.starts_with("- [ ]") || t.starts_with("- [x]") || t.starts_with("- [X]")
}

// Metadata-free longform for the whole project. When `with_headings` is set,
// each chapter is prefixed with a `# Title` separator.
pub fn manuscript_text(index: &Index, with_headings: bool) -> String {
    let mut out: Vec<String> = Vec::new();
    for ch in &index.chapters {
        let lines: Vec<String> = std::fs::read_to_string(&ch.path)
            .map(|s| s.lines().map(String::from).collect())
            .unwrap_or_default();
        if with_headings {
            out.push(format!("# {}", ch.title));
        }
        out.extend(strip_metadata(&lines));
        out.push(String::new());
        out.push(String::new());
    }
    out.join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_frontmatter_and_scene_yaml() {
        let lines: Vec<String> = vec![
            "---",
            "status: draft",
            "---",
            "# Chapter 1",
            "",
            "## Scene 1",
            "",
            "```yaml",
            "storyteller: scene",
            "pov: Odysseus",
            "```",
            "",
            "Odysseus rowed.",
            "- **Beat:** the harbor",
            "- [ ] plan this",
            "A plain list:",
            "- real item",
        ]
        .into_iter()
        .map(String::from)
        .collect();
        let out = strip_metadata(&lines);
        assert!(!out.iter().any(|l| l == "status: draft" || l == "pov: Odysseus"));
        assert!(!out.iter().any(|l| l.starts_with("- **Beat:**")));
        assert!(!out.iter().any(|l| l.starts_with("- [ ]")));
        assert!(out.iter().any(|l| l == "Odysseus rowed."));
        assert!(out.iter().any(|l| l == "- real item"));
    }
}
