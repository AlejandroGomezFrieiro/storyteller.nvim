//! store.rs — the staged-edit engine (docs/rework-plan.md Phase C).
//!
//! Views stage [`Op`]s against the project; [`Store::apply`] transforms every
//! touched file fully in memory, then writes atomically (temp-file + rename).
//! Writes are surgical: only patched key lines move; comments and unknown
//! lines keep their byte positions — the same contract as the Lua projection
//! engine (`meta/write.lua`), pinned by the shared golden fixtures under
//! `tests/projections/`.

#![allow(dead_code)]

use anyhow::{anyhow, bail, Context, Result};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

/// Addresses a scene by chapter file plus its `## ` heading line (0-based).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SceneRef {
    /// Path relative to the project root, forward slashes.
    pub file: String,
    pub line: usize,
}

/// Addresses a reference card by path plus its heading line (0-based).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CardRef {
    pub file: String,
    pub line: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Setup,
    Payoff,
}

impl Side {
    fn field(self) -> &'static str {
        match self {
            Side::Setup => "setup",
            Side::Payoff => "payoff",
        }
    }
}

#[derive(Debug, Clone)]
pub enum Op {
    /// Write one scene YAML key; `None` removes it.
    SetField {
        scene: SceneRef,
        key: String,
        value: Option<String>,
    },
    /// Coordinate write: rewrites whichever of `at:`/`day:`/`time:` holds the
    /// coordinate (default `day` when unscheduled); `None` clears scheduling.
    SetCoord {
        scene: SceneRef,
        coord: Option<String>,
    },
    /// Append one `also:` placement as a flow-map string.
    AddPlacement {
        scene: SceneRef,
        axis: String,
        coord: String,
    },
    /// Remove the `also:` placement focused on `axis`.
    RemovePlacement {
        scene: SceneRef,
        axis: String,
    },
    /// Stage-cell write; sugar for `SetField("stage")`.
    SetStage {
        scene: SceneRef,
        stage: Option<String>,
    },
    AttachPlotline {
        scene: SceneRef,
        name: String,
    },
    DetachPlotline {
        scene: SceneRef,
        name: String,
    },
    AttachThread {
        scene: SceneRef,
        side: Side,
        key: String,
    },
    DetachThread {
        scene: SceneRef,
        side: Side,
        key: String,
    },
    AddEdge {
        card: CardRef,
        to: String,
        kind: String,
    },
    RemoveEdge {
        card: CardRef,
        to: String,
    },
    RenameEdge {
        card: CardRef,
        to: String,
        kind: String,
    },
}

impl Op {
    /// The file this op transforms.
    fn file(&self) -> &str {
        match self {
            Op::SetField { scene, .. }
            | Op::SetCoord { scene, .. }
            | Op::AddPlacement { scene, .. }
            | Op::RemovePlacement { scene, .. }
            | Op::SetStage { scene, .. }
            | Op::AttachPlotline { scene, .. }
            | Op::DetachPlotline { scene, .. }
            | Op::AttachThread { scene, .. }
            | Op::DetachThread { scene, .. } => &scene.file,
            Op::AddEdge { card, .. }
            | Op::RemoveEdge { card, .. }
            | Op::RenameEdge { card, .. } => &card.file,
        }
    }

    /// The 0-based heading line this op anchors to.
    fn line(&self) -> usize {
        match self {
            Op::SetField { scene, .. }
            | Op::SetCoord { scene, .. }
            | Op::AddPlacement { scene, .. }
            | Op::RemovePlacement { scene, .. }
            | Op::SetStage { scene, .. }
            | Op::AttachPlotline { scene, .. }
            | Op::DetachPlotline { scene, .. }
            | Op::AttachThread { scene, .. }
            | Op::DetachThread { scene, .. } => scene.line,
            Op::AddEdge { card, .. }
            | Op::RemoveEdge { card, .. }
            | Op::RenameEdge { card, .. } => card.line,
        }
    }

