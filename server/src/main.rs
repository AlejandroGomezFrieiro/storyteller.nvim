mod cli;
mod commands;
mod compile;
mod diagnostics;
mod index;
mod meta;
mod schema;

use index::Index;
use schema::Schema;
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::RwLock;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer, LspService, Server};

struct Backend {
    client: Client,
    index: RwLock<Index>,
    root: RwLock<Option<PathBuf>>,
    docs: RwLock<HashMap<String, String>>,
    schema: RwLock<Schema>,
    init_schema: RwLock<Option<Value>>,
}

#[derive(PartialEq, Clone, Copy)]
enum BlockKind {
    Frontmatter,
    Scene,
    OtherYaml,
    Prose,
}

fn byte_to_utf16(line: &str, byte: usize) -> u32 {
    let byte = byte.min(line.len());
    let mut count = 0u32;
    for (i, c) in line.char_indices() {
        if i >= byte {
            break;
        }
        count += c.len_utf16() as u32;
    }
    count
}

impl Backend {
    fn new(client: Client) -> Self {
        Self {
            client,
            index: RwLock::new(Index::default()),
            root: RwLock::new(None),
            docs: RwLock::new(HashMap::new()),
            schema: RwLock::new(Schema::defaults()),
            init_schema: RwLock::new(None),
        }
    }

    fn rescan(&self) -> Vec<String> {
        let root = self.root.read().unwrap().clone();
        if let Some(root) = root {
            let init = self.init_schema.read().unwrap().clone();
            let (schema, warnings) = Schema::load(Some(&root), init.as_ref());
            *self.schema.write().unwrap() = schema;
            *self.index.write().unwrap() = index::scan(&root);
            return warnings;
        }
        Vec::new()
    }

    async fn log_warnings(&self, warnings: Vec<String>) {
        for w in warnings {
            self.client.log_message(MessageType::WARNING, w).await;
        }
    }

    fn document_lines(&self, uri: &Url) -> Vec<String> {
        let key = uri.as_str().to_string();
        if let Some(text) = self.docs.read().unwrap().get(&key) {
            return text.lines().map(|l| l.to_string()).collect();
        }
        if let Ok(path) = uri.to_file_path() {
            return std::fs::read_to_string(path)
                .map(|s| s.lines().map(|l| l.to_string()).collect())
                .unwrap_or_default();
        }
        Vec::new()
    }

    // Resolve the name under a position (byte range included). Returns
    // (entry, start_byte, end_byte).
    fn resolve_pos(&self, uri: &Url, position: Position) -> Option<(index::NameEntry, usize, usize)> {
        let lines = self.document_lines(uri);
        let line = lines.get(position.line as usize)?;
        let byte = utf16_to_byte(line, position.character);
        let idx = self.index.read().unwrap();
        let (entry, (start, end)) = index::resolve_at(&idx, line, byte)?;
        Some((entry.clone(), start, end))
    }

    // Extract the text covered by a range (a visual selection may span words
    // or lines). Returns the normalized name (whitespace collapsed to spaces).
    fn selection_text(&self, uri: &Url, range: Range) -> Option<String> {
        let lines = self.document_lines(uri);
        let start = range.start;
        let end = range.end;
        if lines.is_empty()
            || start.line as usize >= lines.len()
            || end.line as usize >= lines.len()
        {
            return None;
        }
        let mut out = String::new();
        if start.line == end.line {
            let line = &lines[start.line as usize];
            let s = utf16_to_byte(line, start.character);
            let e = utf16_to_byte(line, end.character);
            out.push_str(&line[s..e.min(line.len())]);
        } else {
            let first = &lines[start.line as usize];
            let s = utf16_to_byte(first, start.character).min(first.len());
            out.push_str(&first[s..]);
            for i in (start.line as usize + 1)..(end.line as usize) {
                out.push('\n');
                out.push_str(&lines[i]);
            }
            let last = &lines[end.line as usize];
            let e = utf16_to_byte(last, end.character).min(last.len());
            out.push('\n');
            out.push_str(&last[..e]);
        }
        let normalized: String = out.split_whitespace().collect::<Vec<_>>().join(" ");
        if normalized.is_empty() {
            None
        } else {
            Some(normalized)
        }
    }

    fn card_content(&self, rtype: &str, name: &str) -> String {
        let body = self
            .schema
            .read()
            .unwrap()
            .ref_type(rtype)
            .map(|t| t.body.clone())
            .unwrap_or_else(|| vec!["Notes".to_string()]);
        let bullets = body
            .iter()
            .map(|b| format!("- **{b}:** "))
            .collect::<Vec<_>>()
            .join("\n");
        format!(
            "---\nnames:\n  - {name}\n---\n\n## {name}\n\n{bullets}\n",
            name = name,
            bullets = bullets
        )
    }

    // Folder (rtype) -> scene-list field (chars/locs/items/orgs or the folder
    // itself for user-added codex types).
    fn type_field(&self, rtype: &str) -> String {
        self.schema
            .read()
            .unwrap()
            .ref_type(rtype)
            .map(|t| t.field.clone())
            .unwrap_or_else(|| rtype.to_string())
    }

    // Human label for a reference-type folder.
    fn type_label(&self, rtype: &str) -> String {
        if let Some(t) = self.schema.read().unwrap().ref_type(rtype) {
            return t.label.clone();
        }
        let s = rtype.replace(['_', '-'], " ");
        let mut it = s.chars();
        match it.next() {
            Some(c) => c.to_uppercase().collect::<String>() + it.as_str(),
            None => s,
        }
    }

