--- Configuration: defaults, user overrides and validation.
---
--- Options come from `vim.g.snot` or `require("snot").setup()`, whichever was set
--- last before the config is first read. setup() is optional.

---@class snot.Config
---@field directory string   folder containing notes
---@field daily_directory? string folder for daily notes; relative paths are inside `directory`. Unset: `directory`
---@field date_format string strftime format used for daily notes and note prefixes
---@field extension string   file extension for notes, including the dot
---@field open_cmd string    Ex command used to open notes, e.g. "edit", "vsplit", "tabedit", "botright split"
---@field templates table<string, string>
---@field picker? snot.PickerName | snot.PickerFn picker for tags and backlinks. Unset: first one installed

---@alias snot.PickerName "telescope" | "fzf-lua" | "snacks" | "mini.pick" | "quickfix" | "select"

---@class snot.UserConfig
---@field directory? string
---@field daily_directory? string
---@field date_format? string
---@field extension? string
---@field open_cmd? string
---@field templates? table<string, string>
---@field picker? snot.PickerName | snot.PickerFn

local M = {}

---@type snot.Config
M.defaults = {
  directory = "~/notes",
  date_format = "%Y%m%d",
  extension = ".md",
  open_cmd = "edit",
  templates = {
    default = table.concat({
      "+++",
      "title = ${title_toml}",
      "date = ${date}",
      "tags = ${tags}",
      "+++",
      "",
      "# ${title}",
      "",
      "${content}",
    }, "\n"),
  },
}

---@type snot.Config?
local current

--- Check a merged config, returning an error message describing the first problem.
---@param cfg table
---@return boolean ok, string? err
function M.validate(cfg)
  return pcall(function()
    vim.validate("directory", cfg.directory, "string")
    vim.validate("daily_directory", cfg.daily_directory, "string", true)
    vim.validate("date_format", cfg.date_format, "string")
    vim.validate("extension", cfg.extension, "string")
    vim.validate("open_cmd", cfg.open_cmd, "string")
    vim.validate("templates", cfg.templates, "table")
    for name, template in pairs(cfg.templates) do
      vim.validate("templates." .. tostring(name), template, "string")
    end
    vim.validate("picker", cfg.picker, function(p)
      return type(p) == "function" or require("snot.picker").backends[p] ~= nil
    end, true, "a picker name or function")
  end)
end

--- Merge `opts` over a fresh copy of the defaults, so repeated calls don't accumulate state.
--- An invalid config is reported and the defaults are used instead.
---@param opts? snot.UserConfig
---@return snot.Config
local function resolve(opts)
  if opts ~= nil and type(opts) ~= "table" then
    vim.notify("snot: config must be a table, using defaults", vim.log.levels.ERROR)
    opts = nil
  end
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  local ok, err = M.validate(cfg)
  if not ok then
    vim.notify("snot: invalid config, using defaults: " .. tostring(err), vim.log.levels.ERROR)
    cfg = vim.deepcopy(M.defaults)
  end
  cfg.directory = vim.fs.normalize(cfg.directory)
  if cfg.daily_directory then
    local daily = vim.fs.normalize(cfg.daily_directory)
    cfg.daily_directory = vim.fs.abspath(daily) == daily and daily or vim.fs.joinpath(cfg.directory, daily)
  end
  return cfg
end

---@param opts? snot.UserConfig
function M.set(opts)
  current = resolve(opts)
end

---@return snot.Config
function M.get()
  if not current then
    current = resolve(vim.g.snot)
  end
  return current
end

return M
