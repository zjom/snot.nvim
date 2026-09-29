if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = true

-- `gf` on a link such as [[projects/atlas#risks|label]] opens projects/atlas:
-- link paths are relative to the notes directory and have no extension.
local cfg = require("snot.config").get()
vim.bo.path = cfg.directory:gsub("[, \\]", "\\%0") .. "," .. vim.o.path
vim.bo.suffixesadd = cfg.extension
vim.bo.includeexpr = [[substitute(v:fname, '#.*$', '', '')]]

-- Show labelled links as their label (queries/snot_inline/highlights.scm).
-- 'concealcursor' is left to the user: by default the cursor line shows the
-- raw link, so it can be edited. Override either in after/ftplugin/snot.lua.
vim.opt_local.conceallevel = 2

-- Highlighting comes from tree-sitter-snot; see :checkhealth snot.
local ts = require("snot.treesitter").start()

-- Align metadata on save (lua/snot/align.lua), unless `format_on_save` is off.
local group = vim.api.nvim_create_augroup("snot_format", { clear = false })
vim.api.nvim_clear_autocmds({ group = group, buffer = 0 })
vim.api.nvim_create_autocmd("BufWritePre", {
  group = group,
  buffer = 0,
  callback = function(ev)
    if require("snot.config").get().format_on_save then
      require("snot").format(ev.buf)
    end
  end,
  desc = "snot: align metadata",
})

vim.b.undo_ftplugin = "setlocal path< suffixesadd< includeexpr< conceallevel<"
  .. " | exe 'autocmd! snot_format * <buffer>'"
if ts then
  vim.b.undo_ftplugin = vim.b.undo_ftplugin .. " | lua vim.treesitter.stop()"
end