    fn describe(&self) -> String {
        match self {
            Op::SetField { scene, key, .. } => format!("{}:{} set {}", scene.file, scene.line, key),
            Op::SetCoord { scene, .. } => format!("{}:{} coord", scene.file, scene.line),
            Op::AddPlacement { scene, axis, .. } => {
                format!("{}:{} +placement {}", scene.file, scene.line, axis)
            }
            Op::RemovePlacement { scene, axis, .. } => {
                format!("{}:{} -placement {}", scene.file, scene.line, axis)
            }
            Op::AttachPlotline { scene, name, .. } => {
                format!("{}:{} +plotline {}", scene.file, scene.line, name)
            }
            Op::DetachPlotline { scene, name, .. } => {
                format!("{}:{} -plotline {}", scene.file, scene.line, name)
            }
            Op::AttachThread { scene, side, key } => {
                format!("{}:{} +{} {}", scene.file, scene.line, side.field(), key)
            }
            Op::DetachThread { scene, side, key } => {
                format!("{}:{} -{} {}", scene.file, scene.line, side.field(), key)
            }
            Op::SetStage { scene, stage } => {
                format!(
                    "{}:{} stage={}",
                    scene.file,
                    scene.line,
                    stage.as_deref().unwrap_or("—")
                )
            }
            Op::AddEdge { card, to, kind } => {
                format!("{}:{} +edge {} {}", card.file, card.line, kind, to)
            }
            Op::RemoveEdge { card, to } => format!("{}:{} -edge {}", card.file, card.line, to),
            Op::RenameEdge { card, to, kind } => {
                format!("{}:{} edge {}→{}", card.file, card.line, to, kind)
            }
        }
    }
}

// --- YAML scene-block primitives -------------------------------------------

struct Block {
    fence: usize,
    sentinel: usize,
    close: usize,
}

/// Locate the scene YAML block governed by the `## ` heading at `heading`.
fn scene_block(lines: &[String], heading: usize) -> Option<Block> {
    let mut first = heading + 1;
    while first < lines.len() && lines[first].trim().is_empty() {
        first += 1;
    }
    if lines.get(first)?.trim() != "```yaml" {
        return None;
    }
    let sentinel = first + 1;
    if lines.get(sentinel)?.trim() != "storyteller: scene" {
        return None;
    }
    let mut close = sentinel + 1;
    while close < lines.len() && lines[close].trim() != "```" {
        close += 1;
    }
    if close >= lines.len() {
        return None;
    }
    Some(Block {
        fence: first,
        sentinel,
        close,
    })
}

/// Top-level key ranges inside a block's content: (key, start, stop) inclusive,
/// list items folded into their key. Keys sit at column 0 between sentinel and
/// close; anything else (comments, blanks) is invisible to this map.
fn key_ranges(lines: &[String], b: &Block) -> Vec<(String, usize, usize)> {
    let mut out = Vec::new();
    let mut i = b.sentinel + 1;
    while i < b.close {
        let line = &lines[i];
        if !line.starts_with(' ') && !line.is_empty() {
            if let Some((k, v)) = line.split_once(':') {
                if !k.contains(char::is_whitespace) {
                    let mut stop = i;
                    if v.trim().is_empty() {
                        while stop + 1 < b.close && lines[stop + 1].starts_with("  - ") {
                            stop += 1;
                        }
                    }
                    out.push((k.to_string(), i, stop));
                    i = stop + 1;
                    continue;
                }
            }
        }
        i += 1;
    }
    out
}

fn scene_new_id() -> String {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:012x}", nanos)
}

/// Surgical single-key write inside the scene block. Returns true when the
/// file content changed. Mirrors `meta/write.lua::scene_write`: replaced keys
/// stay in place, removals take their list items with them, and unknown lines
/// plus comments never move. (The Lua engine additionally invents an id for
/// id-less scenes; the TUI does not — golden fixtures use id-bearing scenes.)
fn scene_set_field(
    lines: &mut Vec<String>,
    heading: usize,
    key: &str,
    value: Option<&str>,
) -> Result<bool> {
    let b = scene_block(lines, heading)
        .ok_or_else(|| anyhow!("scene at line {} has no metadata block", heading + 1))?;
    let ranges = key_ranges(lines, &b);

    // Removal: take the key's list items with it.
    let Some(value) = value else {
        for (k, start, stop) in &ranges {
            if k == key {
                for i in (*start..=*stop).rev() {
                    lines.remove(i);
                }
                return Ok(true);
            }
        }
        return Ok(false);
    };

    // Replacement in place (a scalar demotes a list to a single line).
    for (k, start, stop) in &ranges {
        if k == key {
            lines[*start] = format!("{key}: {value}");
            for i in (*start + 1..=*stop).rev() {
                lines.remove(i);
            }
            return Ok(true);
        }
    }

    // Insertion just before the closing fence — the same placement the Lua
    // engine's sorted-additions path produces.
    lines.insert(b.close, format!("{key}: {value}"));
    Ok(true)
}

