# snot.nvim

Simple dated notes for Neovim, written in the [Simple Note Format](NOTE_SPEC.md):
plain text where headings, lists, tasks, `@metadata` and `[[links]]` are all
greppable.

```
@created:2024-01-02 @work

# My idea @project:atlas

- [ ] Draft the plan @due:2024-01-09 @urgent
- See [[daily/20240102]] and [[projects/atlas#risks|the risk list]]
```

- Daily notes: `~/notes/20240102.snot`
- Titled notes: `~/notes/20240102__my-idea.snot`
- New notes open pre-filled from a template and aren't written until you save.
- Tags are `@flags` in any heading, list item, table row or the file itself; find where one is set in your picker of choice.
- `[[path]]` links between notes, relative to the notes directory, with backlinks in your picker (needs [ripgrep](https://github.com/BurntSushi/ripgrep)).
- Tree-sitter highlighting via [tree-sitter-snot](https://github.com/zjom/tree-sitter-snot), and `gf` to follow a link.

snot is opinionated: notes are always Simple Note Format. Only the file extension is configurable.

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

For highlighting, install the tree-sitter parsers. snot registers them with
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (main branch), so:

```vim
:TSInstall snot
```

installs `snot` and `snot_inline` along with their queries. snot starts tree-sitter in note buffers itself.

Links with a label, like `[[projects/atlas#risks|risks]]`, are shown as just the label. snot sets `conceallevel=2` in notes; the cursor line still shows the full link (see `'concealcursor'`). Override either in `after/ftplugin/snot.lua`.

## Configuration

Set `vim.g.snot` before first use (these are the defaults):

```lua
vim.g.snot = {
  directory = "~/notes",
  daily_directory = nil, -- e.g. "daily" for ~/notes/daily; must be inside `directory`
  date_format = "%Y%m%d",
  extension = ".snot",
  open_cmd = "edit", -- or "vsplit", "tabedit", "botright split", ...
  picker = nil, -- tag/backlinks picker: "telescope", "fzf-lua", "snacks", "mini.pick", "quickfix",
                -- "select" or a function; unset uses the first one installed
}
```

`require("snot").setup({ ... })` takes the same table if you prefer that.
See `:help snot-templates` to customise the note template.

## Usage

| Command                  | Action                                                             |
| ------------------------ | ------------------------------------------------------------------ |
| `:Snot new [title]`      | New note (prompts for a title if none given)                       |
| `:Snot daily [date]`     | Daily note: `today`, `yesterday`, `tomorrow`, `-3`, `+1` or a date |
| `:Snot dir`              | Open the notes directory                                           |
| `:Snot tag [tag]`        | Find where a tag is set (pick a tag if none given)                 |
| `:Snot backlinks [note]` | Find notes linking to a note (default: the current one)            |

Window modifiers work too: `:vertical Snot daily`, `:tab Snot new Idea`.

### Mappings

No mappings are set by default. Use the `<Plug>` mappings or the Lua API:

```lua
vim.keymap.set("n", "<leader>pd", "<Plug>(snot-daily)")
vim.keymap.set("n", "<leader>pn", "<Plug>(snot-new)")
vim.keymap.set("n", "<leader>pt", "<Plug>(snot-tag)")
vim.keymap.set("n", "<leader>pb", "<Plug>(snot-backlinks)")

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
