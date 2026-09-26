--- Note searches, shown with the picker from snot.picker.

local picker = require("snot.picker")
local store = require("snot.store")
local util = require("snot.util")

local M = {}

--- Pick from the places `tag` is set. Without a tag, choose one from all tags first.
---@param tag? string
function M.by_tag(tag)
  if tag == nil or tag == "" then
    local tags = store.tags()
    if #tags == 0 then
      vim.notify("snot: no tagged notes", vim.log.levels.INFO)
      return
    end
    return picker.get().select(tags, { prompt = "Note tags" }, function(t)
      if t then
        -- Open the next picker after this one has fully closed.
        vim.schedule(function()
          M.by_tag(t)
        end)
      end
    end)
  end

  tag = tag:gsub("^@", "")
  local items = store.tag_locations(tag)
  if #items == 0 then
    vim.notify(("snot: no notes tagged %q"):format(tag), vim.log.levels.INFO)
    return
  end
  picker.get().pick(items, { prompt = "Tagged @" .. tag })
end

--- Pick from the notes linking to `note` (link path or file path; default: the current note).
---@param note? string
function M.backlinks(note)
  if note == nil or note == "" then
    note = vim.api.nvim_buf_get_name(0)
    if not store.is_note(note) then
      return util.fail("the current buffer is not a note")
    end
  end
  local target = store.link_path(note)
  store.backlinks(target, function(items, err)
    if not items then
      return util.fail(err --[[@as string]])
    end
    if #items == 0 then
      vim.notify(("snot: no notes link to %s"):format(target), vim.log.levels.INFO)
      return
    end
    picker.get().pick(items, { prompt = ("Links to %s"):format(target) })
  end)
end

return M
