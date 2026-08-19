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

    fn root_uri(&self) -> Option<Url> {
        self.root
            .read()
            .unwrap()
            .as_ref()
            .and_then(|p| Url::from_file_path(p).ok())
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

    fn word_at_utf16(&self, line: &str, character: u32) -> Option<String> {
        let chars: Vec<char> = line.chars().collect();
        if chars.is_empty() {
            return None;
        }
        // Map a UTF-16 column to a char index (the char at/after that offset).
        let mut u = 0usize;
        let mut idx = chars.len();
        for (i, c) in chars.iter().enumerate() {
            if character as usize <= u {
                idx = i;
                break;
            }
            u += c.len_utf16();
        }
        let mut pos = idx.min(chars.len().saturating_sub(1));
        let is_word = |c: char| c.is_alphanumeric() || c == '\'';
        while pos > 0 && !is_word(chars[pos]) {
            pos -= 1;
        }
        if !is_word(chars[pos]) {
            return None;
        }
        let mut start = pos;
        let mut end = pos;
        while start > 0 && is_word(chars[start - 1]) {
            start -= 1;
        }
        while end + 1 < chars.len() && is_word(chars[end + 1]) {
            end += 1;
        }
        Some(chars[start..=end].iter().collect())
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

    async fn shutdown(&self) -> Result<()> {
        Ok(())
    }

    async fn did_open(&self, params: DidOpenTextDocumentParams) {
        let uri = params.text_document.uri;
        self.docs
            .write()
            .unwrap()
            .insert(uri.as_str().to_string(), params.text_document.text);
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
    }

    async fn hover(&self, params: HoverParams) -> Result<Option<Hover>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        let lines = self.document_lines(&uri);
        let line = lines.get(pos.line as usize).cloned().unwrap_or_default();
        let word = match self.word_at_utf16(&line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };

        let entries = {
            let idx = self.index.read().unwrap();
            index::resolve(&idx, &word)
        };
        let entry = match entries.into_iter().max_by(|a, b| {
            a.confidence.partial_cmp(&b.confidence).unwrap()
        }) {
            Some(e) => e,
            None => return Ok(None),
        };

        let mut parts = vec![format!("**{}** — {}", entry.name, entry.rtype)];
        let idx = self.index.read().unwrap();
        if let Some(card) = idx
            .cards
            .iter()
            .find(|c| c.path == entry.path)
        {
            for s in &card.summary {
                parts.push(s.clone());
            }
        }
        let contents = HoverContents::Markup(MarkupContent {
            kind: MarkupKind::Markdown,
            value: parts.join("\n\n"),
        });
        Ok(Some(Hover {
            contents,
            range: None,
        }))
    }

    async fn goto_definition(
        &self,
        params: GotoDefinitionParams,
    ) -> Result<Option<GotoDefinitionResponse>> {
        let uri = params.text_document_position_params.text_document.uri;
        let pos = params.text_document_position_params.position;
        let lines = self.document_lines(&uri);
        let line = lines.get(pos.line as usize).cloned().unwrap_or_default();
        let word = match self.word_at_utf16(&line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };
        let idx = self.index.read().unwrap();
        let entry = index::resolve(&idx, &word)
            .into_iter()
            .max_by(|a, b| a.confidence.partial_cmp(&b.confidence).unwrap());
        let entry = match entry {
            Some(e) => e,
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
        let lines = self.document_lines(&uri);
        let line = lines.get(pos.line as usize).cloned().unwrap_or_default();
        let word = match self.word_at_utf16(&line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };
        let idx = self.index.read().unwrap();
        let entry = index::resolve(&idx, &word)
            .into_iter()
            .max_by(|a, b| a.confidence.partial_cmp(&b.confidence).unwrap());
        let entry = match entry {
            Some(e) => e,
            None => return Ok(None),
        };

        let mut locations = Vec::new();
        for chapter in &idx.chapters {
            if let Ok(text) = std::fs::read_to_string(&chapter.path) {
                for (i, l) in text.lines().enumerate() {
                    let mut byte = 0usize;
                    for w in l.split(|c: char| !(c.is_alphanumeric() || c == '\'')) {
                        if w.eq_ignore_ascii_case(&entry.name) {
                            if let Some(start) = l[byte..].find(w) {
                                let col = byte + start;
                                locations.push(Location {
                                    uri: Url::from_file_path(&chapter.path)
                                        .unwrap_or_else(|_| uri.clone()),
                                    range: Range::new(
                                        Position::new(i as u32, col as u32),
                                        Position::new(i as u32, (col + w.len()) as u32),
                                    ),
                                });
                            }
                        }
                        byte += w.len() + 1;
                    }
                }
            }
        }
        Ok(Some(locations))
    }

    async fn completion(&self, params: CompletionParams) -> Result<Option<CompletionResponse>> {
        let mut items: Vec<CompletionItem> = Vec::new();
        let idx = self.index.read().unwrap();
        let mut seen = std::collections::HashSet::new();
        for card in &idx.cards {
            for name in card.aliases.iter().chain(std::iter::once(&card.name)) {
                let key = name.to_lowercase();
                if seen.contains(&key) {
                    continue;
                }
                seen.insert(key);
                items.push(CompletionItem {
                    label: name.clone(),
                    kind: Some(CompletionItemKind::REFERENCE),
                    detail: Some(card.rtype.clone()),
                    ..Default::default()
                });
            }
        }
        for status in &self.schema.statuses {
            items.push(CompletionItem {
                label: status.clone(),
                kind: Some(CompletionItemKind::ENUM_MEMBER),
                detail: Some("status".into()),
                ..Default::default()
            });
        }
        let _ = params;
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
        let word = match self.word_at_utf16(&line, pos.character) {
            Some(w) => w,
            None => return Ok(None),
        };
        if word.len() < 3 {
            return Ok(None);
        }

        let mut actions = Vec::new();
        let types: Vec<(&str, &str)> = vec![
            ("character", "Character"),
            ("location", "Location"),
            ("item", "Item"),
            ("organization", "Organization"),
        ];
        for (rtype, label) in types {
            let Some(new_uri) = self.card_uri(rtype, &word) else {
                continue;
            };
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
                        new_text: content.clone(),
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

#[tokio::main]
async fn main() {
    let stdin = tokio::io::stdin();
    let stdout = tokio::io::stdout();
    let (service, socket) = LspService::new(Backend::new);
    Server::new(stdin, stdout, socket).serve(service).await;
}
