# Storyteller — nixvim module.
#
# Standalone Nixvim module. It uses a neutral `storyteller.*` namespace so it
# can coexist with nixvim_config's separate `writing.storyteller.*` adapter.
# It adds the plugin package to the runtimepath and wires optional consumers.
#
# Options (all under `storyteller`):
#   enable       – enable the plugin itself (default true).
#   settings     – table passed to storyteller.setup({...}) (default {}).
#   export.enable – add pandoc to extraPackages for export commands
#                  (:StoryExport / :StoryExportAll). Default true.
#   picker.enable  – enable telescope, the plugin's preferred picker backend.
#                  Default true.
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
  cfg = config.storyteller;
in {
  options.storyteller = {
    enable = lib.mkEnableOption "storyteller novel-writing plugin" // {
      default = true;
    };
    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Options passed to storyteller.setup({...}).";
    };
    export.enable =
      lib.mkEnableOption "pandoc via :StoryExport / :StoryExportAll" // {
        default = true;
      };
    picker.enable = lib.mkEnableOption "telescope picker backend" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Put the plugin on the runtimepath so `plugin/storyteller.lua` loads.
    extraPlugins = [storytellerPkg];

    # Pandoc powers manuscript export; only pulled in when export is on.
    extraPackages = lib.mkDefault (lib.optional cfg.export.enable pkgs.pandoc);

    # Let the plugin's pickers use Telescope when its backend is enabled.
    plugins.telescope.enable = lib.mkDefault cfg.picker.enable;

    extraConfigLua = lib.mkDefault ''
      -- Phase 5 registers Templates + Export into :Story* before the central
      -- registry materializes user commands during storyteller.setup().
      require("storyteller.commands.phase5").setup()
      require("storyteller").setup(${builtins.toJSON config.storyteller.settings})
    '';
  };
}
