--- Reading notes from the notes directory: listing files, their tags and the
--- links between them. Tags and links come from the snot language server when
--- it is installed (lua/snot/lsp.lua), else from reading the notes in Lua.

local config = require("snot.config")
local format = require("snot.format")
local lsp = require("snot.lsp")

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

---@param a string
---@param b string
---@return boolean
local function newest_first(a, b)
  return vim.fs.basename(a) > vim.fs.basename(b)
end

--- Sort locations newest note first, then in reading order.
---@param locations snot.Location[]
---@return snot.Location[]
local function sort_locations(locations)
  table.sort(locations, function(a, b)
    if a.path ~= b.path then
      local x, y = vim.fs.basename(a.path), vim.fs.basename(b.path)
      if x ~= y then
        return x > y
      end
      return a.path > b.path
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)
  return locations
end

--- A note's link path (NOTE_SPEC.md, section 7.2): its path relative to the
--- notes directory, without the extension, e.g. "daily/20240102". Also accepts
--- a link path, returned as-is.
---@param path string
---@return string
function M.link_path(path)
  local ext = config.get().extension
  local rel = vim.fs.relpath(config.get().directory, vim.fs.abspath(vim.fs.normalize(path)))
  if not rel or not vim.endswith(path, ext) then
    return path
  end
  return rel:sub(1, #rel - #ext)
end

--- True if `path` is a note: a file with the note extension under the notes
--- directory, outside hidden folders.
---@param path string
---@return boolean
function M.is_note(path)
  path = vim.fs.normalize(path)
  local rel = vim.fs.relpath(config.get().directory, path)
  return rel ~= nil and vim.endswith(path, config.get().extension) and not ("/" .. rel):find("/%.")
end

--- Full paths of all notes under the notes directory, including daily notes,
--- newest first. Hidden files and folders are skipped.
---@return string[]
function M.list()
  local root, ext = config.get().directory, config.get().extension
  local out = {}
  if vim.fn.isdirectory(root) ~= 1 then
    return out
  end
  local entries = vim.fs.dir(root, {
    depth = math.huge,
    skip = function(name)
      return not vim.fs.basename(name):match("^%.")
    end,
  })
  for name, kind in entries do
    if kind == "file" and vim.endswith(name, ext) and not vim.fs.basename(name):match("^%.") then
      out[#out + 1] = vim.fs.joinpath(root, name)
    end
  end
  table.sort(out, newest_first)
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

---@class snot.Location
---@field path string
---@field lnum integer 1-based
---@field col  integer 1-based byte column
---@field text string  the matching line

--- Where the tags in a note are: every flag token, `@tag`, in any scope.
---@param path string
---@return { tag: string, loc: snot.Location }[]
local function tags_in(path)
  local tokens, _, lines = format.parse_file(path)
  local out = {}
  for _, tok in ipairs(tokens) do
    if format.is_flag(tok) then
      local text = lines[tok.lnum]:gsub("\r$", "")
      out[#out + 1] = { tag = tok.key, loc = { path = path, lnum = tok.lnum, col = tok.col, text = text } }
    end
  end
  return out
end

--- The tags in a note: its flag tokens (`@tag`), from any scope, deduplicated.
---@param path string
---@return string[]
function M.read_tags(path)
  local seen, out = {}, {}
  for _, t in ipairs(tags_in(path)) do
    if not seen[t.tag] then
      seen[t.tag] = true
      out[#out + 1] = t.tag
    end
  end
  return out
end

--- All tags used across notes, sorted.
---@return string[]
function M.tags()
  local tags = lsp.request("snot/tags")
  if tags then
    return tags
  end
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

--- Every place `tag` is set, newest note first, then in reading order.
---@param tag string
---@return snot.Location[]
function M.tag_locations(tag)
  -- A tag is a flag, which has the value "true".
  local symbols = lsp.request("workspace/symbol", { query = "@" .. tag .. ":true" })
  if symbols then
    local locations = vim.tbl_map(function(s)
      return s.location
    end, symbols)
    return sort_locations(lsp.to_locations(locations))
  end
  local out = {}
  for _, path in ipairs(M.list()) do
    for _, t in ipairs(tags_in(path)) do
      if t.tag == tag then
        out[#out + 1] = t.loc
      end
    end
  end
  return out
end

--- Full paths of notes carrying `tag` in any scope, newest first.
---@param tag string
---@return string[]
function M.notes_with_tag(tag)
  local out = {}
  for _, loc in ipairs(M.tag_locations(tag)) do
    if out[#out] ~= loc.path then
      out[#out + 1] = loc.path
    end
  end
  return out
end

--- Links to the note `target` (a link path) in the given files, skipping links
--- from the note itself. Newest note first, then in reading order.
---@param files string[]
---@param target string
---@return snot.Location[]
local function links_to(files, target)
  table.sort(files, newest_first)
  local out = {}
  for _, path in ipairs(files) do
    if M.link_path(path) ~= target then
      local _, links, lines = format.parse_file(path)
      for _, link in ipairs(links) do
        if format.note_target(link.target) == target then
          local text = lines[link.lnum]:gsub("\r$", "")
          out[#out + 1] = { path = path, lnum = link.lnum, col = link.col, text = text }
        end
      end
    end
  end
  return out
end

--- Find links to a note, `[[path]]`, `[[path#anchor]]` or `[[path|label]]`,
--- from other notes. The language server knows unsaved buffers too; without
--- it, ripgrep finds candidate files among saved notes in the background, then
--- they are parsed so that links in code and math don't count. Calls
--- `on_done(locations)` on the main loop, newest note first, or
--- `on_done(nil, err)`.
---@param note string link path or file path of the linked note
---@param on_done fun(locations?: snot.Location[], err?: string)
function M.backlinks(note, on_done)
  local asked = lsp.request_async("snot/backlinks", { note = M.link_path(note) }, function(locations, err)
    if not locations then
      return on_done(nil, err)
    end
    on_done(sort_locations(lsp.to_locations(locations)))
  end)
  if asked then
    return
  end
  if vim.fn.executable("rg") ~= 1 then
    return on_done(nil, "ripgrep (rg) is required for backlinks")
  end
  local target = M.link_path(note)
  local root = config.get().directory
  if vim.fn.isdirectory(root) ~= 1 then
    return on_done({})
  end

  -- --no-config: a user's ripgreprc could change the output format.
  -- --no-ignore without --hidden: search exactly the files M.list() sees.
  -- stylua: ignore
  local cmd = {
    "rg", "--files-with-matches", "--null", "--no-config", "--no-ignore",
    "--glob", "*" .. config.get().extension,
    "--fixed-strings", "-e", target,
    "--", root,
  }

  local function on_exit(res)
    if res.code > 1 then -- 1 means no matches
      return on_done(nil, "rg failed: " .. vim.trim(res.stderr or ""))
    end
    local files = vim.split(res.stdout or "", "\0", { plain = true, trimempty = true })
    on_done(links_to(files, target))
  end
  vim.system(cmd, { text = true }, vim.schedule_wrap(on_exit))
end

return M