    // All known type folders: schema-declared ones plus folders discovered on
    // disk (deduped, schema order first).
    fn type_dirs(&self) -> Vec<String> {
        let idx = self.index.read().unwrap();
        let schema = self.schema.read().unwrap();
        let mut out: Vec<String> = schema.reference_types.values().map(|t| t.dir.clone()).collect();
        for d in &idx.reference_dirs {
            if !out.contains(d) {
                out.push(d.clone());
            }
        }
        out
    }

    fn card_uri(&self, rtype: &str, name: &str) -> Option<Url> {
        let root = self.root.read().unwrap().clone()?;
        let slug = name
            .to_lowercase()
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' { c } else { '-' })
            .collect::<String>();
        // `rtype` is a folder name; the schema dir lookup is a no-op safety net
        // for the singular-id form, and codex folders fall through to themselves.
        let dir = self
            .schema
            .read()
            .unwrap()
            .dir_of(rtype)
            .map(String::from)
            .unwrap_or_else(|| rtype.to_string());
        Url::from_file_path(root.join("references").join(dir).join(format!("{slug}.md"))).ok()
    }

    // Publish story diagnostics for every chapter and reference card.
    async fn publish_diagnostics(&self) {
        let mut by_uri: HashMap<Url, Vec<Diagnostic>> = HashMap::new();
        {
            let idx = self.index.read().unwrap();
            let schema = self.schema.read().unwrap();
            for ch in &idx.chapters {
                let uri = match Url::from_file_path(&ch.path) {
                    Ok(u) => u,
                    Err(_) => continue,
                };
                let text = self
                    .docs
                    .read()
                    .unwrap()
                    .get(uri.as_str())
                    .cloned()
                    .unwrap_or_else(|| std::fs::read_to_string(&ch.path).unwrap_or_default());
                for (li, byte, word) in index::unknown_names(&idx, &text) {
                    let line = text.lines().nth(li).unwrap_or("");
                    let start = Position::new(li as u32, byte_to_utf16(line, byte));
                    let end = Position::new(li as u32, byte_to_utf16(line, byte + word.len()));
                    by_uri.entry(uri.clone()).or_default().push(Diagnostic {
                        range: Range::new(start, end),
                        severity: Some(DiagnosticSeverity::HINT),
                        source: Some("storyteller".into()),
                        message: format!("No reference card for “{word}” — run a code action to create one."),
                        ..Default::default()
                    });
                }
            }

            for card in &idx.cards {
                if index::mention_count(&idx, card) == 0 {
                    if let Ok(uri) = Url::from_file_path(&card.path) {
                        let diag = Diagnostic {
                            range: Range::new(Position::new(0, 0), Position::new(0, 0)),
                            severity: Some(DiagnosticSeverity::HINT),
                            source: Some("storyteller".into()),
                            message: format!("“{}” is never mentioned in the manuscript.", card.name),
                            ..Default::default()
                        };
                        by_uri.entry(uri).or_default().push(diag);
                    }
                }
            }

            for pd in diagnostics::project_diagnostics(&idx, &schema) {
                let Ok(uri) = Url::from_file_path(&pd.path) else {
                    continue;
                };
                let text = std::fs::read_to_string(&pd.path).unwrap_or_default();
                let line = text.lines().nth(pd.line as usize).unwrap_or("");
                let start_byte = pd.start_byte.min(line.len());
                let end_byte = pd.end_byte.min(line.len()).max(start_byte);
                let severity = match pd.severity {
                    diagnostics::Severity::Warning => DiagnosticSeverity::WARNING,
                    diagnostics::Severity::Hint => DiagnosticSeverity::HINT,
                };
                by_uri.entry(uri).or_default().push(Diagnostic {
                    range: Range::new(
                        Position::new(pd.line, byte_to_utf16(line, start_byte)),
                        Position::new(pd.line, byte_to_utf16(line, end_byte)),
                    ),
                    severity: Some(severity),
                    source: Some("storyteller".into()),
                    message: pd.message,
                    ..Default::default()
                });
            }
        }

        for (uri, diags) in by_uri {
            self.client.publish_diagnostics(uri, diags, None).await;
        }
    }

    // Is the line inside a YAML block (frontmatter or ```yaml)?
    // Which YAML/prose context a line sits in. Chapter frontmatter is between
    // the leading `---` pair; a Scene block is a ```yaml block whose first line
    // is the scene sentinel; OtherYaml is any other fenced YAML.
    fn block_kind(&self, lines: &[String], line: usize) -> BlockKind {
        let sentinel = self.schema.read().unwrap().scene_sentinel.clone();
        let mut in_fm = false;
        let mut in_block = false;
        let mut block_is_scene = false;
        for (i, l) in lines.iter().enumerate() {
            if i > line {
                break;
            }
            let t = l.trim();
            if t == "---" && !in_block {
                in_fm = !in_fm;
                continue;
            }
            if t == "```yaml" {
                in_block = true;
                block_is_scene = lines
                    .get(i + 1)
                    .map(|n| n.trim().eq_ignore_ascii_case(&sentinel))
                    .unwrap_or(false);
                continue;
            }
            if t == "```" && in_block {
                in_block = false;
                continue;
            }
        }
        if in_fm {
            BlockKind::Frontmatter
        } else if in_block {
            if block_is_scene {
                BlockKind::Scene
            } else {
                BlockKind::OtherYaml
            }
        } else {
            BlockKind::Prose
        }
    }

