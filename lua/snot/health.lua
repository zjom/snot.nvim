--- :checkhealth snot

local M = {}

function M.check()
  local health = vim.health

  health.start("snot: environment")
  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim >= 0.11")
  else
    health.error("snot.nvim requires Neovim >= 0.11")
  end

  health.start("snot: configuration")
  local config = require("snot.config")
  local user = vim.g.snot
  if user == nil then
    health.info("vim.g.snot not set; using setup() options or defaults")
  elseif type(user) ~= "table" then
    health.error("vim.g.snot must be a table, got " .. type(user))
  else
    local ok, err = config.validate(vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), user or {}))
    if ok then
      health.ok("vim.g.snot is valid")
    else
      health.error("vim.g.snot is invalid: " .. tostring(err))
    end
  end

  local cfg = config.get()
  if not cfg.templates.default then
    health.warn("no `default` template; notes created without `template` will fail")
  end
  if vim.fn.isdirectory(cfg.directory) == 1 then
    if vim.fn.filewritable(cfg.directory) == 2 then
      health.ok("notes directory: " .. cfg.directory)
    else
      health.error("notes directory is not writable: " .. cfg.directory)
    end
  else
    health.info("notes directory will be created on first use: " .. cfg.directory)
  end

  health.start("snot: language server")
  local lsp = require("snot.lsp")
  local cmd = (vim.lsp.config.snot or {}).cmd
  if not cfg.lsp then
    health.info("off (`lsp = false`); reading notes in Lua")
  elseif type(cmd) ~= "table" then
    health.info("custom command; not checked")
  elseif lsp.enabled() then
    local version = vim.system({ cmd[1], "--version" }, { text = true }):wait()
    health.ok(("%s: %s"):format(vim.fn.exepath(cmd[1]), vim.trim(version.stdout or "")))
  else
    health.warn(cmd[1] .. " not found; formatting, tags and backlinks fall back to Lua", {
      "Install it from https://github.com/zjom/snot, e.g. `nix profile install github:zjom/snot`",
    })
  end

  health.start("snot: optional dependencies")
  if vim.fn.executable("rg") == 1 then
    health.ok("ripgrep found (:Snot backlinks without the language server)")
  elseif lsp.enabled() then
    health.info("ripgrep not found; not needed with the language server")
  else
    health.warn("ripgrep (rg) not found; :Snot backlinks is unavailable")
  end
  local ts = require("snot.treesitter")
  for _, lang in ipairs({ "snot", "snot_inline" }) do
    if ts.has_parser(lang) then
      health.ok("tree-sitter parser found: " .. lang)
    else
      health.warn("tree-sitter parser not found: " .. lang .. "; notes have no highlighting", {
        "With nvim-treesitter (main branch): :TSInstall snot",
        "Or build it from https://github.com/zjom/tree-sitter-snot",
      })
    end
  end
  local picker = cfg.picker
  if type(picker) == "function" then
    health.info("picker: custom function")
  else
    health.info("picker: " .. (picker or "auto (telescope, fzf-lua, snacks, mini.pick, then vim.ui.select)"))
  end
end

return M