// --- List-item primitives ----------------------------------------------------

fn list_add(lines: &mut Vec<String>, heading: usize, key: &str, item: &str) -> Result<()> {
    let b = scene_block(lines, heading)
        .ok_or_else(|| anyhow!("scene at line {} has no metadata block", heading + 1))?;
    let ranges = key_ranges(lines, &b);
    let item_line = format!("  - {item}");
    for (k, _start, stop) in &ranges {
        if k == key {
            lines.insert(stop + 1, item_line);
            return Ok(());
        }
    }
    // Absent key: create the list just before the closing fence.
    lines.insert(b.close, key.to_owned());
    lines.insert(b.close + 1, item_line);
    Ok(())
}

fn list_remove(lines: &mut Vec<String>, heading: usize, key: &str, item: &str) -> Result<bool> {
    let b = scene_block(lines, heading)
        .ok_or_else(|| anyhow!("scene at line {} has no metadata block", heading + 1))?;
    let ranges = key_ranges(lines, &b);
    for (k, start, stop) in &ranges {
        if k != key {
            continue;
        }
        let needle = format!("  - {item}");
        let found = lines[*start..=*stop]
            .iter()
            .position(|l| *l == needle)
            .map(|p| *start + p);
        let Some(at) = found else {
            return Ok(false);
        };
        lines.remove(at);
        // An emptied list (key line + exactly one item) drops its bare key.
        if stop - start == 1 {
            lines.remove(*start);
        }
        return Ok(true);
    }
    Ok(false)
}

// --- Card frontmatter edges ---------------------------------------------------

struct Frontmatter {
    start: usize, // first line after the opening ---
    end: usize,   // line index of the closing ---
}

fn frontmatter(lines: &[String]) -> Option<Frontmatter> {
    if lines.first()?.trim() != "---" {
        return None;
    }
    for (i, l) in lines.iter().enumerate().skip(1) {
        if l.trim() == "---" {
            return Some(Frontmatter { start: 1, end: i });
        }
    }
    None
}

/// One `relations:` entry as (start, end, to, kind, is_shorthand).
fn relation_items(lines: &[String], fm: &Frontmatter) -> Vec<(usize, usize, String, String, bool)> {
    let mut out = Vec::new();
    let mut in_relations = false;
    let mut cur: Option<(usize, String, String, bool)> = None;
    for (i, line) in lines.iter().enumerate().take(fm.end).skip(fm.start) {
        if !in_relations {
            if line.starts_with("relations:") {
                in_relations = true;
            }
            continue;
        }
        if let Some(rest) = line.strip_prefix("  - ") {
            if let Some((s, to, kind, sh)) = cur.take() {
                out.push((s, i - 1, to, kind, sh));
            }
            if let Some(to) = flow_or_pair_to(rest) {
                cur = Some((i, to, entry_kind(rest), false));
            } else if let Some((k, v)) = rest.split_once(':') {
                let target = v.trim();
                if k.trim() == "to" {
                    cur = Some((i, target.to_string(), "related".into(), false));
                } else if !target.is_empty() {
                    cur = Some((i, target.to_string(), k.trim().to_string(), true));
                } else {
                    cur = None;
                }
            } else {
                cur = None;
            }
        } else if line.starts_with(' ') {
            if let Some((_, to, kind, _)) = cur.as_mut() {
                if let Some((k, v)) = line.trim().split_once(':') {
                    match k.trim() {
                        "kind" => *kind = v.trim().to_string(),
                        "to" if to.is_empty() => {
                            *to = v.trim().to_string();
                        }
                        _ => {}
                    }
                }
            }
        } else {
            if let Some((s, to, kind, sh)) = cur.take() {
                out.push((s, i - 1, to, kind, sh));
            }
            in_relations = false;
        }
    }
    if let Some((s, to, kind, sh)) = cur.take() {
        out.push((s, fm.end - 1, to, kind, sh));
    }
    out
}

fn entry_kind(rest: &str) -> String {
    for part in rest.trim_matches(|p| p == '{' || p == '}').split(',') {
        if let Some((k, v)) = part.split_once(':') {
            if k.trim() == "kind" {
                return v.trim().to_string();
            }
        }
    }
    "related".to_string()
}

