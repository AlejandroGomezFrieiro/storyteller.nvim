# Storyteller Language Server

Storyteller ships a **prose-aware language server** (`storyteller-lsp`, written
in Rust with `tower-lsp`) that replaces markdown-oxide for writing projects. It
is not a general Markdown engine: it understands *stories* — reference cards,
scene metadata, and the names that appear in your prose.

The server is packaged as `storyteller-lsp` in the storyteller flake. The
`nixvim_config` writing module wires it automatically; the standalone Storyteller
Nixvim module exposes `storyteller.lsp.package` for the same purpose.

---

## Why a language server?

Your prose is plain Markdown, so the plugin can always read it. But a server adds
**always-on, cursor-position-aware** behavior that a plugin alone cannot cheaply
provide:

- it knows *which* reference card a bare word names, even when the word is three
  tokens long or an alias;
- it can edit every mention (rename), not just the file in the current buffer;
- it can tell you, per scene, which names still need a card or a link.

Best of all, **no wikilinks**. The server indexes every reference card and its
`names:` aliases, then matches bare prose — write "Odysseus watched the harbor
lights" and hover, `gd`, `gr`, completion, and diagnostics all work on "Odysseus".

The server is a hybrid: it talks to the plugin's on-disk layout (`references/`,
`chapters/`) and the shared `schema.json`, while the Lua plugin keeps its own
index for views and fallbacks.

---

## How it attaches

The server starts as a Neovim client (LSP client) for `markdown` buffers under a
project root. In the writing configuration it is wired like this:

```nix
vim.lsp.config("storyteller", {
  cmd = [ "${storyteller-lsp}" ],   # the binary
  filetypes = { "markdown" },
  root_markers = { ".storyteller", ".git" },
})
vim.lsp.enable("storyteller")
```

A buffer is served when it is Markdown **and** lives under a root with, in
order of preference:

1. an explicit `.storyteller` marker,
2. a `chapters/` or `references/` layout,
3. a git root.

---

## What gets indexed

On startup, on save, and on watched-file changes the server rescans the project:

| What | From | Notes |
| --- | --- | --- |
| Reference cards | `references/<type>/<slug>.md` | Any subfolder is a type (see below). |
| Primary name | card `# heading` (before `—`/`–`/`:`) | e.g. `## Captain Greg` → "Captain Greg" |
| Aliases | frontmatter `names:` | e.g. `names: [Captain Greg, Greg]` |
| Summary | card `- **…**` bullet lines | shown on hover |
| Chapters | `chapters/*.md` | name matching + word-level mentions |
| Scene blocks | ```` ```yaml `` storyteller: scene ```` | metadata, `chars`/`locs`/… links |

Name keys are normalized (lowercased, punctuation stripped) so `Capt. Clark` in
an alias matches `Capt. Clark`/`capt clark` tokens in prose.

### Arbitrary reference types ("codex")

Every subfolder of `references/` is a reference **type** — the folder name *is*
the type id. Characters, locations, items, and organizations are built in, but a
`references/creatures/` folder needs no configuration to appear in the server:

- `references/creatures/grhall.md` → type `creatures`, resolvable in prose,
- listed in the create-card code actions ("Create Creatures card for …"),
- linkable into a scene's `creatures:` list (built-ins keep their short
  `chars`/`locs`/`items`/`orgs` fields; custom types use a list named after
  their folder),
- offered in YAML/prose completion and hover metadata.

The card *template* (which `- **…**` bullets a new card gets) comes from the
shared `schema.json` `reference_types.body`; custom types fall back to a single
`- **Notes:**`.

---

## Features

### Single- and multi-word resolution

The server matches names one **to three words** using the same n-gram strategy
as the plugin. "Odysseus" and "Captain Greg" both resolve; the hover range and
`gd`/`gr`/rename target the *full* matched phrase, not just the last token.

The same resolution powering cursors is used by code actions: a **visual
selection** over several words ("Captain Clark") is honored instead of the
single word under the cursor.

### Hover

`K` (or `vim.lsp.buf.hover()`) shows the card name, its type, and its summary
bullets. The hover is positioned over the resolved match range.

### Go to definition

`gd` opens the matching reference card file — through its canonical path, so it
survives alias matches ("The Grinding One" → `references/creatures/grhall.md`).

### References

`gr` lists every mention of an entity **across the whole alias set**. For a card
with aliases `[Odysseus, The Wanderer]`, references to either name are found in
every chapter.

### Rename

`vim.lsp.buf.rename()` changes an entity's name in its card *and* every mention
in every chapter. It rejects empty and identical new names. (Scope: exact primary-
name matches; alias rewriting is not performed.)

### Completion

Completion is **context-aware**:

- **In prose** — suggests reference names as you type.
- **Inside YAML** (frontmatter or a scene block) — suggests field names
  (`status`, `pov`, `chars`, …, plus any custom type's list field), enum values
  for `status`, and reference names for name-list fields (`chars`, `locs`,
  `items`, `orgs`, custom `creatures:`, …).

### Document outline

`<leader>o` / `vim.lsp.buf.document_symbol()` lists scene (`##`) headings in the
current chapter, grouped by their chapter `#` heading.