    fn field_on_line(line: &str) -> Option<String> {
        let t = line.trim_start();
        let colon = t.find(':')?;
        let key = t[..colon].trim();
        if key.is_empty() {
            return None;
        }
        Some(key.to_string())
    }

    // Link `item` into the scene metadata block containing `position`.
    // Returns the raw TextEdit replacing the block if it isn't already linked.
    fn link_text_edit(&self, uri: &Url, position: Position, key: &str, item: &str) -> Option<TextEdit> {
        let lines = self.document_lines(uri);
        let (yaml, end) = scene_block_indexes(&lines, position.line as usize)?;
        let open = &lines[yaml];
        let close = &lines[end];
        let inner = &lines[yaml + 1..end];
        if block_contains(inner, key, item) {
            return None;
        }
        let new_inner = add_list_item(inner, key, item);
        let close_chars = byte_to_utf16(close, close.len());
        let range = Range::new(Position::new(yaml as u32, 0), Position::new(end as u32, close_chars));
        let new_text = format!("{open}\n{}\n{close}", new_inner.join("\n"));
        Some(TextEdit { range, new_text })
    }

    fn link_edit(&self, uri: &Url, position: Position, key: &str, item: &str) -> Option<WorkspaceEdit> {
        let edit = self.link_text_edit(uri, position, key, item)?;
        Some(WorkspaceEdit {
            changes: Some([(uri.clone(), vec![edit])].into_iter().collect()),
            document_changes: None,
            change_annotations: None,
        })
    }

    // Replace the value of `field:` in the scene block containing `position`.
    // Returns (old_value, TextEdit) when the field is present.
    fn field_value_edit(
        &self,
        lines: &[String],
        position: Position,
        field: &str,
        new_value: &str,
    ) -> Option<(String, TextEdit)> {
        let (yaml, end) = scene_block_indexes(lines, position.line as usize)?;
        let li = (yaml + 1..end).find(|&i| {
            let t = lines[i].trim_start();
            t == field || t.starts_with(&format!("{field}:"))
        })?;
        let line = &lines[li];
        let t = line.trim_start();
        let indent = line.len() - t.len();
        let colon = t.find(':')?;
        let rest = &t[colon + 1..];
        let value = rest.trim().to_string();
        if value.is_empty() {
            return None;
        }
        let lead = rest.len() - rest.trim_start().len();
        let value_start = indent + colon + 1 + lead;
        let value_end = value_start + value.len();
        let range = Range::new(
            Position::new(li as u32, byte_to_utf16(line, value_start)),
            Position::new(li as u32, byte_to_utf16(line, value_end)),
        );
        Some((value, TextEdit { range, new_text: new_value.to_string() }))
    }

    // Insert a scalar field as the last line of the scene block.
    fn insert_field_edit(
        &self,
        lines: &[String],
        position: Position,
        field: &str,
        value: &str,
    ) -> Option<TextEdit> {
        let (_, end) = scene_block_indexes(lines, position.line as usize)?;
        let close = &lines[end];
        let close_chars = byte_to_utf16(close, close.len());
        let new_text = format!("{field}: {value}\n{close}");
        Some(TextEdit {
            range: Range::new(Position::new(end as u32, 0), Position::new(end as u32, close_chars)),
            new_text,
        })
    }

    // Insert a fresh scene YAML block directly under the `## ` heading above
    // `position` (only when that heading has no scene block yet).
    fn promote_scene_edit(&self, lines: &[String], position: Position) -> Option<TextEdit> {
        if scene_block_indexes(lines, position.line as usize).is_some() {
            return None;
        }
        let heading = (0..=position.line as usize)
            .rev()
            .find(|&i| lines[i].trim_start().starts_with("## "))?;
        let block = "```yaml\nstoryteller: scene\n```\n\n";
        Some(TextEdit {
            range: Range::new(Position::new((heading + 1) as u32, 0), Position::new((heading + 1) as u32, 0)),
            new_text: block.to_string(),
        })
    }
}

fn utf16_to_byte(line: &str, character: u32) -> usize {
    let mut u = 0u32;
    for (i, c) in line.char_indices() {
        if u >= character {
            return i;
        }
        u += c.len_utf16() as u32;
    }
    line.len()
}

// Find the ```yaml .. ``` block of the scene containing `line`. Returns
// (yaml_line, closing_fence_line) or None.
fn scene_block_indexes(lines: &[String], line: usize) -> Option<(usize, usize)> {
    let mut start = None;
    for i in (0..=line).rev() {
        if lines[i].trim_start().starts_with("## ") || lines[i].trim_start().starts_with("# ") {
            start = Some(i);
            break;
        }
    }
    let start = start?;
    let mut yaml = None;
    for i in (start + 1)..lines.len() {
        if i > line {
            break; // looking back up to the cursor only
        }
        if lines[i].trim() == "```yaml" {
            yaml = Some(i);
        }
    }
    let yaml = yaml?;
    let mut end = None;
    for i in (yaml + 1)..lines.len() {
        if lines[i].trim() == "```" {
            end = Some(i);
            break;
        }
        if lines[i].trim_start().starts_with("## ") {
            break; // unclosed block: bail
        }
    }
    let end = end?;
    if !lines[yaml + 1].trim().eq_ignore_ascii_case("storyteller: scene") {
        return None;
    }
    Some((yaml, end))
}

