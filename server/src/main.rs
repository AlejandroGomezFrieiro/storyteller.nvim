mod index;
mod meta;

use index::Index;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::RwLock;
use tower_lsp::jsonrpc::Result;
use tower_lsp::lsp_types::*;
use tower_lsp::{Client, LanguageServer, LspService, Server};

const SCHEMA_JSON: &str = include_str!("../schema.json");

#[derive(serde::Deserialize)]
struct Schema {
    statuses: Vec<String>,
    scene_fields: Vec<String>,
    chapter_fields: Vec<String>,
    #[serde(default)]
    reference_types: HashMap<String, RefType>,
}

#[derive(serde::Deserialize)]
struct RefType {
    #[allow(dead_code)]
    dir: String,
    label: String,
}

struct Backend {
    client: Client,
    index: RwLock<Index>,
    root: RwLock<Option<PathBuf>>,
    docs: RwLock<HashMap<String, String>>,
    schema: Schema,
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
        let schema: Schema = serde_json::from_str(SCHEMA_JSON).unwrap_or(Schema {
            statuses: vec![
                "outline".into(),
                "draft".into(),
                "revision".into(),
                "done".into(),
                "unused".into(),
            ],
            scene_fields: vec!["pov".into(), "location".into(), "status".into()],
            chapter_fields: vec!["status".into(), "target".into()],
            reference_types: HashMap::new(),
        });
        Self {
            client,
            index: RwLock::new(Index::default()),
            root: RwLock::new(None),
            docs: RwLock::new(HashMap::new()),
            schema,
        }
    }

    fn rescan(&self) {
        let root = self.root.read().unwrap().clone();
        if let Some(root) = root {
            let idx = index::scan(&root);
            *self.index.write().unwrap() = idx;
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
        let body = match rtype {
            "character" => "- **Role:** \n- **Notes:** ",
            "location" => "- **Atmosphere:** \n- **Notes:** ",
            "item" => "- **Type:** \n- **Notes:** ",
            _ => "- **Wants:** \n- **Members:** \n- **Notes:** ",
        };
        format!(
            "---\nnames:\n  - {name}\n---\n\n## {name}\n\n{body}\n",
            name = name,
            body = body
        )
    }

    fn card_uri(&self, rtype: &str, name: &str) -> Option<Url> {
        let root = self.root.read().unwrap().clone()?;
        let slug = name
            .to_lowercase()
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' { c } else { '-' })
            .collect::<String>();
        let dir = match rtype {
            "character" => "characters",
            "location" => "locations",
            "item" => "items",
            _ => "organizations",
        };
        Url::from_file_path(root.join("references").join(dir).join(format!("{slug}.md"))).ok()
    }

    // Publish story diagnostics for every chapter and reference card.
    async fn publish_diagnostics(&self) {
        let to_publish: Vec<(Url, Vec<Diagnostic>)> = {
            let idx = self.index.read().unwrap();
            let mut out = Vec::new();
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
                let mut diags = Vec::new();
                for (li, byte, word) in index::unknown_names(&idx, &text) {
                    let line = text.lines().nth(li).unwrap_or("");
                    let start = Position::new(li as u32, byte_to_utf16(line, byte));
                    let end = Position::new(li as u32, byte_to_utf16(line, byte + word.len()));
                    diags.push(Diagnostic {
                        range: Range::new(start, end),
                        severity: Some(DiagnosticSeverity::HINT),
                        source: Some("storyteller".into()),
                        message: format!("No reference card for “{word}” — run a code action to create one."),
                        ..Default::default()
                    });
                }
                out.push((uri, diags));
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
                        out.push((uri, vec![diag]));
                    }
                }
            }
            out
        };

        for (uri, diags) in to_publish {
            self.client.publish_diagnostics(uri, diags, None).await;
        }
    }

    // Is the line inside a YAML block (frontmatter or ```yaml)?
    fn in_yaml(&self, lines: &[String], line: usize) -> bool {
        let mut in_fm = false;
        let mut in_block = false;
        for (i, l) in lines.iter().enumerate() {
            let t = l.trim();
            if i > line {
                break;
            }
            if t == "---" && !in_block {
                in_fm = !in_fm;
                continue;
            }
            if t == "```yaml" {
                in_block = true;
                continue;
            }
            if t == "```" && in_block {
                in_block = false;
                continue;
            }
        }
        in_fm || in_block
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
    // Returns a WorkspaceEdit replacing the block if it isn't already linked.
    fn link_edit(&self, uri: &Url, position: Position, key: &str, item: &str) -> Option<WorkspaceEdit> {
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
        Some(WorkspaceEdit {
            changes: Some(
                [(uri.clone(), vec![TextEdit { range, new_text }])]
                    .into_iter()
                    .collect(),
            ),
            document_changes: None,
            change_annotations: None,
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
        self.rescan();

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
                completion_provider: Some(CompletionOptions {
                    resolve_provider: Some(false),
                    trigger_characters: Some(vec![]),
                    ..Default::default()
                }),
                code_action_provider: Some(CodeActionProviderCapability::Simple(true)),
                ..Default::default()
            },
        })
    }

    async fn initialized(&self, _params: InitializedParams) {
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
        self.rescan();
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
        self.rescan();
        self.publish_diagnostics().await;
    }

    async fn did_change_watched_files(&self, _params: DidChangeWatchedFilesParams) {
        self.rescan();
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

        if self.in_yaml(&lines, pos.line as usize) {
            // YAML context: field names + values for the field on the line.
            if let Some(field) = Self::field_on_line(&line) {
                match field.as_str() {
                    "status" => {
                        for status in &self.schema.statuses {
                            items.push(CompletionItem {
                                label: status.clone(),
                                kind: Some(CompletionItemKind::ENUM_MEMBER),
                                detail: Some("status".into()),
                                ..Default::default()
                            });
                        }
                    }
                    "pov" | "location" | "chars" | "locs" | "items" | "orgs" => {
                        self.name_items(&mut items);
                    }
                    _ => {}
                }
            }
            // Always offer field names.
            let mut seen = std::collections::HashSet::new();
            for field in self.schema.scene_fields.iter().chain(self.schema.chapter_fields.iter()) {
                if seen.insert(field) {
                    items.push(CompletionItem {
                        label: field.clone(),
                        kind: Some(CompletionItemKind::FIELD),
                        ..Default::default()
                    });
                }
            }
        } else {
            // Prose: suggest reference names.
            self.name_items(&mut items);
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
                    deprecated: None,
                    tags: None,
                });
            }
        }
        Ok(Some(DocumentSymbolResponse::Flat(symbols)))
    }

    async fn code_action(&self, params: CodeActionParams) -> Result<Option<CodeActionResponse>> {
        let uri = params.text_document.uri;

        // Prefer the full selection (visual mode may select a multi-word
        // name); fall back to the single word under the cursor.
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
                    None => return Ok(None),
                }
            }
        };
        if word.len() < 3 {
            return Ok(None);
        }

        let mut actions = Vec::new();
        let types = ["character", "location", "item", "organization"];
        for rtype in types {
            let Some(new_uri) = self.card_uri(rtype, &word) else {
                continue;
            };
            let label = self
                .schema
                .reference_types
                .get(rtype)
                .map(|t| t.label.clone())
                .unwrap_or_else(|| rtype.to_string());
            let content = self.card_content(rtype, &word);
            let edit = WorkspaceEdit {
                changes: None,
                document_changes: Some(DocumentChanges::Edits(vec![TextDocumentEdit {
                    text_document: OptionalVersionedTextDocumentIdentifier {
                        uri: new_uri,
                        version: None,
                    },
                    edits: vec![OneOf::Left(TextEdit {
                        range: Range::default(),
                        new_text: content,
                    })],
                }])),
                change_annotations: None,
            };
            actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                title: format!("Create {label} card for “{word}”"),
                kind: Some(CodeActionKind::QUICKFIX),
                edit: Some(edit),
                ..Default::default()
            }));
        }

        // If the mention resolves to an existing card, offer to link it into
        // the enclosing scene's metadata block.
        if let Some((entry, _, _)) = self.resolve_pos(&uri, params.range.start) {
            let field = match entry.rtype.as_str() {
                "characters" => "chars",
                "locations" => "locs",
                "items" => "items",
                _ => "orgs",
            };
            let title = format!("Link “{}” to this scene", entry.name);
            if let Some(edit) = self.link_edit(&uri, params.range.start, field, &entry.name) {
                actions.push(CodeActionOrCommand::CodeAction(CodeAction {
                    kind: Some(CodeActionKind::REFACTOR),
                    title,
                    edit: Some(edit),
                    ..Default::default()
                }));
            }
        }
        Ok(Some(actions))
    }
}

impl Backend {
    fn name_items(&self, items: &mut Vec<CompletionItem>) {
        let idx = self.index.read().unwrap();
        let mut seen = std::collections::HashSet::new();
        for card in &idx.cards {
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
