{
  description = "Storyteller: a Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    nixvim_config.url = "github:AlejandroGomezFrieiro/nixvim_config";
    nixvim_config.inputs.nixpkgs.follows = "nixpkgs";
    nixvim_config.inputs.systems.follows = "systems";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixvim_config,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    version = "0.2.0";
    # The exact Nixvim revision pinned by nixvim_config's lock.
    nixvim = inputs.nixvim_config.inputs.nixvim;
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
      # blink-cmp-spell (spelling suggestions as completions) is licensed
      # under a non-free license, so opt in to exactly that one package.
      demoPkgs = import inputs.nixpkgs {
        inherit (pkgs) system;
        config.allowUnfreePredicate = pkg:
          builtins.elem (pkg.pname or pkg.name) ["blink-cmp-spell"];
      };
      # The standard nixvim_config writing setup (Catppuccin, LSPSaga,
      # blink.cmp, Telescope, Fyler, …) with Storyteller enabled, used to
      # record the VHS demos in docs/vhs/.
      demoNvim = nixvim.legacyPackages.${system}.makeNixvimWithModule {
        pkgs = demoPkgs;
        module = {
          imports = [inputs.nixvim_config.nixosModules.writing];
          writing.storyteller.enable = true;
          # The writing module defaults these to its own storyteller input;
          # force the local plugin so demos track this repository.
          writing.storyteller.package =
            nixpkgs.lib.mkForce self.packages.${system}.default;
          writing.storyteller.lspPackage =
            nixpkgs.lib.mkForce self.packages.${system}.storyteller-lsp;
        };
      };
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.neovim
          pkgs.vhs
          # Optional UI dependency; the plugin falls back without it.
          pkgs.vimPlugins.nui-nvim
          # The language server, built from this flake.
          self.packages.${system}.storyteller-lsp
          # Rust toolchain for the language server.
          pkgs.cargo
          pkgs.rustc
          pkgs.gcc
          pkgs.pkg-config
        ];
      };

      # VHS recording shell: the standard writing Neovim plus VHS.
      demo = pkgs.mkShell {
        packages = [
          pkgs.vhs
          demoNvim
          # Keep the LSP executable available when demo-init.lua is used
          # directly instead of the generated Nixvim configuration.
          self.packages.${system}.storyteller-lsp
        ];
      };
    });

    # Standalone Nixvim module; nixvim_config supplies its own writing adapter.
    nixvimModules.default = import ./nixvim.nix;
  };
}