### Code actions

`vim.lsp.buf.code_action()` (`<leader>la`) offers:

1. **Create a card** for an unknown word/selection — one action per known type
   (Character, Location, Item, Organization, plus any codex folders), writing a
   templated card (`---\nnames:\n  - …\n---\n\n## …`) into
   `references/<type>/<slug>.md`.
2. **Link to this scene** — for a name that already resolves to a card, appends
   the canonical card name to the enclosing scene block's list field
   (`chars`/`locs`/`items`/`orgs`, or `creatures:`/… for custom types), creating
   the key if needed and de-duplicating case-insensitively.

### Diagnostics

`didChange`/`didSave`/`didChangeWatchedFiles` publish hints:

| Diagnostic | Severity | Meaning |
| --- | --- | --- |
| `No reference card for "…"` | HINT | A capitalized token in prose has no card — run the create-card code action. |
| `"…" is never mentioned` | HINT | A card exists but no chapter mentions its names (unused card). |

Diagnostics are hint-level by design: they nudge, they never warn-bomb a first
draft.

---

## Index freshness

The server is **rescan-on-demand**, not watch-based:

- `didOpen` / `didChange` keep the open buffer's text in memory,
- `didSave` and `didChangeWatchedFiles` trigger a full rescan + diagnostics republish.

So edits in another editor, or new card files dropped in `references/`, appear
after you save a chapter or any watched file.

---

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| `gd`/hover do nothing | Cursor not directly on a resolved name; try the middle of a matched phrase, or select it visually and use a code action. |
| Server not starting | Not under a project root: add a `.storyteller` marker, or check the buffer is `markdown` (`:set filetype`). |
| Names not resolving | Card is not under `references/<type>/`, or the `#`/`##` title was edited to differ from `names:`. Fix the card, then save any chapter to rescan. |
| Multiple providers conflicting | markdown-oxide and storyteller both target `markdown`; the writing module disables the former. |
| No completion in YAML | Position must be on/in a YAML key line; list fields only get name completion (not arbitrary values). |
| Old index after external edits | The server only rescans on save/watched-file events; save a chapter to refresh. |

---

## Manual install (no nixvim)

Point a plugin manager at the repo and add the server binary manually:

```lua
-- storyteller-lsp installed on PATH (or set a full path)
vim.lsp.config("storyteller", {
  cmd = { "storyteller-lsp" },
  filetypes = { "markdown" },
  root_markers = { ".storyteller", ".git" },
})
vim.lsp.enable("storyteller")
```

The flake exposes `packages.<system>.storyteller-lsp` for a `nix profile` /
`nix shell` install.