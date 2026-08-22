# AGENTS.md — Storyteller development

Nix-powered dev environment. Use the flake devshell; it provides the Rust
toolchain (cargo/rustc/rustfmt/clippy), `storyteller-tui`, nvim, vhs, stylua,
and luacheck.

## Fast paths

```bash
# Enter the devshell with the full toolchain.
nix develop .#default

# Plugin (Lua) regression suite — no Nix needed if nvim is on PATH.
nvim --headless -u NONE -l tests/storyteller_spec.lua

# Rust TUI — build + tests, from inside the devshell.
cargo test            # in tui/
cargo build           # or cargo check for a fast typecheck
cargo fmt --check     # and: cargo fmt to apply
cargo clippy -- -D warnings

# Lint the Lua (matches CI).
stylua --check lua/ plugin/ tests/

# Build the derived Nix packages / run the checks.
nix build .#storyteller-tui
nix build .#default
nix flake check
```

## Layout

- `tui/` — the Rust ratatui cockpit (`storyteller-tui`). Tests in `tui/src/**`
  use `TestBackend`; run with `cargo test` from inside `tui/`.
- `lua/`,`plugin/`,`doc/`,`templates/` — the Neovim plugin (Lua).
- `tests/storyteller_spec.lua` — the headless Lua regression suite.
- `docs/vhs/` — VHS demo tapes; regenerate the GIFs under `docs/assets/`.

## Flake notes

- `packages.default` — the nvim plugin (runtimepath source).
- `packages.storyteller-tui` — the Rust cockpit; its `cargoLock` pins the
  vendored git dep `storyteller-core` via `outputHashes`. If you bump the
  `storyteller-core` tag/rev in `tui/Cargo.toml`, re-run `cargo update` and
  update the hash in `flake.nix` (e.g. `nix run nixpkgs#nix-prefetch-git -- ...`).
- `packages.storyteller-lsp` — provided by the `storyteller` flake input.
- `devShells.default` — full toolchain; `devShells.demo` — the nixvim demo
  nvim + vhs for regenerating demo assets.

## Conventions

- Don't edit `tui/Cargo.lock` by hand; Regenerate via `cargo` in the devshell.
- Storyboard buffers on the Neovim side keep the canonical text editable and
  apply on `:w`; styling is an extmark overlay (`lua/storyteller/ui/board_hl.lua`).
- Semantic palette slots live in `tui/src/theme.rs` (Rust) and the
  `Storyteller*` highlights in `lua/storyteller/ui/init.lua`; keep them in sync.
