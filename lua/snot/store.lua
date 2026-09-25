--- Reading notes from the notes directory: listing files and their front-matter tags.

local config = require("snot.config")

local M = {}

---@param stem string file name without extension
---@return string
function M.path(stem)
  local cfg = config.get()
  return vim.fs.joinpath(cfg.directory, stem .. cfg.extension)
end

--- True if the note is on disk or already open (possibly unsaved) in a buffer.
---@param path string
---@return boolean
function M.exists(path)
  return vim.uv.fs_stat(path) ~= nil or vim.fn.bufexists(path) == 1
end

--- File names of all notes in the notes folder, newest first.
---@return string[]
function M.list()
  local out = {}
  local cfg = config.get()
  if vim.fn.isdirectory(cfg.directory) ~= 1 then
    return out
  end
  for name, kind in vim.fs.dir(cfg.directory) do
    if kind == "file" and vim.endswith(name, cfg.extension) then
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b)
    return a > b
  end)
  return out
end

--- Dates of existing daily notes, newest first. Daily notes are the ones without
--- a "__title" suffix.
---@return string[]
function M.daily_dates()
  local ext = config.get().extension
  local out = {}
  for _, name in ipairs(M.list()) do
    if not name:find("__", 1, true) then
      out[#out + 1] = name:sub(1, #name - #ext)
    end
  end
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
  local dir = config.get().directory
  local seen = {}
  for _, name in ipairs(M.list()) do
    for _, tag in ipairs(M.read_tags(vim.fs.joinpath(dir, name))) do
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
  local dir = config.get().directory
  local out = {}
  for _, name in ipairs(M.list()) do
    local path = vim.fs.joinpath(dir, name)
    if vim.tbl_contains(M.read_tags(path), tag) then
      out[#out + 1] = path
    end
  end
  return out
end

return M
