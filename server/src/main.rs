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
        let pos = params.range.start;
        let lines = self.document_lines(&uri);
        let line = lines.get(pos.line as usize).cloned().unwrap_or_default();
        let byte = utf16_to_byte(&line, pos.character);
        let word = index::tokenize(&line)
            .into_iter()
            .find(|t| byte >= t.start && byte <= t.end)
            .map(|t| t.word);

        let word = match word {
            Some(w) => w,
            None => return Ok(None),
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
