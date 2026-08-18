# Storyteller — nixvim module.
#
# Consumed by nixvim_config's `writing` derivation (Phase 5 wires the full
# feature set). This module establishes the `writing.storyteller` option
# namespace, adds the plugin package to the runtimepath so `:Story*` works,
# and optionally wires the consumers the plugin integrates with.
#
# Options (all under `writing.storyteller`):
#   enable       – enable the plugin itself (default true).
#   settings     – table passed to storyteller.setup({...}) (default {}).
#   export.enable – add pandoc to extraPackages for export commands
#                  (:StoryExport / :StoryExportAll). Default true.
#   lualine.enable – enable lualine so the plugin's live word-count status
#                  component can be picked up. Default true.
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
  cfg = config.writing.storyteller;
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
    export.enable =
      lib.mkEnableOption "pandoc via :StoryExport / :StoryExportAll" // {
        default = true;
      };
    lualine.enable = lib.mkEnableOption "lualine status component (word/target)" // {
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

    # Surface the plugin's word-count/target status to the statusline and let
    # the plugin's pickers use telescope when its backend is enabled.
    plugins.lualine.enable = lib.mkDefault cfg.lualine.enable;
    plugins.telescope.enable = lib.mkDefault cfg.picker.enable;

    extraConfigLua = lib.mkDefault ''
      -- Phase 5 registers Templates + Export into :Story* before the central
      -- registry materializes user commands during storyteller.setup().
      require("storyteller.commands.phase5").setup()
      require("storyteller").setup(${builtins.toJSON config.writing.storyteller.settings})
    ''
    + lib.optionalString (cfg.lualine.enable && cfg.picker.enable) ''
      -- Once lualine is up, patch in storyteller's status component so the
      -- live word/target readout shows next to the existing sections.
      vim.schedule(function()
        local ok = pcall(require, "lualine")
        if ok then
          require("storyteller.lualine").patch()
        end
      end)
    '';
  };
}