// Does a YAML block already list `item` under `key` (as `- item` or `[a, b]`)?
fn block_contains(block: &[String], key: &str, item: &str) -> bool {
    for (i, l) in block.iter().enumerate() {
        let t = l.trim();
        let is_key = t == key || (t.trim_end_matches(':') == key);
        if !is_key {
            continue;
        }
        if t.contains('[') && t.to_lowercase().contains(&item.to_lowercase()) {
            return true;
        }
        let mut j = i + 1;
        while j < block.len() && block[j].trim_start().starts_with("- ") {
            let val = block[j].trim().trim_start_matches("- ").trim();
            if val.eq_ignore_ascii_case(item) {
                return true;
            }
            j += 1;
        }
    }
    false
}

// Does a YAML block declare `key` at all (as `key:` or `key: value`)?
fn block_has_field(block: &[String], key: &str) -> bool {
    block.iter().any(|l| {
        let t = l.trim();
        t == key || t.trim_end_matches(':') == key
    })
}

// Add an item to a `key:` list in a YAML block (creating the key if absent).
fn add_list_item(block: &[String], key: &str, item: &str) -> Vec<String> {
    let mut out = block.to_vec();
    let mut ki = None;
    for (i, l) in out.iter().enumerate() {
        let t = l.trim();
        if t == key || t.trim_end_matches(':') == key {
            ki = Some(i);
            break;
        }
    }
    if let Some(i) = ki {
        // dedupe against existing `- item` entries
        let mut j = i + 1;
        while j < out.len() && out[j].trim_start().starts_with("- ") {
            if out[j].trim().trim_start_matches("- ").trim().eq_ignore_ascii_case(item) {
                return out;
            }
            j += 1;
        }
        out.insert(j, format!("  - {item}"));
    } else {
        out.push(format!("{key}:"));
        out.push(format!("  - {item}"));
    }
    out
}