fn flow_or_pair_to(rest: &str) -> Option<String> {
    let inner = rest.trim().strip_prefix('{')?.strip_suffix('}')?;
    for part in inner.split(',') {
        if let Some((k, v)) = part.split_once(':') {
            if k.trim() == "to" {
                return Some(v.trim().to_string());
            }
        }
    }
    None
}

fn edge_add(lines: &mut Vec<String>, fm: &Frontmatter, card_line: usize, to: &str, kind: &str) {
    let items = relation_items(lines, fm);
    let entry = [format!("  - to: {to}"), format!("    kind: {kind}")];
    match items.last() {
        Some(&(_start, end, ..)) => {
            for (off, l) in entry.iter().enumerate() {
                lines.insert(end + 1 + off, l.clone());
            }
        }
        None => {
            // No relations yet: find where the card's frontmatter ends and
            // append the list there.
            let at = fm.end.max(card_line + 1);
            lines.insert(at, "relations:".to_string());
            for (off, l) in entry.iter().enumerate() {
                lines.insert(at + 1 + off, l.clone());
            }
        }
    }
}

fn edge_remove(lines: &mut Vec<String>, fm: &Frontmatter, to: &str) -> bool {
    let items = relation_items(lines, fm);
    for (start, end, eto, _, _) in items {
        if eto == to {
            for i in (start..=end).rev() {
                lines.remove(i);
            }
            return true;
        }
    }
    false
}

fn edge_rename(lines: &mut Vec<String>, fm: &Frontmatter, to: &str, kind: &str) -> Result<()> {
    let items = relation_items(lines, fm);
    for (start, end, eto, _declared_kind, shorthand) in items {
        if eto != to {
            continue;
        }
        if shorthand {
            // Shorthand encodes the kind as its key; conversion to block-map
            // form is the documented exception (rework-plan §store).
            lines[start] = format!("  - to: {eto}");
            lines.insert(start + 1, format!("    kind: {kind}"));
        } else {
            // Rewrite the kind line in place when the entry declares one;
            // otherwise make the entry an explicit flow map.
            let kind_at = (start..=end).find(|i| lines[*i].trim_start().starts_with("kind:"));
            match kind_at {
                Some(i) => {
                    let indent = lines[i].len() - lines[i].trim_start().len();
                    lines[i] = format!("{}kind: {kind}", " ".repeat(indent));
                }
                None => {
                    lines[start] = format!("  - {{ to: {eto}, kind: {kind} }}");
                }
            }
        }
        return Ok(());
    }
    bail!("no edge to “{to}” to rename")
}

// --- Store ---------------------------------------------------------------------

/// Sorted (path, mtime_ns, size) over every indexed `.md` under root.
fn fingerprint(root: &Path) -> Result<Vec<(String, u128, u64)>> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(d) = stack.pop() {
        for entry in fs::read_dir(&d).with_context(|| d.display().to_string())? {
            let path = entry?.path();
            let name = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            if name.starts_with('_') || name.starts_with('.') {
                continue;
            }
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().map(|e| e == "md").unwrap_or(false) {
                let meta = fs::metadata(&path)?;
                let mtime = meta
                    .modified()
                    .ok()
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_nanos())
                    .unwrap_or(0);
                out.push((
                    path.strip_prefix(root)
                        .unwrap_or(&path)
                        .to_string_lossy()
                        .to_string(),
                    mtime,
                    meta.len(),
                ));
            }
        }
    }
    out.sort();
    Ok(out)
}

fn git_snapshot(root: &Path, note: &str) {
    let inside = std::process::Command::new("git")
        .args(["-C", &root.display().to_string(), "rev-parse", "--git-dir"])
        .output();
    if !inside.map(|o| o.status.success()).unwrap_or(false) {
        return;
    }
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let subject = format!("storyteller:snapshot {ts} — {note}");
    let _ = std::process::Command::new("git")
        .args(["-C", &root.display().to_string(), "add", "-A"])
        .output();
    let _ = std::process::Command::new("git")
        .args([
            "-C",
            &root.display().to_string(),
            "commit",
            "-q",
            "-m",
            &subject,
        ])
        .output();
}

fn atomic_write(path: &Path, lines: &[String]) -> Result<()> {
    let tmp = path.with_extension("md.staged");
    fs::write(&tmp, lines.join("\n") + "\n")
        .with_context(|| format!("staging {}", tmp.display()))?;
    fs::rename(&tmp, path).with_context(|| format!("writing {}", path.display()))?;
    Ok(())
}

