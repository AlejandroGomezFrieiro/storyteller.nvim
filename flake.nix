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
    version = "0.0.1";
  in {
    # The plugin as a Neovim-loadable package (runtimepath source):
    # lazy.nvim:  { dir = paths-storytelling_plugin }
    # nixvim:     nvim.extraPlugins = [ self.packages.${system}.default ]
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.runCommand "storyteller-nvim-${version}" {} ''
        mkdir -p $out
        cp -r ${./plugin} $out/plugin
        cp -r ${./lua} $out/lua
        cp -r ${./doc} $out/doc
        cp -r ${./templates} $out/templates
      '';
    });

    # nixvim module (consumed by nixvim_config's `writing` derivation).
    # Added in Phase 5; kept as a stub so the contract lands early.
    nixvimModules.default = import ./nixvim.nix;
  };
}