#[tower_lsp::async_trait]
impl LanguageServer for Backend {
    async fn initialize(&self, params: InitializeParams) -> Result<InitializeResult> {
        if let Some(root_uri) = params.root_uri {
            if let Ok(path) = root_uri.to_file_path() {
                *self.root.write().unwrap() = Some(path);
            }
        }
        if let Some(opts) = params.initialization_options {
            if let Some(schema_val) = opts.get("schema") {
                *self.init_schema.write().unwrap() = Some(schema_val.clone());
            }
        }
        let warnings = self.rescan();
        self.log_warnings(warnings).await;

        Ok(InitializeResult {
            server_info: Some(ServerInfo {
                name: "storyteller".into(),
                version: Some(env!("CARGO_PKG_VERSION").into()),
            }),
            capabilities: ServerCapabilities {
                text_document_sync: Some(TextDocumentSyncCapability::Options(
                    TextDocumentSyncOptions {
                        open_close: Some(true),
                        change: Some(TextDocumentSyncKind::FULL),
                        save: Some(TextDocumentSyncSaveOptions::Supported(true)),
                        ..Default::default()
                    },
                )),
                hover_provider: Some(HoverProviderCapability::Simple(true)),
                definition_provider: Some(OneOf::Left(true)),
                references_provider: Some(OneOf::Left(true)),
                rename_provider: Some(OneOf::Left(true)),
                document_symbol_provider: Some(OneOf::Left(true)),
                document_highlight_provider: Some(OneOf::Left(true)),
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(false),
                    trigger_characters: Some(vec![]),
                    ..Default::default()
                }),
                code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
                execute_command_provider: Some(ExecuteCommandOptions {
                    commands: [
                        "storyteller.link",
                        "storyteller.createCard",
                        "storyteller.compile",
                        "storyteller.manuscript",
                        "storyteller.detect",
                        "storyteller.statusCycle",
                    ]
                    .into_iter()
                    .map(Into::into)
                    .collect(),
                    work_done_progress_options: Default::default(),
                }),
                ..Default::default()
            },
        })
    }

    async fn initialized(&self, _params: InitializedParams) {
        let watchers = [
            ".storyteller/schema.json",
            "storyteller.schema.json",
            ".storyteller.toml",
            "references/**",
            "chapters/**",
        ]
        .iter()
        .map(|g| FileSystemWatcher {
            glob_pattern: GlobPattern::String(g.to_string()),
            kind: Some(WatchKind::Create | WatchKind::Change | WatchKind::Delete),
        })
        .collect::<Vec<_>>();
        let registration = Registration {
            id: "storyteller-watch".into(),
            method: "workspace/didChangeWatchedFiles".into(),
            register_options: Some(
                serde_json::to_value(DidChangeWatchedFilesRegistrationOptions { watchers }).unwrap(),
            ),
        };
        let _ = self.client.register_capability(vec![registration]).await;
        self.publish_diagnostics().await;
    }

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let uri = params.text_document.uri;
        self.docs
            .write()
            .unwrap()
            .insert(uri.as_str().to_string(), params.text_document.text);
        let warnings = self.rescan();
        self.log_warnings(warnings).await;
        self.publish_diagnostics().await;
    }

    async fn did_change(&self, params: DidChangeTextDocumentParams) {
        if let Some(change) = params.content_changes.into_iter().last() {
            self.docs
                .write()
                .unwrap()
                .insert(params.text_document.uri.as_str().to_string(), change.text);
        }
    }

    async fn did_save(&self, _params: DidSaveTextDocumentParams) {
        let warnings = self.rescan();
        self.log_warnings(warnings).await;
        self.publish_diagnostics().await;
    }

    async fn did_change_watched_files(&self, _params: DidChangeWatchedFilesParams) {
        let warnings = self.rescan();
        self.log_warnings(warnings).await;
        self.publish_diagnostics().await;
    }

    async fn hover(&self, params: HoverParams) -> Result<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        let (entry, start, end) = match self.resolve_pos(&uri, pos) {
            Some(r) => r,
            None => return Ok(None),
        };
        let line = self.document_lines(&uri).get(pos.line as usize).cloned().unwrap_or_default();

        let mut parts = vec![format!("**{}** — {}", entry.name, entry.rtype)];
        let idx = self.index.read().unwrap();
        if let Some(card) = idx.cards.iter().find(|c| c.path == entry.path) {
            for s in &card.summary {
                parts.push(s.clone());
            }
        }
        let range = Range::new(
            Position::new(pos.line, byte_to_utf16(&line, start)),
            Position::new(pos.line, byte_to_utf16(&line, end)),
        );
        Ok(Some(Hover {
            contents: HoverContents::Markup(MarkupContent {
                kind: MarkupKind::Markdown,
                value: parts.join("\n\n"),
            }),
            range: Some(range),
        }))
    }

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        let (entry, _, _) = match self.resolve_pos(&uri, pos) {
            Some(r) => r,
            None => return Ok(None),
        };
        let target = Url::from_file_path(&entry.path).ok();
        Ok(target.map(|u| GotoDefinitionResponse::Scalar(Location {
            uri: u,
            range: Range::default(),
        })))
    }

    async fn references(&self, params: ReferenceParams) -> Result<Option<Vec<Location>>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        let (entry, _, _) = match self.resolve_pos(&uri, pos) {
            Some(r) => r,
            None => return Ok(None),
        };

        let idx = self.index.read().unwrap();
        // Match the whole alias set, not just the primary name.
        let card = idx.cards.iter().find(|c| c.path == entry.path);
        let aliases: Vec<String> = card
            .map(|c| c.aliases.iter().map(|a| a.to_lowercase()).collect())
            .unwrap_or_else(|| vec![entry.name.to_lowercase()]);
        let alias_set: std::collections::HashSet<&String> = aliases.iter().collect();

        let mut locations = Vec::new();
        for chapter in &idx.chapters {
            if let Ok(text) = std::fs::read_to_string(&chapter.path) {
                for (i, l) in text.lines().enumerate() {
                    for t in index::tokenize(l) {
                        if alias_set.contains(&t.word.to_lowercase()) {
                            locations.push(Location {
                                uri: Url::from_file_path(&chapter.path).unwrap_or_else(|_| uri.clone()),
                                range: Range::new(
                                    Position::new(i as u32, byte_to_utf16(l, t.start)),
                                    Position::new(i as u32, byte_to_utf16(l, t.end)),
                                ),
                            });
                        }
                    }
                }
            }
        }
        Ok(Some(locations))
    }

    async fn rename(&self, params: RenameParams) -> Result<Option<WorkspaceEdit>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        let (entry, _, _) = match self.resolve_pos(&uri, pos) {
            Some(r) => r,
            None => return Ok(None),
        };
        let new_name = params.new_name.trim();
        if new_name.is_empty() || new_name == entry.name {
            return Ok(None);
        }

        let idx = self.index.read().unwrap();
        let mut changes: HashMap<Url, Vec<TextEdit>> = HashMap::new();
        let mut files: Vec<PathBuf> = vec![entry.path.clone()];
        for ch in &idx.chapters {
            files.push(ch.path.clone());
        }
        for file in files {
            if let Ok(text) = std::fs::read_to_string(&file) {
                let replaced = text.replace(&entry.name, new_name);
                if replaced != text {
                    let line_count = text.lines().count() as u32;
                    let end = Position::new(line_count.saturating_sub(1), 0);
                    if let Ok(u) = Url::from_file_path(&file) {
                        changes.entry(u).or_default().push(TextEdit {
                            range: Range::new(Position::new(0, 0), end),
                            new_text: replaced,
                        });
                    }
                }
            }
        }
        if changes.is_empty() {
            return Ok(None);
        }
        Ok(Some(WorkspaceEdit {
            changes: Some(changes),
            document_changes: None,
            change_annotations: None,
        }))
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let uri = params.text_document_position.text_document.uri;
        let pos = params.text_document_position.position;
        let lines = self.document_lines(&uri);
        let line = lines.get(pos.line as usize).cloned().unwrap_or_default();

        let mut items: Vec<CompletionItem> = Vec::new();

        match self.block_kind(&lines, pos.line as usize) {
            BlockKind::Prose => self.name_items(&mut items),
            kind => {
                let schema = self.schema.read().unwrap();
                let idx = self.index.read().unwrap();
                if let Some(field) = Self::field_on_line(&line) {
                    if field == "tags" {
                        for t in index::tag_values(&idx) {
                            items.push(CompletionItem {
                                label: t,
                                kind: Some(CompletionItemKind::ENUM_MEMBER),
                                detail: Some("tag".into()),
                                ..Default::default()
                            });
                        }
                    } else {
                        let defs = match kind {
                            BlockKind::Frontmatter => &schema.chapter_field_defs,
                            _ => &schema.scene_field_defs,
                        };
                        if let Some(def) = defs.get(&field) {
                            match def.kind.as_str() {
                                "enum" => {
                                    for v in schema.enum_values(def.from.as_deref().unwrap_or("statuses")) {
                                        items.push(CompletionItem {
                                            label: v,
                                            kind: Some(CompletionItemKind::ENUM_MEMBER),
                                            detail: Some(field.clone()),
                                            ..Default::default()
                                        });
                                    }
                                }
                                "reference" | "reference-list" => {
                                    if let Some(dir) = def.ref_type.as_deref().and_then(|t| schema.dir_of(t)) {
                                        self.push_names_of_type(&mut items, &idx, Some(dir));
                                    }
                                }
                                "thread-key" => {
                                    for k in index::thread_keys(&idx) {
                                        items.push(CompletionItem {
                                            label: k,
                                            kind: Some(CompletionItemKind::TEXT),
                                            detail: Some("thread".into()),
                                            ..Default::default()
                                        });
                                    }
                                }
                                _ => {}
                            }
                        } else if schema.is_list(&field) || idx.reference_dirs.contains(&field) {
                            // Codex-style list fields named after their folder
                            // (e.g. `creatures:` from references/creatures).
                            self.push_names_of_type(&mut items, &idx, Some(&field));
                        }
                    }
                }
                // Always offer field names for this block kind.
                let mut seen = std::collections::HashSet::new();
                let fields = match kind {
                    BlockKind::Frontmatter => &schema.chapter_fields,
                    _ => &schema.scene_fields,
                };
                for field in fields {
                    if seen.insert(field) {
                        items.push(CompletionItem {
                            label: field.clone(),
                            kind: Some(CompletionItemKind::FIELD),
                            ..Default::default()
                        });
                    }
                }
            }
        }

        Ok(Some(CompletionResponse::Array(items)))
    }

    async fn document_symbol(
        &self,
        params: DocumentSymbolParams,
    ) -> Result<Option<DocumentSymbolResponse>> {
        let lines = self.document_lines(&params.text_document.uri);
        let mut symbols = Vec::new();
        let mut chapter_name: Option<String> = None;
        for (i, l) in lines.iter().enumerate() {
            if let Some(h1) = l.strip_prefix("# ") {
                chapter_name = Some(h1.trim().to_string());
            } else if let Some(h2) = l.strip_prefix("## ") {
                symbols.push(SymbolInformation {
                    name: h2.trim().to_string(),
                    kind: SymbolKind::KEY,
                    location: Location {
                        uri: params.text_document.uri.clone(),
                        range: Range::new(Position::new(i as u32, 0), Position::new(i as u32, l.len() as u32)),
                    },
                    container_name: chapter_name.clone(),
                    #[allow(deprecated)]
                    deprecated: None,
                    tags: None,
                });
            }
        }
        Ok(Some(DocumentSymbolResponse::Flat(symbols)))
    }

    async fn code_action(&self, params: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;
        let mut actions: Vec<CodeActionOrCommand> = Vec::new();

        // Structural actions (no selection word needed).
        self.scene_actions(&uri, params.range.start, &mut actions);

        // Card actions (need a selection / cursor word).
        let word = match self.selection_text(&uri, params.range) {
            Some(t) => t,
            None => {
                let pos = params.range.start;
                let lines = self.document_lines(&uri);
                let line = lines.get(pos.line as usize).cloned().unwrap_or_default();
                let byte = utf16_to_byte(&line, pos.character);
                match index::tokenize(&line)
                    .into_iter()
                    .find(|t| byte >= t.start && byte <= t.end)
                    .map(|t| t.word)
                {
                    Some(w) => w,
                    None => String::new(),
                }
            }
        };
        if word.len() >= 3 {
            self.card_actions(&uri, &word, params.range.start, &mut actions);
        }

        if actions.is_empty() {
            Ok(None)
        } else {
            Ok(Some(actions))
        }
    }

    async fn execute_command(&self, params: ExecuteCommandParams) -> Result<Option<Value>> {
        Ok(Some(self.run_command(params.command.as_str(), &params.arguments)))
    }

    async fn document_highlight(
        &self,
        params: DocumentHighlightParams,
    ) -> Result<Option<Vec<DocumentHighlight>>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        let Some((entry, _, _)) = self.resolve_pos(&uri, pos) else {
            return Ok(None);
        };
        let idx = self.index.read().unwrap();
        let card = idx.cards.iter().find(|c| c.path == entry.path);
        let aliases: Vec<String> = card
            .map(|c| c.aliases.iter().map(|a| a.to_lowercase()).collect())
            .unwrap_or_else(|| vec![entry.name.to_lowercase()]);
        let alias_set: std::collections::HashSet<&String> = aliases.iter().collect();

        let mut out = Vec::new();
        for (i, l) in self.document_lines(&uri).iter().enumerate() {
            for t in index::tokenize(l) {
                if alias_set.contains(&t.word.to_lowercase()) {
                    out.push(DocumentHighlight {
                        range: Range::new(
                            Position::new(i as u32, byte_to_utf16(l, t.start)),
                            Position::new(i as u32, byte_to_utf16(l, t.end)),
                        ),
                        kind: Some(DocumentHighlightKind::TEXT),
                    });
                }
            }
        }
        Ok(Some(out))
    }

}

