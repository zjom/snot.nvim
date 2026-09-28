--- snot.nvim: simple dated notes in Simple Note Format.
--- Spec: https://github.com/zjom/snot/blob/main/NOTE_SPEC.md

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

--- Full paths of notes carrying `@tag` in any scope, newest first.
---@param tag string
---@return string[]
function M.notes_with_tag(tag)
  return require("snot.store").notes_with_tag(tag)
end

--- Every place `@tag` is set, newest note first, then in reading order.
---@param tag string
---@return snot.Location[]
function M.tag_locations(tag)
  return require("snot.store").tag_locations(tag)
end

--- Pick from the places `tag` is set with the configured picker. Without a
--- tag, choose one from all tags first.
---@param tag? string
function M.find_by_tag(tag)
  return require("snot.find").by_tag(tag)
end

--- Find links to a note, `[[path]]`, `[[path#anchor]]` or `[[path|label]]`, in
--- the background. Calls `on_done(locations)` newest note first, or `on_done(nil, err)`.
---@param note string link path (e.g. "daily/20240102") or file path of the linked note
---@param on_done fun(locations?: snot.Location[], err?: string)
function M.backlinks(note, on_done)
  return require("snot.store").backlinks(note, on_done)
end

--- Pick from the notes linking to `note` (link path or file path; default: the current note)
--- with the configured picker.
---@param note? string
function M.find_backlinks(note)
  return require("snot.find").backlinks(note)
end

--- Format lines `first` to `last` of a note (default: all of the current
--- buffer): align the metadata ending headings and list items to the right
--- margin, 'textwidth' (79 if unset). With the language server, also trim
--- trailing whitespace and blank lines at the end.
---@param bufnr? integer
---@param first? integer 1-based
---@param last? integer 1-based, inclusive
function M.format(bufnr, first, last)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local client = require("snot.lsp").attached(bufnr)
  if not client then
    return require("snot.align").buffer(bufnr, first, last)
  end
  local range
  if first then
    local line = last or vim.api.nvim_buf_line_count(bufnr)
    range = { start = { first, 0 }, ["end"] = { line, 0 } }
  end
  local tw = vim.bo[bufnr].textwidth
  vim.lsp.buf.format({
    bufnr = bufnr,
    id = client.id,
    range = range,
    formatting_options = { width = tw > 0 and tw or nil },
  })
end

return M
