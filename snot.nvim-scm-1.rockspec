rockspec_format = "3.0"
package = "snot.nvim"
version = "scm-1"

source = {
  url = "git+https://github.com/zjom/snot.nvim",
}

description = {
  summary = "Simple dated notes in Simple Note Format for Neovim",
  homepage = "https://github.com/zjom/snot.nvim",
  license = "Unlicense",
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
    "ftplugin",
    "plugin",
    "syntax",
  },
}
