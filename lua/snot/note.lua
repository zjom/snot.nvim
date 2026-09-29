--- Creating and opening notes.

local config = require("snot.config")
local store = require("snot.store")
local util = require("snot.util")

local M = {}

---@class snot.CreateNoteOpts
---@field title?    string            required unless is_daily
---@field content?  string
---@field tags?     string | string[] list, or a comma/space separated string; written as `@tag` flags
---@field template? string            name of a template in config.templates
---@field is_daily? boolean
---@field date?     string            date in config.date_format; defaults to today
---@field open_cmd? string            overrides config.open_cmd for this call

---@param opts? snot.CreateNoteOpts
---@return integer? bufnr, string? path_or_err
function M.create(opts)
  opts = opts or {}
  local cfg = config.get()
  local open_cmd = opts.open_cmd or cfg.open_cmd

  local template_name = opts.template or "default"
  local template = cfg.templates[template_name]
  if not template then
    return util.fail(("unknown template %q"):format(template_name))
  end
  if not opts.is_daily and (opts.title == nil or opts.title == "") then
    return util.fail("a title is required for non-daily notes")
  end
  local tags, terr = util.normalize_tags(opts.tags)
  if not tags then
    return util.fail(terr --[[@as string]])
  end

  -- Create the folder now so a later :w doesn't fail with E212.
  local dir = opts.is_daily and store.daily_dir() or cfg.directory
  local ok, err = util.ensure_dir(dir)
  if not ok then
    return util.fail(("could not create %s: %s"):format(dir, err))
  end

  local date = opts.date or tostring(os.date(cfg.date_format))
  local title = opts.is_daily and date or opts.title --[[@as string]]
  local stem = opts.is_daily and date or (date .. "__" .. util.slugify(title))
  local path = store.path(stem, dir)

  if store.exists(path) then
    if opts.is_daily then
      local buf, oerr = util.open(path, open_cmd)
      if not buf then
        return util.fail(("could not open %s: %s"):format(path, oerr))
      end
      return buf, path
    end
    local sec, usec = vim.uv.gettimeofday()
    path = store.path(("%s__%d%06d"):format(stem, sec, usec), dir)
  end

  local text = util.render(template, {
    title = title,
    date = date,
    created = os.date("%Y-%m-%d"),
    tags = table.concat(vim.tbl_map(function(t)
      return " @" .. t
    end, tags)),
    content = opts.content,
  })
  local lines = vim.split(text, "\n", { plain = true })

  local buf, oerr = util.open(path, open_cmd)
  if not buf then
    return util.fail(("could not open %s: %s"):format(path, oerr))
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Leave the buffer unmodified: if the user types nothing and closes it, no
  -- file is created and :q doesn't complain. Any edit makes it modified again.
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines] })

  return buf, path
end

--- Open the notes directory, creating it if needed.
---@param open_cmd? string overrides config.open_cmd for this call
---@return integer? bufnr, string? err
function M.open_dir(open_cmd)
  local cfg = config.get()
  local ok, err = util.ensure_dir(cfg.directory)
  if not ok then
    return util.fail(("could not create %s: %s"):format(cfg.directory, err))
  end
  local buf, oerr = util.open(cfg.directory, open_cmd or cfg.open_cmd)
  if not buf then
    return util.fail(oerr --[[@as string]])
  end
  return buf
end

return M
