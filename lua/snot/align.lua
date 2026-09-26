--- Aligning metadata: the tokens ending a heading or list item are pushed to
--- the right margin, away from the text, like tags in Vim help files:
---
---   # Atlas kickoff                                      @project:atlas @urgent
---
--- The margin is 'textwidth', or 79 when that is unset (as for |gq|). Padding
--- uses tabs up to 'tabstop' unless 'expandtab' is set, then spaces.

local format = require("snot.format")

local M = {}

--- Width used when 'textwidth' is 0: the most |gq| formats to.
M.default_width = 79

--- Split a heading or list item into its text and its trailing metadata, or
--- nil for any other line, or one with no text or no trailing metadata.
---@param line string
---@return string? text, string? meta
function M.split(line)
  local prefix = line:match("^#+ ")
  if prefix and #prefix > 7 then
    return
  end
  prefix = prefix or line:match("^ *[-+] ") or line:match("^ *%d+%. ")
  if not prefix then
    return
  end
  local box = line:match("^%[[ x-]%] ", #prefix + 1)
  prefix = prefix .. (box or "")

  local tokens = format.parse({ line })
  local start
  for t = #tokens, 1, -1 do
    if not line:sub(tokens[t].end_col, (start or #line + 1) - 1):match("^%s*$") then
      break
    end
    start = tokens[t].col
  end
  if not start then
    return
  end
  local text = line:sub(1, start - 1):gsub("%s+$", "")
  if vim.trim(text:sub(#prefix + 1)) == "" then
    return
  end
  return text, vim.trim(line:sub(start))
end

--- Padding from display column `from` to `to` (0-based), at least one space.
---@param from integer
---@param to integer
---@param expandtab boolean
---@param tabstop integer
---@return string
local function pad(from, to, expandtab, tabstop)
  if to <= from then
    return " "
  end
  if expandtab or tabstop <= 0 then
    return (" "):rep(to - from)
  end
  local tabs, col = 0, from
  while (math.floor(col / tabstop) + 1) * tabstop <= to do
    col = (math.floor(col / tabstop) + 1) * tabstop
    tabs = tabs + 1
  end
  return ("\t"):rep(tabs) .. (" "):rep(to - col)
end

---@class snot.AlignOpts
---@field width integer column the metadata ends at
---@field expandtab boolean pad with spaces only
---@field tabstop integer

--- The line with its trailing metadata aligned, or unchanged if it has none.
---@param line string
---@param opts snot.AlignOpts
---@return string
function M.line(line, opts)
  local text, meta = M.split(line)
  if not text then
    return line
  end
  local from = vim.fn.strdisplaywidth(text)
  local to = opts.width - vim.fn.strdisplaywidth(meta)
  return text .. pad(from, to, opts.expandtab, opts.tabstop) .. meta
end

--- Options for `bufnr` from its 'textwidth', 'expandtab' and 'tabstop'.
---@param bufnr integer
---@return snot.AlignOpts
function M.buf_opts(bufnr)
  local bo = vim.bo[bufnr]
  return {
    width = bo.textwidth > 0 and bo.textwidth or M.default_width,
    expandtab = bo.expandtab,
    tabstop = bo.tabstop,
  }
end

--- Align the metadata of headings and list items in lines `first` to `last`
--- (1-based, inclusive; default the whole buffer). Code and math blocks are
--- left alone. Only changed lines are set, so an aligned buffer isn't modified.
---@param bufnr? integer
---@param first? integer
---@param last? integer
function M.buffer(bufnr, first, last)
  if bufnr == nil or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local opts = M.buf_opts(bufnr)
  -- Read from the top, to know which lines are in code and math blocks.
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, last or -1, false)
  for lnum, line in format.inline_lines(lines) do
    if lnum >= (first or 1) then
      local aligned = M.line(line, opts)
      if aligned ~= line then
        vim.api.nvim_buf_set_lines(bufnr, lnum - 1, lnum, true, { aligned })
      end
    end
  end
end

return M
