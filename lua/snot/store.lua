--- Reading notes from the notes directory: listing files and their front-matter tags.

local config = require("snot.config")

local M = {}

--- Folder daily notes live in: `daily_directory` if set, else `directory`.
---@return string
function M.daily_dir()
  local cfg = config.get()
  return cfg.daily_directory or cfg.directory
end

---@param stem string file name without extension
---@param dir? string defaults to the notes directory
---@return string
function M.path(stem, dir)
  local cfg = config.get()
  return vim.fs.joinpath(dir or cfg.directory, stem .. cfg.extension)
end

--- True if the note is on disk or already open (possibly unsaved) in a buffer.
---@param path string
---@return boolean
function M.exists(path)
  return vim.uv.fs_stat(path) ~= nil or vim.fn.bufexists(path) == 1
end

--- File names of the notes directly inside `dir`.
---@param dir string
---@return string[]
local function note_names(dir)
  local out = {}
  if vim.fn.isdirectory(dir) ~= 1 then
    return out
  end
  local ext = config.get().extension
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and vim.endswith(name, ext) then
      out[#out + 1] = name
    end
  end
  return out
end

--- Folders holding notes: the notes directory, plus `daily_directory` if it differs.
---@return string[]
local function dirs()
  local out = { config.get().directory }
  if M.daily_dir() ~= out[1] then
    out[2] = M.daily_dir()
  end
  return out
end

--- A note's file name without its extension, e.g. "20240102__my-idea".
--- Also accepts a bare stem.
---@param path string
---@return string
function M.stem(path)
  local name, ext = vim.fs.basename(path), config.get().extension
  return vim.endswith(name, ext) and name:sub(1, #name - #ext) or name
end

--- True if `path` is a note: a file with the note extension in a notes folder.
---@param path string
---@return boolean
function M.is_note(path)
  path = vim.fs.normalize(path)
  return vim.endswith(path, config.get().extension) and vim.tbl_contains(dirs(), vim.fs.dirname(path))
end

--- Full paths of all notes, including daily notes in `daily_directory`, newest first.
---@return string[]
function M.list()
  local out = {}
  for _, dir in ipairs(dirs()) do
    for _, name in ipairs(note_names(dir)) do
      out[#out + 1] = vim.fs.joinpath(dir, name)
    end
  end
  table.sort(out, function(a, b)
    return vim.fs.basename(a) > vim.fs.basename(b)
  end)
  return out
end

--- Dates of existing daily notes, newest first. Daily notes are the ones without
--- a "__title" suffix.
---@return string[]
function M.daily_dates()
  local ext = config.get().extension
  local out = {}
  for _, name in ipairs(note_names(M.daily_dir())) do
    if not name:find("__", 1, true) then
      out[#out + 1] = name:sub(1, #name - #ext)
    end
  end
  table.sort(out, function(a, b)
    return a > b
  end)
  return out
end

--- Read the tags from a note's +++ front matter (`tags = ["a", "b"]`).
--- Only the front matter is read, so this stays fast on long notes.
---@param path string
---@return string[]
function M.read_tags(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local tags, in_front_matter = {}, false
  for line in f:lines() do
    if line == "+++" then
      if in_front_matter then
        break -- end of front matter
      end
      in_front_matter = true
    elseif not in_front_matter then
      break -- no front matter at the top of the file
    else
      local list = line:match("^%s*tags%s*=%s*%[(.*)%]%s*$")
      if list then
        for tag in list:gmatch('"([^"]*)"') do
          tags[#tags + 1] = tag
        end
        break
      end
    end
  end
  f:close()
  return tags
end

--- All tags used across notes, sorted.
---@return string[]
function M.tags()
  local seen = {}
  for _, path in ipairs(M.list()) do
    for _, tag in ipairs(M.read_tags(path)) do
      seen[tag] = true
    end
  end
  local tags = vim.tbl_keys(seen)
  table.sort(tags)
  return tags
end

--- Full paths of notes carrying `tag` (exact match), newest first.
---@param tag string
---@return string[]
function M.notes_with_tag(tag)
  local out = {}
  for _, path in ipairs(M.list()) do
    if vim.tbl_contains(M.read_tags(path), tag) then
      out[#out + 1] = path
    end
  end
  return out
end

---@class snot.Location
---@field path string
---@field lnum integer 1-based
---@field col  integer 1-based byte column
---@field text string  the matching line

--- Turn ripgrep's --json output into locations, skipping links from the note itself.
---@param stdout string
---@param stem string
---@return snot.Location[]
local function parse_matches(stdout, stem)
  local out = {}
  for line in vim.gsplit(stdout, "\n", { plain = true, trimempty = true }) do
    local ok, msg = pcall(vim.json.decode, line)
    local data = ok and msg.type == "match" and msg.data
    -- path.text/lines.text are absent for non-UTF-8 content
    if data and data.path.text and data.lines.text and M.stem(data.path.text) ~= stem then
      out[#out + 1] = {
        path = data.path.text,
        lnum = data.line_number,
        col = data.submatches[1].start + 1,
        text = (data.lines.text:gsub("\r?\n$", "")),
      }
    end
  end
  local names = {}
  for _, loc in ipairs(out) do
    names[loc] = vim.fs.basename(loc.path)
  end
  table.sort(out, function(a, b)
    if names[a] ~= names[b] then
      return names[a] > names[b]
    end
    return a.lnum < b.lnum
  end)
  return out
end

--- Find links to a note, `[[stem]]` or `[[stem|alias]]`, in saved notes. Runs
--- ripgrep in the background and calls `on_done(locations)` on the main loop,
--- newest note first, or `on_done(nil, err)`.
---@param note string stem or path of the linked note
---@param on_done fun(locations?: snot.Location[], err?: string)
function M.backlinks(note, on_done)
  if vim.fn.executable("rg") ~= 1 then
    return on_done(nil, "ripgrep (rg) is required for backlinks")
  end
  local stem = M.stem(note)
  local search = vim.tbl_filter(function(dir)
    return vim.fn.isdirectory(dir) == 1
  end, dirs())
  if #search == 0 then
    return on_done({})
  end

  -- --no-config: a user's ripgreprc could change the output format.
  -- --max-depth 1, --hidden, --no-ignore: search exactly the files M.list() sees.
  -- stylua: ignore
  local cmd = {
    "rg", "--json", "--no-config", "--max-depth", "1", "--hidden", "--no-ignore",
    "--glob", "*" .. config.get().extension,
    "--fixed-strings", "-e", "[[" .. stem .. "]]", "-e", "[[" .. stem .. "|",
    "--",
  }
  vim.list_extend(cmd, search)

  local function on_exit(res)
    if res.code > 1 then -- 1 means no matches
      return on_done(nil, "rg failed: " .. vim.trim(res.stderr or ""))
    end
    on_done(parse_matches(res.stdout or "", stem))
  end
  vim.system(cmd, { text = true }, vim.schedule_wrap(on_exit))
end

return M
