# Storyteller — nixvim module.
#
# Consumed by nixvim_config's `writing` derivation (Phase 5 wires the full
# feature set). This stub establishes the option namespace and adds the
# plugin package to the runtimepath so `:Story*` is available.
#
# The plugin source is the enclosing repo (`./`), so this module works whether
# consumed from the flake or vendored.
{
  config,
  lib,
  pkgs,
  ...
}: let
  storytellerPkg = pkgs.runCommand "storyteller-nvim" {} ''
    mkdir -p $out
    cp -r ${./plugin} $out/plugin
    cp -r ${./lua} $out/lua
    cp -r ${./doc} $out/doc
    cp -r ${./templates} $out/templates
  '';
in {
  options.writing.storyteller = {
    enable = lib.mkEnableOption "storyteller novel-writing plugin" // {
      default = true;
    };
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Options passed to storyteller.setup({...}).";
    };
  };

  config = lib.mkIf config.writing.storyteller.enable {
    # Put the plugin on the runtimepath so `plugin/storyteller.lua` loads.
    extraPlugins = [storytellerPkg];

    extraConfigLua = lib.mkDefault ''
      require("storyteller").setup(${builtins.toJSON config.writing.storyteller.settings})
    '';
  };
}