/// Staged edits over one project root. `apply` is atomic across files and
/// aborts when the disk state drifted since load/refresh.
pub struct Store {
    pub root: PathBuf,
    pub staged: Vec<Op>,
    fingerprint: Vec<(String, u128, u64)>,
}

impl Store {
    pub fn new(root: &Path) -> Result<Store> {
        Ok(Store {
            root: root.to_path_buf(),
            staged: Vec::new(),
            fingerprint: fingerprint(root)?,
        })
    }

    pub fn stage(&mut self, op: Op) {
        self.staged.push(op);
    }

    pub fn pending(&self) -> usize {
        self.staged.len()
    }

    pub fn drop_staged(&mut self) {
        self.staged.clear();
    }

    /// Re-read fingerprints after an external reload.
    pub fn refresh(&mut self) -> Result<()> {
        self.fingerprint = fingerprint(&self.root)?;
        self.staged.clear();
        Ok(())
    }

    /// Apply all staged ops atomically. Returns the number of effective ops.
    pub fn apply(&mut self) -> Result<usize> {
        if self.staged.is_empty() {
            return Ok(0);
        }
        let current = fingerprint(&self.root)?;
        if current != self.fingerprint {
            bail!("files changed on disk — R to reload");
        }

        // Group by file, then transform each file's ops against its lines
        // bottom-up so earlier line indices survive the surgery.
        let mut per_file: BTreeMap<String, Vec<Op>> = BTreeMap::new();
        for op in self.staged.drain(..) {
            per_file.entry(op.file().to_string()).or_default().push(op);
        }

        let mut writes: BTreeMap<String, (Vec<String>, usize)> = BTreeMap::new();
        for (file, mut ops) in per_file {
            ops.sort_by_key(|op| std::cmp::Reverse(op.line()));
            let path = self.root.join(&file);
            let text =
                fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
            let mut lines: Vec<String> = text.lines().map(String::from).collect();
            let mut count = 0usize;
            for op in &ops {
                let changed = Self::dispatch(&mut lines, op)?;
                count += changed as usize;
            }
            if count > 0 {
                writes.insert(file, (lines, count));
            }
        }

        let multi_file = writes.len() > 1;
        if multi_file {
            git_snapshot(&self.root, "before staged apply");
        }
        for (file, (lines, _)) in &writes {
            atomic_write(&self.root.join(file), lines)?;
        }
        self.fingerprint = fingerprint(&self.root)?;

        Ok(writes.values().map(|(_, c)| c).sum())
    }

