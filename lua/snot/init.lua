--- snot.nvim: simple dated markdown notes.

local M = {}

--- Override the default configuration. Optional: `vim.g.snot` works too.
---@param opts? snot.UserConfig
function M.setup(opts)
  require("snot.config").set(opts)
end

--- The resolved configuration.
---@return snot.Config
function M.config()
  return require("snot.config").get()
end

--- Absolute path of the notes directory.
---@return string
function M.directory()
  return require("snot.config").get().directory
end

--- Open a new note in a buffer pre-filled from a template. Nothing is written to
--- disk until the buffer is saved, so an abandoned note leaves no file behind.
--- If the note already exists (e.g. today's daily note), it is opened as-is.
---@param opts? snot.CreateNoteOpts
---@return integer? bufnr, string? path_or_err
function M.create_note(opts)
  return require("snot.note").create(opts)
end

---@class snot.DailyOpts
---@field content? string
---@field date?    string date in config.date_format; defaults to today
---@field cmd?     string overrides config.open_cmd for this call

--- Open the daily note for `opts.date` (default: today), pre-filling a new buffer if it doesn't exist.
---@param opts? snot.DailyOpts
---@return integer? bufnr, string? path_or_err
function M.goto_daily(opts)
  opts = opts or {}
  return M.create_note({ is_daily = true, content = opts.content, date = opts.date, cmd = opts.cmd })
end

--- Alias of |goto_daily()|, kept for compatibility.
M.create_daily = M.goto_daily

--- Open the notes directory, creating it if needed.
---@param opts? { cmd?: string }
---@return integer? bufnr, string? err
function M.open_dir(opts)
  return require("snot.note").open_dir((opts or {}).cmd)
end

--- All tags used across notes, sorted.
---@return string[]
function M.tags()
  return require("snot.store").tags()
end

--- Full paths of notes carrying `tag` (exact match), newest first.
---@param tag string
---@return string[]
function M.notes_with_tag(tag)
  return require("snot.store").notes_with_tag(tag)
end

--- Find notes by tag with Telescope. Without a tag, pick one from all tags first.
---@param tag? string
---@param opts? table telescope picker options (layout_config, etc.)
function M.find_by_tag(tag, opts)
  return require("snot.telescope").find_by_tag(tag, opts)
end

return M
