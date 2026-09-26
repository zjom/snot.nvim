-- Load the plugin from this checkout, as a plugin manager would, so :Snot exists.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.runtime("plugin/snot.lua")
-- nvim -l leaves filetype detection off.
vim.cmd("filetype plugin on")