    fn dispatch(lines: &mut Vec<String>, op: &Op) -> Result<bool> {
        match op {
            Op::SetField { scene, key, value } => {
                scene_set_field(lines, scene.line, key, value.as_deref())
            }
            Op::SetCoord { scene, coord } => {
                let b = scene_block(lines, scene.line).ok_or_else(|| {
                    anyhow!("scene at line {} has no metadata block", scene.line + 1)
                })?;
                let holding = key_ranges(lines, &b)
                    .into_iter()
                    .find_map(|(k, _, _)| ["at", "day", "time"].contains(&k.as_str()).then_some(k));
                if coord.is_none() && holding.is_none() {
                    return Ok(false);
                }
                let key = holding.unwrap_or_else(|| "day".to_string());
                scene_set_field(lines, scene.line, &key, coord.as_deref())
            }
            Op::AddPlacement { scene, axis, coord } => {
                let item = format!("{{ timeline: {axis}, at: {coord} }}");
                list_add(lines, scene.line, "also", &item).map(|_| true)
            }
            Op::RemovePlacement { scene, axis } => {
                let b = scene_block(lines, scene.line).ok_or_else(|| {
                    anyhow!("scene at line {} has no metadata block", scene.line + 1)
                })?;
                let ranges = key_ranges(lines, &b);
                let _needle_prefix = "{ timeline: ";
                for (k, start, stop) in ranges {
                    if k != "also" {
                        continue;
                    }
                    for i in start..=stop {
                        let trimmed = lines[i].trim().trim_start_matches("- ").trim();
                        let inner = trimmed
                            .strip_prefix("{ timeline: ")
                            .and_then(|rest| rest.strip_suffix('}'))
                            .unwrap_or("");
                        let entry_axis = inner.split(',').next().unwrap_or("").trim();
                        if entry_axis == axis {
                            lines.remove(i);
                            if stop - start == 1 {
                                lines.remove(start);
                            }
                            return Ok(true);
                        }
                    }
                }
                Ok(false)
            }
            Op::SetStage { scene, stage } => {
                scene_set_field(lines, scene.line, "stage", stage.as_deref())
            }
            Op::AttachPlotline { scene, name } => {
                list_add(lines, scene.line, "plotlines", name).map(|_| true)
            }
            Op::DetachPlotline { scene, name } => list_remove(lines, scene.line, "plotlines", name),
            Op::AttachThread { scene, side, key } => {
                list_add(lines, scene.line, side.field(), key).map(|_| true)
            }
            Op::DetachThread { scene, side, key } => {
                list_remove(lines, scene.line, side.field(), key)
            }
            Op::AddEdge { card, to, kind } => {
                let fm = frontmatter(lines)
                    .ok_or_else(|| anyhow!("card at line {} has no frontmatter", card.line + 1))?;
                edge_add(lines, &fm, card.line, to, kind);
                Ok(true)
            }
            Op::RemoveEdge { card, to } => {
                let fm = frontmatter(lines)
                    .ok_or_else(|| anyhow!("card at line {} has no frontmatter", card.line + 1))?;
                Ok(edge_remove(lines, &fm, to))
            }
            Op::RenameEdge { card, to, kind } => {
                let fm = frontmatter(lines)
                    .ok_or_else(|| anyhow!("card at line {} has no frontmatter", card.line + 1))?;
                edge_rename(lines, &fm, to, kind).map(|_| true)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write_project(files: &[(&str, &str)]) -> (PathBuf, Vec<(String, PathBuf)>) {
        let dir = std::env::temp_dir().join(format!(
            "st-store-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .subsec_nanos()
        ));
        for (rel, content) in files {
            let full = dir.join(rel);
            fs::create_dir_all(full.parent().unwrap()).unwrap();
            fs::write(&full, content).unwrap();
        }
        let paths = files
            .iter()
            .map(|(rel, _)| (rel.to_string(), dir.join(rel)))
            .collect();
        (dir, paths)
    }

    const CHAPTER: &str = "# Chapter One\n\n## The warning\n\n```yaml\nstoryteller: scene\nid: abc123def456\nday: 1\npov: Odysseus\n```\n\nThe rain had not stopped.\n";

    #[test]
    fn set_field_is_surgical_in_place() {
        let mut lines: Vec<String> = CHAPTER.lines().map(String::from).collect();
        // "## The warning" sits at line index 2.
        scene_set_field(&mut lines, 2, "day", Some("5")).unwrap();
        assert_eq!(
            lines.join("\n"),
            "# Chapter One\n\n## The warning\n\n```yaml\nstoryteller: scene\nid: abc123def456\nday: 5\npov: Odysseus\n```\n\nThe rain had not stopped."
        );
    }

    #[test]
    fn clearing_removes_the_key_line() {
        let mut lines: Vec<String> = CHAPTER.lines().map(String::from).collect();
        scene_set_field(&mut lines, 2, "pov", None).unwrap();
        let text = lines.join("\n");
        assert!(!text.contains("pov:"), "pov removed");
        assert!(text.contains("id: abc123def456"), "id untouched");
    }

    #[test]
    fn comments_survive_field_writes() {
        let text = "# C\n\n## S\n\n```yaml\nstoryteller: scene\nid: abc123def456\n# a free-form comment\nday: 1\n```\n\nprose.\n";
        let mut lines: Vec<String> = text.lines().map(String::from).collect();
        scene_set_field(&mut lines, 2, "pov", Some("Odysseus")).unwrap();
        let out = lines.join("\n");
        assert!(out.contains("# a free-form comment"), "comment preserved");
        assert!(
            out.find("# a free-form comment").unwrap() < out.find("day:").unwrap(),
            "comment keeps its position"
        );
        assert!(out.contains("pov: Odysseus"));
    }

    #[test]
    fn list_ops_round_trip() {
        let base = "# C\n\n## S\n\n```yaml\nstoryteller: scene\nid: abc123def456\nplotlines:\n  - Telemachy\n```\n\nx\n";
        let mut lines: Vec<String> = base.lines().map(String::from).collect();
        list_add(&mut lines, 2, "plotlines", "Suitors").unwrap();
        assert!(lines.join("\n").contains("  - Suitors"));
        assert!(list_remove(&mut lines, 2, "plotlines", "Telemachy").unwrap());
        let out = lines.join("\n");
        assert!(out.contains("plotlines:\n  - Suitors"), "one item left");
        assert!(list_remove(&mut lines, 2, "plotlines", "Suitors").unwrap());
        assert!(
            !lines.join("\n").contains("plotlines"),
            "emptied list drops its key"
        );
    }

    #[test]
    fn placement_flow_maps_round_trip() {
        let base = "# C\n\n## S\n\n```yaml\nstoryteller: scene\nid: abc123def456\ntimeline: Present\nday: 12\nalso:\n  - { timeline: Past, at: 40 }\n```\n\nx\n";
        let mut lines: Vec<String> = base.lines().map(String::from).collect();

        Op::AddPlacement {
            scene: SceneRef {
                file: "chapters/01.md".into(),
                line: 2,
            },
            axis: "Far".into(),
            coord: "5".into(),
        }
        .apply_to(&mut lines);
        assert!(lines.join("\n").contains("  - { timeline: Far, at: 5 }"));

        Op::RemovePlacement {
            scene: SceneRef {
                file: "chapters/01.md".into(),
                line: 2,
            },
            axis: "Past".into(),
        }
        .apply_to(&mut lines);
        let out = lines.join("\n");
        assert!(!out.contains("Past"), "past placement removed");
        assert!(out.contains("  - { timeline: Far, at: 5 }"), "sibling kept");
    }

    impl Op {
        fn apply_to(self, lines: &mut Vec<String>) -> bool {
            Store::dispatch(lines, &self).unwrap()
        }
    }

    #[test]
    fn edges_preserve_all_three_syntax_forms() {
        let base = "---\nnames:\n  - Odysseus\nrelations:\n  - { to: Penelope, kind: spouse }\n  - to: Telemachus\n    kind: parent\n  - rival: Poseidon\n---\n\n## Odysseus\n";
        let mut lines: Vec<String> = base.lines().map(String::from).collect();
        let fm = frontmatter(&lines).unwrap();
        let card = CardRef {
            file: "references/characters/odysseus.md".into(),
            line: 9,
        };

        // Add appends block-map form.
        edge_add(&mut lines, &fm, card.line, "Mentor", "serves");
        let text = lines.join("\n");
        assert!(text.contains("  - to: Mentor\n    kind: serves"));

        // Rename in place for flow and block forms.
        let fm = frontmatter(&lines).unwrap();
        edge_rename(&mut lines, &fm, "Penelope", "widow").unwrap();
        assert!(lines.join("\n").contains("{ to: Penelope, kind: widow }"));
        let fm = frontmatter(&lines).unwrap();
        edge_rename(&mut lines, &fm, "Telemachus", "guardian").unwrap();
        assert!(lines.join("\n").contains("    kind: guardian"));

        // Renaming a shorthand entry converts it to block-map form — the
        // documented exception.
        let fm = frontmatter(&lines).unwrap();
        edge_rename(&mut lines, &fm, "Poseidon", "enemy").unwrap();
        assert!(lines
            .join("\n")
            .contains("  - to: Poseidon\n    kind: enemy"));

        // Removal matches by `to` regardless of syntax.
        let fm = frontmatter(&lines).unwrap();
        assert!(edge_remove(&mut lines, &fm, "Mentor"));
        assert!(!lines.join("\n").contains("Mentor"));
    }

    #[test]
    fn apply_is_atomic_when_an_op_fails() {
        let (dir, paths) = write_project(&[("chapters/01.md", CHAPTER)]);
        let mut store = Store::new(&dir).unwrap();
        store.stage(Op::SetField {
            scene: SceneRef {
                file: "chapters/01.md".into(),
                line: 2,
            },
            key: "day".into(),
            value: Some("7".into()),
        });
        store.stage(Op::AddEdge {
            // A card file that does not exist: the transform pass fails
            // before any write lands.
            card: CardRef {
                file: "chapters/missing.md".into(),
                line: 0,
            },
            to: "Athena".into(),
            kind: "ally".into(),
        });
        let err = store.apply().unwrap_err();
        assert!(err.to_string().contains("missing.md") || err.to_string().contains("No such file"));
        // Nothing landed on disk.
        let after = fs::read_to_string(&paths[0].1).unwrap();
        assert_eq!(after, CHAPTER, "failed apply leaves files untouched");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn stale_guard_aborts_apply() {
        let (dir, _) = write_project(&[("chapters/01.md", CHAPTER)]);
        let mut store = Store::new(&dir).unwrap();
        // External edit behind the store's back.
        std::thread::sleep(std::time::Duration::from_millis(20));
        fs::write(
            dir.join("chapters/01.md"),
            format!("{CHAPTER}\n## Extra\nprose\n"),
        )
        .unwrap();
        store.stage(Op::SetField {
            scene: SceneRef {
                file: "chapters/01.md".into(),
                line: 2,
            },
            key: "day".into(),
            value: Some("7".into()),
        });
        let err = store.apply().unwrap_err();
        assert!(err.to_string().contains("R to reload"));
        assert_eq!(store.pending(), 1, "staging survives a stale abort");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn multi_file_apply_lands_everywhere() {
        let card = "---\nnames:\n  - Odysseus\nrelations:\n  - { to: Penelope, kind: spouse }\n---\n\n## Odysseus\n";
        let (dir, paths) = write_project(&[
            ("chapters/01.md", CHAPTER),
            ("references/characters/odysseus.md", card),
        ]);
        let mut store = Store::new(&dir).unwrap();
        store.stage(Op::SetField {
            scene: SceneRef {
                file: "chapters/01.md".into(),
                line: 2,
            },
            key: "day".into(),
            value: Some("8".into()),
        });
        store.stage(Op::AddEdge {
            card: CardRef {
                file: "references/characters/odysseus.md".into(),
                line: 6,
            },
            to: "Athena".into(),
            kind: "ally".into(),
        });
        assert_eq!(store.apply().unwrap(), 2);
        let chapter = fs::read_to_string(&paths[0].1).unwrap();
        let cardtext = fs::read_to_string(&paths[1].1).unwrap();
        assert!(chapter.contains("day: 8"));
        assert!(cardtext.contains("  - to: Athena\n    kind: ally"));
        fs::remove_dir_all(&dir).ok();
    }

    /// Golden parity: the JSON fixtures under tests/projections/ describe
    /// project files plus `set_field` ops; the Lua engine's frozen output is
    /// asserted byte-exact here too.
    #[test]
    fn matches_lua_golden_fixtures() {
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let dir = manifest.join("../tests/projections");
        let entries = match fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => return, // fixtures live in the plugin repo checkout
        };
        let mut checked = 0;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e != "json").unwrap_or(true) {
                continue;
            }
            let raw = fs::read_to_string(&path).unwrap();
            let fx: serde_json::Value = serde_json::from_str(&raw).unwrap();
            let name = fx["name"].as_str().unwrap_or("?").to_string();

            let tmp =
                std::env::temp_dir().join(format!("st-fixture-{}-{}", std::process::id(), name));
            if tmp.exists() {
                fs::remove_dir_all(&tmp).unwrap();
            }
            for (rel, content) in fx["files"].as_object().unwrap() {
                let full = tmp.join(rel);
                fs::create_dir_all(full.parent().unwrap()).unwrap();
                fs::write(full, content.as_str().unwrap()).unwrap();
            }

            let ops: Vec<Op> = fx["ops"]
                .as_array()
                .unwrap()
                .iter()
                .map(|o| {
                    assert_eq!(o["op"].as_str(), Some("set_field"), "fixture op kind");
                    let rel = o["rel"].as_str().unwrap().to_string();
                    let title = o["raw_title"].as_str().unwrap().to_string();
                    let file_lines = fs::read_to_string(tmp.join(&rel)).unwrap();
                    let line = file_lines
                        .lines()
                        .enumerate()
                        .find(|(_, l)| *l == format!("## {title}"))
                        .map(|(i, _)| i)
                        .unwrap_or_else(|| panic!("heading ## {title} not found"));
                    Op::SetField {
                        scene: SceneRef { file: rel, line },
                        key: o["key"].as_str().unwrap().to_string(),
                        value: o["value"].as_str().map(String::from),
                    }
                })
                .collect();

            let mut store = Store::new(&tmp).unwrap();
            for op in ops {
                store.stage(op);
            }
            store.apply().unwrap();

            for (rel, want) in fx["expect"].as_object().unwrap() {
                let got = fs::read_to_string(tmp.join(rel)).unwrap();
                // Fixture strings carry a trailing newline; atomic_write adds one.
                assert_eq!(
                    got.trim_end(),
                    want.as_str().unwrap().trim_end(),
                    "fixture {name}: {rel}"
                );
            }
            checked += 1;
            fs::remove_dir_all(&tmp).ok();
        }
        assert!(checked >= 3, "expected several fixtures, found {checked}");
    }
}
