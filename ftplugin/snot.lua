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

vim.b.undo_ftplugin = "setlocal path< suffixesadd< includeexpr<"
