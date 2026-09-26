--- Picker backends and how one is chosen: the configured picker, or the first
--- one installed, falling back to vim.ui.select. What gets picked lives in
--- snot.find.

local config = require("snot.config")
local util = require("snot.util")

local M = {}

--- A note to pick, optionally at a position within it.
---@class snot.PickItem
---@field path  string
---@field lnum? integer 1-based
---@field col?  integer 1-based byte column
---@field text? string  the line at `lnum`

---@alias snot.PickerFn fun(items: snot.PickItem[], opts: { prompt: string })
---@alias snot.SelectFn fun(items: string[], opts: { prompt: string }, on_choice: fun(item?: string))

---@class snot.Picker
---@field pick   snot.PickerFn pick a note and open it
---@field select snot.SelectFn choose one of `items`; `on_choice(nil)` when cancelled

--- How an item is shown: path relative to the notes directory, then line and text if any.
---@param item snot.PickItem
---@return string
local function label(item)
  local path = vim.fs.relpath(config.get().directory, item.path) or item.path
  if not item.lnum then
    return path
  end
  return ("%s:%d: %s"):format(path, item.lnum, vim.trim(item.text or ""))
end

---@param item snot.PickItem
local function open(item)
  local buf, err = util.open(item.path, config.get().open_cmd)
  if not buf then
    return util.fail(("could not open %s: %s"):format(item.path, err))
  end
  if item.lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, (item.col or 1) - 1 })
  end
end

---@type snot.SelectFn
local function ui_select(items, opts, on_choice)
  vim.ui.select(items, { prompt = opts.prompt }, on_choice)
end

---@type table<string, snot.Picker>
M.backends = {
  telescope = {
    pick = function(items, opts)
      local conf = require("telescope.config").values
      local topts = {}
      require("telescope.pickers")
        .new(topts, {
          prompt_title = opts.prompt,
          finder = require("telescope.finders").new_table({
            results = items,
            entry_maker = function(item)
              local display = label(item)
              -- filename/lnum/col drive telescope's default open action and previewer.
              return {
                value = item,
                display = display,
                ordinal = display,
                filename = item.path,
                lnum = item.lnum,
                col = item.col,
              }
            end,
          }),
          sorter = conf.generic_sorter(topts),
          previewer = conf.grep_previewer(topts),
        })
        :find()
    end,
    select = function(items, opts, on_choice)
      local actions = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      local topts = {}
      require("telescope.pickers")
        .new(topts, {
          prompt_title = opts.prompt,
          finder = require("telescope.finders").new_table({ results = items }),
          sorter = require("telescope.config").values.generic_sorter(topts),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              local entry = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              on_choice(entry and entry[1])
            end)
            return true
          end,
        })
        :find()
    end,
  },

  ["fzf-lua"] = {
    pick = function(items, opts)
      local fzf = require("fzf-lua")
      -- "path[:line:col:text]" entries get fzf-lua's file actions and previewer.
      local lines = vim.tbl_map(function(item)
        if not item.lnum then
          return item.path
        end
        return ("%s:%d:%d:%s"):format(item.path, item.lnum, item.col or 1, vim.trim(item.text or ""))
      end, items)
      fzf.fzf_exec(lines, {
        prompt = opts.prompt .. "> ",
        previewer = "builtin",
        actions = { default = fzf.actions.file_edit_or_qf },
      })
    end,
    select = function(items, opts, on_choice)
      require("fzf-lua").fzf_exec(items, {
        prompt = opts.prompt .. "> ",
        actions = {
          default = function(selected)
            on_choice(selected and selected[1])
          end,
        },
      })
    end,
  },

  snacks = {
    pick = function(items, opts)
      Snacks.picker.pick({
        title = opts.prompt,
        format = "file",
        items = vim.tbl_map(function(item)
          return {
            file = item.path,
            pos = item.lnum and { item.lnum, (item.col or 1) - 1 },
            line = item.text,
            text = label(item),
          }
        end, items),
      })
    end,
    select = function(items, opts, on_choice)
      Snacks.picker.select(items, { prompt = opts.prompt }, on_choice)
    end,
  },

  ["mini.pick"] = {
    pick = function(items, opts)
      MiniPick.start({
        source = {
          name = opts.prompt,
          -- `path`/`lnum`/`col` drive mini.pick's default preview and choose.
          items = vim.tbl_map(function(item)
            return { text = label(item), path = item.path, lnum = item.lnum, col = item.col }
          end, items),
        },
      })
    end,
    select = function(items, opts, on_choice)
      MiniPick.ui_select(items, { prompt = opts.prompt }, on_choice)
    end,
  },

  quickfix = {
    pick = function(items, opts)
      vim.fn.setqflist({}, " ", {
        title = opts.prompt,
        items = vim.tbl_map(function(item)
          return { filename = item.path, lnum = item.lnum, col = item.col, text = item.text }
        end, items),
      })
      vim.cmd("botright copen")
    end,
    -- The quickfix list can't make a choice.
    select = ui_select,
  },

  select = {
    pick = function(items, opts)
      vim.ui.select(items, { prompt = opts.prompt, format_item = label }, function(item)
        if item then
          open(item)
        end
      end)
    end,
    select = ui_select,
  },
}

--- Pickers tried in order when `picker` is unset. snacks and mini.pick only
--- count once set up, since they ship inside larger plugin collections.
---@type { [1]: string, [2]: fun(): boolean }[]
local detect = {
  {
    "telescope",
    function()
      return (pcall(require, "telescope"))
    end,
  },
  {
    "fzf-lua",
    function()
      return (pcall(require, "fzf-lua"))
    end,
  },
  {
    "snacks",
    function()
      return _G.Snacks ~= nil and Snacks.picker ~= nil
    end,
  },
  {
    "mini.pick",
    function()
      return _G.MiniPick ~= nil
    end,
  },
}

--- The picker `config.picker` selects, or the first one installed. A custom
--- picker function handles `pick`; choices fall back to vim.ui.select.
---@return snot.Picker
function M.get()
  local choice = config.get().picker
  if type(choice) == "function" then
    return { pick = choice, select = ui_select }
  end
  if choice then
    return M.backends[choice]
  end
  for _, d in ipairs(detect) do
    if d[2]() then
      return M.backends[d[1]]
    end
  end
  return M.backends.select
end

return M
