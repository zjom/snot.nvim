# snot.nvim

Simple dated markdown notes for Neovim.

- Daily notes: `~/notes/20240102.md`
- Titled notes: `~/notes/20240102__my-idea.md`
- New notes open pre-filled from a template and aren't written until you save.
- Tags in TOML front matter, searchable with [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional).

Requires Neovim 0.11+.

## Installation

With `vim.pack`:

```lua
vim.pack.add({ "https://github.com/zjom/snot.nvim" })
```

With lazy.nvim:

```lua
{ "zjom/snot.nvim" }
```

No `setup()` call is needed, and the plugin loads lazily on its own.

## Configuration

Set `vim.g.snot` before first use (these are the defaults):

```lua
vim.g.snot = {
  directory = "~/notes",
  daily_directory = nil, -- e.g. "daily" for ~/notes/daily; unset keeps daily notes in `directory`
  date_format = "%Y%m%d",
  extension = ".md",
  open_cmd = "edit", -- or "vsplit", "tabedit", "botright split", ...
}
```

`require("snot").setup({ ... })` takes the same table if you prefer that.
See `:help snot-templates` to customise the note template.

## Usage

| Command              | Action                                                             |
| -------------------- | ------------------------------------------------------------------ |
| `:Snot new [title]`  | New note (prompts for a title if none given)                       |
| `:Snot daily [date]` | Daily note: `today`, `yesterday`, `tomorrow`, `-3`, `+1` or a date |
| `:Snot dir`          | Open the notes directory                                           |
| `:Snot tag [tag]`    | Find notes by tag with Telescope                                   |

Window modifiers work too: `:vertical Snot daily`, `:tab Snot new Idea`.

### Mappings

No mappings are set by default. Use the `<Plug>` mappings or the Lua API:

```lua
vim.keymap.set("n", "<leader>pd", "<Plug>(snot-daily)")
vim.keymap.set("n", "<leader>pn", "<Plug>(snot-new)")
vim.keymap.set("n", "<leader>pt", "<Plug>(snot-tag)")

vim.keymap.set("n", "<leader>pf", function()
  require("telescope.builtin").find_files({ cwd = require("snot").directory() })
end)
```

See `:help snot` for the full Lua API.

## Development

```sh
luarocks test --local   # runs spec/ with busted via nlua
# nix users should run busted in the devshell instead
busted
stylua --check .
```