impl Backend {
    fn scene_actions(&self, uri: &Url, position: Position, actions: &mut Vec<CodeActionOrCommand>) {
        let lines = self.document_lines(uri);
        let schema = self.schema.read().unwrap();

        // Cycle status.
        if let Some((current, _)) = self.field_value_edit(&lines, position, "status", "") {
            let next = schema.next_status(&current);
            if next != current {
                if let Some((_, edit)) = self.field_value_edit(&lines, position, "status", &next) {
                    actions.push(refactor_action(uri.clone(), format!("Cycle status: {current} → {next}"), edit));
                }
            }
        }

        if let Some((yaml, end)) = scene_block_indexes(&lines, position.line as usize) {
            let inner = &lines[yaml + 1..end];
            let threads = index::thread_keys(&self.index.read().unwrap());
            if !block_has_field(inner, "setup") {
                for key in &threads {
                    if let Some(edit) = self.insert_field_edit(&lines, position, "setup", key) {
                        actions.push(refactor_action(uri.clone(), format!("Add setup: {key}"), edit));
                    }
                }
            }
            if !block_has_field(inner, "payoff") {
                for key in &threads {
                    if let Some(edit) = self.insert_field_edit(&lines, position, "payoff", key) {
                        actions.push(refactor_action(uri.clone(), format!("Add payoff: {key}"), edit));
                    }
                }
            }
        } else if let Some(edit) = self.promote_scene_edit(&lines, position) {
            actions.push(refactor_action(uri.clone(), "Promote section to scene".into(), edit));
        }
    }

