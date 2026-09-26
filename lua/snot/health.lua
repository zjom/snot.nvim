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

  health.start("snot: optional dependencies")
  if vim.fn.executable("rg") == 1 then
    health.ok("ripgrep found (:Snot backlinks)")
  else
    health.warn("ripgrep (rg) not found; :Snot backlinks is unavailable")
  end
  local picker = cfg.picker
  if type(picker) == "function" then
    health.info("picker: custom function")
  else
    health.info("picker: " .. (picker or "auto (telescope, fzf-lua, snacks, mini.pick, then vim.ui.select)"))
  end
end

return M
