{
  description = "Storyteller: a Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    version = "0.2.0";
  in {
    # The plugin as a Neovim-loadable package (runtimepath source):
    # lazy.nvim:  { dir = paths-storytelling_plugin }
    # nixvim:     nvim.extraPlugins = [ self.packages.${system}.default ]
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      default = pkgs.runCommand "storyteller-nvim-${version}" {} ''
        mkdir -p $out
        cp -r ${./plugin} $out/plugin
        cp -r ${./lua} $out/lua
        cp -r ${./doc} $out/doc
        cp -r ${./templates} $out/templates
      '';

      # Prose-aware language server (replaces markdown-oxide for Storyteller).
      storyteller-lsp = pkgs.rustPlatform.buildRustPackage {
        pname = "storyteller-lsp";
        version = version;
        src = ./server;
        cargoLock = {lockFile = ./server/Cargo.lock;};
        doCheck = true;
      };
    });

    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.neovim
          pkgs.vhs
          # Optional UI dependency; the plugin falls back without it.
          pkgs.vimPlugins.nui-nvim
          # Rust toolchain for the language server.
          pkgs.cargo
          pkgs.rustc
          pkgs.gcc
          pkgs.pkg-config
        ];
      };
    });

    # Standalone Nixvim module; nixvim_config supplies its own writing adapter.
    nixvimModules.default = import ./nixvim.nix;
  };
}
