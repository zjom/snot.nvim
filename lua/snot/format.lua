--- Reading Simple Note Format (NOTE_SPEC.md): the metadata tokens and links in
--- a note. Code and math, both blocks and inline spans, are verbatim and skipped.

local M = {}

---@class snot.Token
---@field key    string
---@field values string[]
---@field lnum   integer 1-based
---@field col    integer 1-based byte column of the "@"

---@class snot.Link
---@field target string trimmed and unescaped
---@field label? string
---@field lnum   integer 1-based
---@field col    integer 1-based byte column of the "[["

---@param c string
---@return boolean
local function is_punct(c)
  return c ~= "" and c:match("^%p$") ~= nil
end

---@param c string
---@return boolean
local function is_space(c)
  return c == " " or c == "\t"
end

--- Remove escapes: a backslash before ASCII punctuation yields the punctuation.
---@param s string
---@return string
local function unescape(s)
  return (s:gsub("\\(%p)", "%1"))
end

--- Split `s` at unescaped `sep` characters, keeping escapes in the pieces.
---@param s string
---@param sep string a single character
---@return string[]
local function split_unescaped(s, sep)
  local out, start, i = {}, 1, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and is_punct(s:sub(i + 1, i + 1)) then
      i = i + 2
    elseif c == sep then
      out[#out + 1] = s:sub(start, i - 1)
      start, i = i + 1, i + 1
    else
      i = i + 1
    end
  end
  out[#out + 1] = s:sub(start)
  return out
end

--- Index just past the first unescaped `stop` pattern match at or after `i`, and
--- the index where the match starts; nil if there is none on the line.
---@param line string
---@param i integer
---@param stop string a literal string
---@return integer? after, integer? at
local function find_unescaped(line, i, stop)
  while i <= #line do
    if line:sub(i, i) == "\\" and is_punct(line:sub(i + 1, i + 1)) then
      i = i + 2
    elseif line:sub(i, i + #stop - 1) == stop then
      return i + #stop, i
    else
      i = i + 1
    end
  end
end

--- Try to read a metadata token whose "@" is at `i`.
---@param line string
---@param i integer
---@param is_row boolean a table row, where "|" ends a value
---@return integer? after, string? key, string[]? values
local function read_token(line, i, is_row)
  local key = line:match("^[a-z][a-z0-9_-]*", i + 1)
  if not key then
    return
  end
  local j = i + 1 + #key
  if line:sub(j, j) ~= ":" then
    return j, key, { "true" }
  end
  local first = line:sub(j + 1, j + 1)
  if first == "[" then
    local after, close = find_unescaped(line, j + 2, "]")
    if not after then
      return -- an unclosed list makes the whole token text
    end
    local values = {}
    for _, item in ipairs(split_unescaped(line:sub(j + 2, close - 1), ",")) do
      item = vim.trim(unescape(item))
      if item ~= "" then
        values[#values + 1] = item
      end
    end
    return after, key, values
  end
  -- A scalar runs to the next whitespace (or "|" in a table row).
  local k = j + 1
  while k <= #line do
    local c = line:sub(k, k)
    if c == "\\" and is_punct(line:sub(k + 1, k + 1)) then
      k = k + 2
    elseif is_space(c) or (is_row and c == "|") then
      break
    else
      k = k + 1
    end
  end
  if k == j + 1 or (is_row and first == "|") then
    return j, key, { "true" } -- "@key:" with no value: a flag followed by ":"
  end
  return k, key, { unescape(line:sub(j + 1, k - 1)) }
end

--- Scan one line of inline content for tokens and links.
---@param line string
---@param lnum integer
---@param tokens snot.Token[]
---@param links snot.Link[]
local function scan_inline(line, lnum, tokens, links)
  local is_row = line:match("^ *|") ~= nil
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    local prev = i > 1 and line:sub(i - 1, i - 1) or ""
    if c == "\\" and is_punct(line:sub(i + 1, i + 1)) then
      i = i + 2
    elseif c == "`" then
      local run = line:match("^`+", i)
      -- Inline code closes at the next run of exactly the same length.
      local j, close = i + #run, nil
      while true do
        local s, e = line:find("`+", j)
        if not s then
          break
        end
        if e - s + 1 == #run then
          close = e
          break
        end
        j = e + 1
      end
      i = (close or (i + #run - 1)) + 1
    elseif c == "$" and line:sub(i + 1, i + 1):match("^%S$") then
      -- Inline math closes at a "$" after a non-space and not before a digit.
      local close
      for j = i + 2, #line do
        if
          line:sub(j, j) == "$"
          and not is_space(line:sub(j - 1, j - 1))
          and not line:sub(j + 1, j + 1):match("^%d$")
        then
          close = j
          break
        end
      end
      i = (close or i) + 1
    elseif c == "[" and line:sub(i + 1, i + 1) == "[" then
      local after, close = find_unescaped(line, i + 2, "]]")
      if after then
        local parts = split_unescaped(line:sub(i + 2, close - 1), "|")
        local label = #parts > 1 and vim.trim(unescape(table.concat(parts, "|", 2))) or nil
        links[#links + 1] = { target = vim.trim(unescape(parts[1])), label = label, lnum = lnum, col = i }
        i = after
      else
        i = i + 2
      end
    elseif c == "@" and (prev == "" or is_space(prev) or (is_row and prev == "|")) then
      local after, key, values = read_token(line, i, is_row)
      if after then
        tokens[#tokens + 1] = { key = key, values = values, lnum = lnum, col = i }
        i = after
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
end

--- The tokens and links in a note's lines, in reading order.
---@param lines string[]
---@return snot.Token[] tokens, snot.Link[] links
function M.parse(lines)
  local tokens, links = {}, {}
  ---@type string? pattern matching the closing fence of the open verbatim block
  local fence
  for lnum, line in ipairs(lines) do
    line = line:gsub("\r$", "")
    if fence then
      if line:match(fence) then
        fence = nil
      end
    else
      local ticks = line:match("^%s*(```+)")
      if ticks then
        fence = "^%s*" .. ticks .. "`*%s*$"
      elseif line:match("^%s*%$%$%s*$") then
        fence = "^%s*%$%$%s*$"
      else
        scan_inline(line, lnum, tokens, links)
      end
    end
  end
  return tokens, links
end

--- Read and parse the note at `path`; nothing if it can't be read.
---@param path string
---@return snot.Token[] tokens, snot.Link[] links, string[] lines
function M.parse_file(path)
  local f = io.open(path, "r")
  if not f then
    return {}, {}, {}
  end
  local lines = vim.split(f:read("*a"), "\n", { plain = true })
  f:close()
  local tokens, links = M.parse(lines)
  return tokens, links, lines
end

--- True for a token in flag form, `@key`, or its equivalent `@key:true`.
---@param token snot.Token
---@return boolean
function M.is_flag(token)
  return #token.values == 1 and token.values[1] == "true"
end

--- True if `s` is a valid metadata key, e.g. a tag.
---@param s string
---@return boolean
function M.is_key(s)
  return s:match("^[a-z][a-z0-9_-]*$") ~= nil
end

--- The note path and anchor a link target points at, or nil if the target is a
--- URL, an anchor in the same file, or a file with an extension.
---@param target string
---@return string? path, string? anchor
function M.note_target(target)
  if target:match("^%a[%w+.-]*://") or target:sub(1, 1) == "#" then
    return
  end
  local path, anchor = target:match("^([^#]*)#?(.*)$")
  if path == "" or vim.fs.basename(path):find(".", 1, true) then
    return
  end
  return path, anchor ~= "" and anchor or nil
end

--- A heading's slug (section 7.3), also used for note file names: tokens
--- removed, lowercased, runs of non-alphanumerics replaced by "-".
---@param text string
---@return string
function M.slug(text)
  local tokens = M.parse({ text })
  -- Remove tokens back to front so earlier columns stay valid.
  for t = #tokens, 1, -1 do
    local tok = tokens[t]
    local after = read_token(text, tok.col, false)
    text = text:sub(1, tok.col - 1) .. text:sub(after --[[@as integer]])
  end
  return (text:lower():gsub("%W+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

return M
