local M = {}

--- Substitute ${name} placeholders. Missing values render as "" rather than "nil".
---@param str string
---@param vars table<string, any>
---@return string
function M.render(str, vars)
  return (str:gsub("%${([%w_]+)}", function(k)
    local v = vars[k]
    return v == nil and "" or tostring(v)
  end))
end

--- Tags as metadata keys: a leading "@" is dropped and letters are lowercased.
---@param tags? string | string[] list, or a comma/space separated string
---@return string[]? tags, string? err
function M.normalize_tags(tags)
  if tags == nil then
    return {}
  end
  if type(tags) == "string" then
    tags = vim.split(tags, "[,%s]+", { trimempty = true })
  end
  local out = {}
  for _, tag in ipairs(tags) do
    tag = tag:gsub("^@", ""):lower()
    if not require("snot.format").is_key(tag) then
      return nil, ("invalid tag %q: use a letter, then letters, digits, - or _"):format(tag)
    end
    out[#out + 1] = tag
  end
  return out
end

--- Turn a free-form title into something safe to use as a file name: its
--- heading slug (NOTE_SPEC.md, section 7.3).
---@param s string
---@return string
function M.slugify(s)
  local slug = require("snot.format").slug(s)
  return slug ~= "" and slug or "untitled"
end

---@param dir string
---@return boolean ok, string? err
function M.ensure_dir(dir)
  if vim.fn.isdirectory(dir) == 1 then
    return true
  end
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then
    return false, tostring(err)
  end
  return true
end

--- Turn "today", "yesterday", "tomorrow" or an offset like "-3"/"+1" into a date
--- formatted with `date_format`. Anything else is taken as a literal date. "" means today.
---@param arg string
---@param date_format string
---@return string? date nil for today
function M.resolve_date(arg, date_format)
  if arg == "" then
    return nil
  end
  ---@type integer?
  local offset = ({ today = 0, yesterday = -1, tomorrow = 1 })[arg]
  if not offset and arg:match("^[+-]%d+$") then
    offset = tonumber(arg)
  end
  if not offset then
    return arg
  end
  local t = os.date("*t") --[[@as osdate]]
  t.day = t.day + offset -- os.time normalises overflowing days across months/years
  t.hour = 12 -- midday avoids DST edge cases
  return tostring(os.date(date_format, os.time(t)))
end

--- Report an error to the user and return it in the `nil, err` convention.
---@param msg string
---@return nil, string
function M.fail(msg)
  vim.notify("snot: " .. msg, vim.log.levels.ERROR)
  return nil, msg
end

--- Open `path` in a window using the Ex command `cmd`, returning the buffer number.
---@param path string
---@param cmd string
---@return integer? bufnr, string? err
function M.open(path, cmd)
  local ok, err = pcall(vim.api.nvim_command, cmd .. " " .. vim.fn.fnameescape(path))
  if not ok then
    return nil, tostring(err)
  end
  return vim.api.nvim_get_current_buf()
end

return M
