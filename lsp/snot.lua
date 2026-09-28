--- The snot language server (https://github.com/zjom/snot): diagnostics,
--- formatting, go to link, references, and heading, `@id` and `@key` symbols.
---
--- plugin/snot.lua enables it; it attaches to notes when `snot` is installed
--- and the `lsp` option is on. Change it with vim.lsp.config("snot", {...}).

---@type vim.lsp.Config
return {
  cmd = { "snot", "lsp" },
  filetypes = { "snot" },
  -- Links are relative to the notes directory, so that is the root for every
  -- note, wherever the buffer's file is.
  root_dir = function(_, on_dir)
    if require("snot.lsp").enabled() then
      on_dir(require("snot.config").get().directory)
    end
  end,
  before_init = function(params, config)
    params.initializationOptions = {
      root = config.root_dir,
      extension = require("snot.config").get().extension,
    }
  end,
}
