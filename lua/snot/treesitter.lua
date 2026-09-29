--- Tree-sitter parsers for Simple Note Format.
---
--- The grammar repo holds two parsers, like tree-sitter-markdown: `snot` for
--- blocks and `snot_inline` for inline content, injected into `snot`.

local M = {}

local url = "https://github.com/zjom/tree-sitter-snot"

M.parsers = {
  snot = {
    install_info = { url = url, location = "tree-sitter-snot", queries = "tree-sitter-snot/queries" },
    requires = { "snot_inline" },
  },
  snot_inline = {
    install_info = { url = url, location = "tree-sitter-snot-inline", queries = "tree-sitter-snot-inline/queries" },
  },
}

--- Add the parsers to nvim-treesitter (main branch), so `:TSInstall snot` works.
function M.register()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    return
  end
  for lang, info in pairs(M.parsers) do
    parsers[lang] = vim.deepcopy(info)
  end
end

--- Whether the parser for `lang` is installed.
---@param lang string
---@return boolean
function M.has_parser(lang)
  -- Since Nvim 0.11 language.add() returns nil for a missing parser instead of
  -- throwing, so check the result as well as the pcall.
  local ok, added = pcall(vim.treesitter.language.add, lang)
  return ok and added == true
end

--- Highlight the current buffer with tree-sitter, if the parser is installed.
---@return boolean started
function M.start()
  return M.has_parser("snot") and (pcall(vim.treesitter.start))
end

return M
