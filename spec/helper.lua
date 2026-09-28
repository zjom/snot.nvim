-- Load the plugin from this checkout, as a plugin manager would, so :Snot exists.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.runtime("plugin/snot.lua")
-- nvim -l leaves filetype detection off.
vim.cmd("filetype plugin on")

-- The language server is used when `snot` is on PATH. SNOT_TEST_LSP=0 tests
-- the fallbacks with it installed.
if os.getenv("SNOT_TEST_LSP") == "0" then
  vim.lsp.config("snot", { cmd = { "snot-disabled-in-tests" } })
end
