# Storyteller — nixvim module.
#
# Standalone Nixvim module. It uses a neutral `storyteller.*` namespace so it
# can coexist with nixvim_config's separate `writing.storyteller.*` adapter.
# It adds the plugin package and its optional UI dependency (nui.nvim) to the
# runtimepath and wires optional consumers.
#
# Options (all under `storyteller`):
#   enable       – enable the plugin itself (default true).
#   settings     – table passed to storyteller.setup({...}) (default {}).
#   export.enable – add pandoc to extraPackages for export commands
#                  (:Story export / :Story export all). Default true.
#   picker.enable  – enable telescope, the plugin's preferred picker backend.
#                  Default true.
#   ui.enable      – add nui.nvim (optional; the plugin falls back to plain
#                  buffer views without it). Default true.
#   lsp.package    – the storyteller-lsp server binary; when set, the server is
#                  wired via vim.lsp.config for markdown buffers (default null).
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
      lib.mkEnableOption "pandoc via :Story export" // {
        default = true;
      };
    picker.enable = lib.mkEnableOption "telescope picker backend" // {
      default = true;
    };
    ui.enable = lib.mkEnableOption "nui.nvim UI dependency" // {
      default = true;
    };
    lsp.package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The storyteller-lsp server binary to wire via vim.lsp.config.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Put the plugin on the runtimepath so `plugin/storyteller.lua` loads.
    # nui.nvim is optional: the plugin's views degrade to plain buffers
    # without it. morph.nvim is vendored inside the plugin itself.
    extraPlugins = [storytellerPkg]
      ++ lib.optional cfg.ui.enable pkgs.vimPlugins.nui-nvim;

    # Pandoc powers manuscript export; only pulled in when export is on.
    extraPackages = lib.mkDefault (lib.optional cfg.export.enable pkgs.pandoc);

    # Let the plugin's pickers use Telescope when its backend is enabled.
    plugins.telescope.enable = lib.mkDefault cfg.picker.enable;

    extraConfigLua = lib.mkDefault ''
      require("storyteller").setup(${builtins.toJSON config.storyteller.settings})
    '' + lib.optionalString (cfg.lsp.package != null) ''
      vim.lsp.config("storyteller", {
        cmd = { "${lib.getExe cfg.lsp.package}" },
        filetypes = { "markdown" },
        root_markers = { ".storyteller", ".git" },
      })
      vim.lsp.enable("storyteller")
    '';
  };
}