    fn card_actions(&self, uri: &Url, word: &str, position: Position, actions: &mut Vec<CodeActionOrCommand>) {
        for rtype in self.type_dirs() {
            let Some(new_uri) = self.card_uri(&rtype, word) else {
                continue;
            };
            let label = self.type_label(&rtype);
            let content = self.card_content(&rtype, word);
            let field = self.type_field(&rtype);
            let mut tdes = vec![TextDocumentEdit {
                text_document: OptionalVersionedTextDocumentIdentifier {
                    uri: new_uri,
                    version: None,
                },
                edits: vec![OneOf::Left(TextEdit {
                    range: Range::default(),
                    new_text: content,
                })],
            }];
            let mut linked = false;
            if let Some(link) = self.link_text_edit(uri, position, &field, word) {
                tdes.push(TextDocumentEdit {
                    text_document: OptionalVersionedTextDocumentIdentifier {
                        uri: uri.clone(),
                        version: None,
                    },
                    edits: vec![OneOf::Left(link)],
                });
                linked = true;
            }
            actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                title: if linked {
                    format!("Create {label} card for “{word}” and link to this scene")
                } else {
                    format!("Create {label} card for “{word}”")
                },
                kind: Some(CodeActionKind::QUICKFIX),
                edit: Some(WorkspaceEdit {
                    changes: None,
                    document_changes: Some(DocumentChanges::Edits(tdes)),
                    change_annotations: None,
                }),
                ..Default::default()
            }));
        }

        // If the mention resolves to an existing card, offer to link it into
        // the enclosing scene's metadata block.
        if let Some((entry, _, _)) = self.resolve_pos(uri, position) {
            let field = self.type_field(&entry.rtype);
            let title = format!("Link “{}” to this scene", entry.name);
            if let Some(edit) = self.link_edit(uri, position, &field, &entry.name) {
                actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                    kind: Some(CodeActionKind::REFACTOR),
                    title,
                    edit: Some(edit),
                    ..Default::default()
                }));
            }
        }
    }

    fn run_command(&self, command: &str, args: &[Value]) -> Value {
        match command {
            "storyteller.createCard" => {
                let name = args.get(0).and_then(|v| v.as_str()).unwrap_or("");
                let rtype = args.get(1).and_then(|v| v.as_str()).unwrap_or("");
                if name.is_empty() || rtype.is_empty() {
                    return serde_json::json!({ "ok": false, "error": "createCard requires {name, type}" });
                }
                let uri = self.card_uri(rtype, name);
                let content = self.card_content(rtype, name);
                serde_json::json!({ "ok": true, "name": name, "type": rtype, "uri": uri.map(|u| u.to_string()), "content": content })
            }
            "storyteller.compile" => {
                let idx = self.index.read().unwrap();
                serde_json::json!({ "ok": true, "text": compile::manuscript_text(&idx, false) })
            }
            "storyteller.manuscript" => {
                let idx = self.index.read().unwrap();
                serde_json::json!({ "ok": true, "text": compile::manuscript_text(&idx, true) })
            }
            "storyteller.detect" => {
                let idx = self.index.read().unwrap();
                serde_json::json!({ "ok": true, "suggestions": commands::detect_suggestions(&idx) })
            }
            "storyteller.statusCycle" => self.status_cycle(args),
            "storyteller.link" => self.link_command(args),
            _ => serde_json::json!({ "ok": false, "error": format!("unknown command: {command}") }),
        }
    }

    fn status_cycle(&self, args: &[Value]) -> Value {
        let path = args.get(0).and_then(|v| v.as_str()).unwrap_or("");
        let line = args.get(1).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let Some(uri) = Url::from_file_path(path).ok() else {
            return serde_json::json!({ "ok": false, "error": "bad path" });
        };
        let lines = self.document_lines(&uri);
        let pos = Position::new(line, 0);
        let next = {
            let schema = self.schema.read().unwrap();
            self.field_value_edit(&lines, pos, "status", "")
                .map(|(current, _)| schema.next_status(&current))
        };
        let Some(next) = next else {
            return serde_json::json!({ "ok": false, "error": "no status field to cycle" });
        };
        let Some((current, edit)) = self.field_value_edit(&lines, pos, "status", &next) else {
            return serde_json::json!({ "ok": false, "error": "no status field to cycle" });
        };
        if current == next {
            return serde_json::json!({ "ok": false, "error": "status already at end" });
        }
        let we = WorkspaceEdit {
            changes: Some([(uri, vec![edit])].into_iter().collect()),
            document_changes: None,
            change_annotations: None,
        };
        serde_json::json!({ "ok": true, "old": current, "new": next, "edit": serde_json::to_value(we).ok() })
    }

    fn link_command(&self, args: &[Value]) -> Value {
        let name = args.get(0).and_then(|v| v.as_str()).unwrap_or("");
        let rtype = args.get(1).and_then(|v| v.as_str()).unwrap_or("");
        let path = args.get(2).and_then(|v| v.as_str()).unwrap_or("");
        let line = args.get(3).and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        if path.is_empty() || name.is_empty() {
            return serde_json::json!({ "ok": false, "error": "link requires {name, type, path, line}" });
        }
        let Some(uri) = Url::from_file_path(path).ok() else {
            return serde_json::json!({ "ok": false });
        };
        let field = self.type_field(rtype);
        let pos = Position::new(line, 0);
        if let Some(edit) = self.link_text_edit(&uri, pos, &field, name) {
            let we = WorkspaceEdit {
                changes: Some([(uri, vec![edit])].into_iter().collect()),
                document_changes: None,
                change_annotations: None,
            };
            return serde_json::json!({ "ok": true, "edit": serde_json::to_value(we).ok() });
        }
        serde_json::json!({ "ok": false, "error": "already linked or no scene" })
    }
}

