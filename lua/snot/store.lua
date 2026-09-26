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

--- Full paths of all notes, including daily notes in `daily_directory`, newest first.
---@return string[]
function M.list()
  local dirs = { config.get().directory }
  if M.daily_dir() ~= dirs[1] then
    dirs[2] = M.daily_dir()
  end
  local out = {}
  for _, dir in ipairs(dirs) do
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

return M
