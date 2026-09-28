--- Configuration: defaults, user overrides and validation.
---
--- Options come from `vim.g.snot` or `require("snot").setup()`, whichever was set
--- last before the config is first read. setup() is optional.

---@class snot.Config
---@field directory string   folder containing notes
---@field daily_directory? string folder for daily notes, relative to `directory`. Unset: `directory`
---@field date_format string strftime format used for daily notes and note prefixes
---@field extension string   file extension for notes, including the dot
---@field open_cmd string    Ex command used to open notes, e.g. "edit", "vsplit", "tabedit", "botright split"
---@field templates table<string, string>
---@field picker? snot.PickerName | snot.PickerFn picker for tags and backlinks. Unset: first one installed
---@field format_on_save boolean align metadata in headings and list items when a note is saved
---@field lsp boolean use the snot language server when `snot` is installed

---@alias snot.PickerName "telescope" | "fzf-lua" | "snacks" | "mini.pick" | "quickfix" | "select"

---@class snot.UserConfig
---@field directory? string
---@field daily_directory? string
---@field date_format? string
---@field extension? string
---@field open_cmd? string
---@field templates? table<string, string>
---@field picker? snot.PickerName | snot.PickerFn
---@field format_on_save? boolean
---@field lsp? boolean

local M = {}

---@type snot.Config
M.defaults = {
  directory = "~/notes",
  date_format = "%Y%m%d",
  extension = ".snot",
  open_cmd = "edit",
  format_on_save = true,
  lsp = true,
  templates = {
    default = table.concat({
      "@created:${created}${tags}",
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
    -- Links are relative to `directory` (NOTE_SPEC.md, section 7.2), so daily
    -- notes must live inside it to be linkable.
    vim.validate("daily_directory", cfg.daily_directory, function(d)
      if d == nil then
        return true
      end
      if type(d) ~= "string" or d == "" or d:match("^[/~]") or d:match("^%a:[/\\]") then
        return false
      end
      for seg in vim.gsplit(d, "[/\\]") do
        if seg == ".." then
          return false
        end
      end
      return true
    end, true, "a relative path inside `directory`")
    vim.validate("date_format", cfg.date_format, "string")
    vim.validate("extension", cfg.extension, function(e)
      return type(e) == "string" and e:match("^%.[^./\\]+$") ~= nil
    end, 'a file extension including the dot, e.g. ".snot"')
    vim.validate("open_cmd", cfg.open_cmd, "string")
    vim.validate("templates", cfg.templates, "table")
    for name, template in pairs(cfg.templates) do
      vim.validate("templates." .. tostring(name), template, "string")
    end
    vim.validate("format_on_save", cfg.format_on_save, "boolean")
    vim.validate("lsp", cfg.lsp, "boolean")
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
    cfg.daily_directory = vim.fs.normalize(vim.fs.joinpath(cfg.directory, cfg.daily_directory))
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