fn refactor_action(uri: Url, title: String, edit: TextEdit) -> CodeActionOrCommand {
    CodeActionOrCommand::CodeAction(CodeAction {
        title,
        kind: Some(CodeActionKind::REFACTOR),
        edit: Some(WorkspaceEdit {
            changes: Some([(uri, vec![edit])].into_iter().collect()),
            document_changes: None,
            change_annotations: None,
        }),
        ..Default::default()
    })
}

impl Backend {
    fn name_items(&self, items: &mut Vec<CompletionItem>) {
        let idx = self.index.read().unwrap();
        self.push_names_of_type(items, &idx, None);
    }

    // Offer card names, optionally filtered to a single type folder.
    fn push_names_of_type(&self, items: &mut Vec<CompletionItem>, idx: &Index, dir: Option<&str>) {
        let mut seen = std::collections::HashSet::new();
        for card in &idx.cards {
            if let Some(d) = dir {
                if card.rtype != d {
                    continue;
                }
            }
            for name in card.aliases.iter().chain(std::iter::once(&card.name)) {
                let key = name.to_lowercase();
                if seen.insert(key) {
                    items.push(CompletionItem {
                        label: name.clone(),
                        kind: Some(CompletionItemKind::REFERENCE),
                        detail: Some(card.rtype.clone()),
                        ..Default::default()
                    });
                }
            }
        }
    }
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if let Some(cmd) = args.get(1).map(|s| s.as_str()) {
        if matches!(cmd, "report" | "check" | "index" | "completions" | "version" | "help") {
            std::process::exit(cli::run(&args[1..]));
        }
    }
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();
    let (service, socket) = LspService::new(Backend::new);
    Server::new(stdin, stdout, socket).serve(service).await;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scene_doc() -> Vec<String> {
        "# Chapter 1\n\n## Scene 1\n\n```yaml\nstoryteller: scene\npov: Odysseus\nstatus: draft\n```\n\nOdysseus here.".lines().map(String::from).collect()
    }

    #[test]
    fn finds_scene_block_around_cursor() {
        let lines = scene_doc();
        let (yaml, end) = scene_block_indexes(&lines, 9).unwrap();
        assert_eq!(lines[yaml], "```yaml");
        assert_eq!(lines[end], "```");
        assert_eq!(yaml, 4);
        assert_eq!(end, 8);
    }

    #[test]
    fn blocks_without_scene_are_skipped() {
        let lines = "```yaml\nfoo: 1\n```".lines().map(String::from).collect::<Vec<_>>();
        assert_eq!(scene_block_indexes(&lines, 0), None);
    }

    #[test]
    fn adds_list_item_to_existing_key() {
        let block = vec!["status: draft".to_string(), "chars:".to_string(), "  - A".to_string()];
        let out = add_list_item(&block, "chars", "B");
        assert!(block_contains(&out, "chars", "A"));
        assert!(block_contains(&out, "chars", "B"));
        assert_eq!(out[2], "  - A");
        assert_eq!(out[3], "  - B");
    }

    #[test]
    fn adds_list_item_when_key_absent() {
        let block = vec!["status: draft".to_string()];
        let out = add_list_item(&block, "chars", "Odysseus");
        assert_eq!(out, vec!["status: draft", "chars:", "  - Odysseus"]);
        assert!(block_contains(&out, "chars", "odysseus"));
    }

    #[test]
    fn add_is_idempotent() {
        let block = add_list_item(&add_list_item(&["chars:".to_string()], "chars", "A"), "chars", "A");
        let items: Vec<&str> = block[1..].iter().map(|l| l.trim()).collect();
        assert_eq!(items, vec!["- A"]);
    }
}
