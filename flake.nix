{
  description = "Storyteller: a Scrivener/Kindling-class novel-writing engine for Neovim over Markdown.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    nixvim_config.url = "github:AlejandroGomezFrieiro/nixvim_config";
    nixvim_config.inputs.nixpkgs.follows = "nixpkgs";
    nixvim_config.inputs.systems.follows = "systems";
    # The open standard + reference language server (spec/ + storyteller-lsp).
    storyteller.url = "github:AlejandroGomezFrieiro/storyteller";
    storyteller.inputs.nixpkgs.follows = "nixpkgs";
    storyteller.inputs.systems.follows = "systems";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    nixvim_config,
    storyteller,
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

      # The ratatui cockpit (tui/): dashboard, corkboard and timeline mirrors,
      # $EDITOR handoff. Depends only on the project's Markdown files.
      storyteller-tui = pkgs.rustPlatform.buildRustPackage {
        pname = "storyteller-tui";
        inherit version;
        src = ./tui;
        cargoLock.lockFile = ./tui/Cargo.lock;
        meta.mainProgram = "storyteller-tui";
      };

      # Prose-aware language server, provided by the storyteller standard repo.
      storyteller-lsp = storyteller.packages.${system}.storyteller-lsp;
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
          # The language server, from the storyteller standard repo.
          self.packages.${system}.storyteller-lsp
          # The ratatui cockpit.
          self.packages.${system}.storyteller-tui
          # Lint/format for CI parity.
          pkgs.stylua
          pkgs.luajitPackages.luacheck
        ];
      };

      # VHS recording shell: the standard writing Neovim plus VHS.
      demo = pkgs.mkShell {
        packages = [
          pkgs.vhs
          demoNvim
          # The ratatui cockpit, for docs/vhs/19-tui.tape.
          self.packages.${system}.storyteller-tui
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
