if vim.g.loaded_snot then
  return
end
vim.g.loaded_snot = true

vim.api.nvim_create_user_command("Snot", function(o)
  require("snot.commands").run(o)
end, {
  nargs = "+",
  complete = function(arg_lead, cmdline)
    return require("snot.commands").complete(arg_lead, cmdline)
  end,
  desc = "Snot: new | daily [date] | dir | tag [tag]",
})

vim.keymap.set("n", "<Plug>(snot-new)", function()
  require("snot.commands").new()
end, { desc = "Snot: new note" })

vim.keymap.set("n", "<Plug>(snot-daily)", function()
  require("snot").goto_daily()
end, { desc = "Snot: today's daily note" })

vim.keymap.set("n", "<Plug>(snot-dir)", function()
  require("snot").open_dir()
end, { desc = "Snot: open notes directory" })

vim.keymap.set("n", "<Plug>(snot-tag)", function()
  require("snot").find_by_tag()
end, { desc = "Snot: find notes by tag" })
