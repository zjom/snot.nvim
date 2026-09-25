rockspec_format = "3.0"
package = "snot.nvim"
version = "scm-1"
license = "Unlicense"

source = {
  url = "git+https://github.com/zjom/snot.nvim",
}

description = {
  summary = "Simple dated markdown notes for Neovim",
  homepage = "https://github.com/zjom/snot.nvim",
}

dependencies = {
  "lua == 5.1",
}

test_dependencies = {
  "nlua",
}

build = {
  type = "builtin",
  copy_directories = {
    "doc",
    "plugin",
  },
}
