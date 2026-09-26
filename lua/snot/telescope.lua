--- Telescope pickers. Only loaded when a picker is used

local config = require("snot.config")
local store = require("snot.store")
local util = require("snot.util")

local M = {}

--- Telescope picker over all tags; calls `on_pick(tag)` with the chosen one.
---@param on_pick fun(tag: string)
---@param opts table telescope picker options
local function pick_tag(on_pick, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new(opts, {
      prompt_title = "Note tags",
      finder = finders.new_table({ results = store.tags() }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            -- Open the next picker after this one has fully closed.
            vim.schedule(function()
              on_pick(entry[1])
            end)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Find notes by tag. Without a tag, pick one from all tags first.
---@param tag? string
---@param opts? table telescope picker options (layout_config, etc.)
function M.find_by_tag(tag, opts)
  if not pcall(require, "telescope") then
    return util.fail("telescope.nvim is required for tag search")
  end
  opts = vim.tbl_extend("force", { cwd = config.get().directory }, opts or {})

  if tag == nil or tag == "" then
    return pick_tag(function(t)
      M.find_by_tag(t, opts)
    end, opts)
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")

  -- Relative to cwd where possible; daily notes may live in a subfolder or elsewhere.
  local names = vim.tbl_map(function(path)
    return vim.fs.relpath(opts.cwd, path) or path
  end, store.notes_with_tag(tag))
  if #names == 0 then
    vim.notify(("snot: no notes tagged %q"):format(tag), vim.log.levels.INFO)
    return
  end

  pickers
    .new(opts, {
      prompt_title = ("Notes tagged %q"):format(tag),
      finder = finders.new_table({ results = names, entry_maker = make_entry.gen_from_file(opts) }),
      sorter = conf.file_sorter(opts),
      previewer = conf.file_previewer(opts),
    })
    :find()
end

return M
