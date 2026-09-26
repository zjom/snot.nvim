--- The :Snot command and its subcommands.

local M = {}

--- Map command modifiers (:vertical, :tab, :botright, ...) to an open command.
--- Returns nil when no window-placement modifier was given, so config.open_cmd applies.
---@param o vim.api.keyset.create_user_command.command_args
---@return string?
local function cmd_from_mods(o)
  local s = o.smods
  if s.tab >= 0 or s.vertical or s.horizontal or s.split ~= "" then
    return o.mods .. " split"
  end
end

---@param items string[]
---@param lead string
---@return string[]
local function filter_prefix(items, lead)
  return vim.tbl_filter(function(i)
    return vim.startswith(i, lead)
  end, items)
end

--- Create a note, prompting for a title when none is given.
---@param title? string
---@param cmd? string
function M.new(title, cmd)
  local function go(t)
    if t and vim.trim(t) ~= "" then
      require("snot").create_note({ title = vim.trim(t), cmd = cmd })
    end
  end
  if title and title ~= "" then
    go(title)
  else
    vim.ui.input({ prompt = "Note title: " }, go)
  end
end

---@class snot.Subcommand
---@field impl fun(args: string, o: vim.api.keyset.create_user_command.command_args)
---@field complete? fun(lead: string): string[]
---@field desc string

---@type table<string, snot.Subcommand>
local subcommands = {
  new = {
    desc = "new note (prompts for a title if none given)",
    impl = function(args, o)
      M.new(args, cmd_from_mods(o))
    end,
  },
  daily = {
    desc = "open a daily note (today, yesterday, tomorrow, -N, +N or a date)",
    impl = function(args, o)
      local date = require("snot.util").resolve_date(args, require("snot.config").get().date_format)
      require("snot").goto_daily({ date = date, cmd = cmd_from_mods(o) })
    end,
    complete = function(lead)
      local items = vim.list_extend({ "today", "yesterday", "tomorrow" }, require("snot.store").daily_dates())
      return filter_prefix(items, lead)
    end,
  },
  dir = {
    desc = "open the notes directory",
    impl = function(_, o)
      require("snot").open_dir({ cmd = cmd_from_mods(o) })
    end,
  },
  tag = {
    desc = "find where a tag is set (pick a tag if none given)",
    impl = function(args)
      require("snot").find_by_tag(args)
    end,
    complete = function(lead)
      return filter_prefix(require("snot.store").tags(), lead)
    end,
  },
  backlinks = {
    desc = "find notes linking to a note (default: the current one)",
    impl = function(args)
      require("snot").find_backlinks(args)
    end,
    complete = function(lead)
      local store = require("snot.store")
      return filter_prefix(vim.tbl_map(store.link_path, store.list()), lead)
    end,
  },
}

---@return string[]
local function subcommand_names()
  local names = vim.tbl_keys(subcommands)
  table.sort(names)
  return names
end

---@param o vim.api.keyset.create_user_command.command_args
function M.run(o)
  local name, args = o.args:match("^%s*(%S+)%s*(.-)%s*$")
  local sub = subcommands[name or ""]
  if not sub then
    local usage = "usage: :Snot {" .. table.concat(subcommand_names(), "|") .. "} [args]"
    local msg = name and ("unknown subcommand %q; %s"):format(name, usage) or usage
    vim.notify("snot: " .. msg, vim.log.levels.ERROR)
    return
  end
  sub.impl(args, o)
end

---@param arg_lead string
---@param cmdline string
---@return string[]
function M.complete(arg_lead, cmdline)
  local name, sub_lead = cmdline:match("%f[%w]Snot!?%s+(%S+)%s+(.*)$")
  if name then
    local sub = subcommands[name]
    return sub and sub.complete and sub.complete(sub_lead) or {}
  end
  if cmdline:match("%f[%w]Snot!?%s+%S*$") then
    return filter_prefix(subcommand_names(), arg_lead)
  end
  return {}
end

return M
