local snot = require("snot")
local util = require("snot.util")

---@param path string
---@param lines string[]
local function write(path, lines)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

--- Call `fn` with vim.notify silenced, returning its results.
---@param fn function
local function quietly(fn)
  local notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function() end
  local ret = vim.F.pack_len(pcall(fn))
  vim.notify = notify
  assert(ret[1], ret[2])
  return select(2, vim.F.unpack_len(ret))
end

describe("util", function()
  it("slugifies titles", function()
    assert.are.equal("hello-world", util.slugify("Hello, World!"))
    assert.are.equal("untitled", util.slugify("!!!"))
  end)

  it("renders templates, leaving missing values empty", function()
    assert.are.equal("a=1 b=", util.render("a=${a} b=${b}", { a = 1 }))
  end)

  it("escapes TOML strings", function()
    assert.are.equal([["say \"hi\" \\"]], util.toml_string([[say "hi" \]]))
  end)

  it("normalizes tags", function()
    assert.are.same({ "a", "b", "c" }, util.normalize_tags("a, b c"))
    assert.are.same({ "x" }, util.normalize_tags({ "x" }))
    assert.are.same({}, util.normalize_tags(nil))
  end)

  it("resolves relative dates", function()
    assert.is_nil(util.resolve_date("", "%Y%m%d"))
    assert.are.equal(os.date("%Y%m%d"), util.resolve_date("today", "%Y%m%d"))
    assert.are.equal(util.resolve_date("-1", "%Y%m%d"), util.resolve_date("yesterday", "%Y%m%d"))
    assert.are.equal("20240101", util.resolve_date("20240101", "%Y%m%d"))
  end)
end)

describe("config", function()
  after_each(function()
    vim.g.snot = nil
    snot.setup()
  end)

  it("reads vim.g.snot when setup() is not called", function()
    -- A fresh copy of the module, as if nothing had called setup() yet.
    local original = package.loaded["snot.config"]
    package.loaded["snot.config"] = nil
    vim.g.snot = { directory = "/tmp/from-g" }
    local fresh = require("snot.config")
    package.loaded["snot.config"] = original
    assert.are.equal("/tmp/from-g", fresh.get().directory)
  end)

  it("does not accumulate state across setup() calls", function()
    snot.setup({ templates = { extra = "x" } })
    snot.setup({})
    assert.is_nil(snot.config().templates.extra)
    assert.is_not_nil(snot.config().templates.default)
  end)

  it("falls back to defaults on invalid options", function()
    quietly(function()
      snot.setup({ directory = 42 })
    end)
    assert.are.equal(vim.fs.normalize("~/notes"), snot.directory())
  end)
end)

describe("notes", function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    snot.setup({ directory = dir })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("creates an unsaved, unmodified note from the template", function()
    local buf, path = snot.create_note({ title = "My Idea", tags = "a b", content = "body", date = "20240102" })
    assert.are.equal(vim.fs.joinpath(dir, "20240102__my-idea.md"), path)
    assert.are.same({
      "+++",
      'title = "My Idea"',
      "date = 20240102",
      'tags = ["a", "b"]',
      "+++",
      "",
      "# My Idea",
      "",
      "body",
    }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.is_false(vim.bo[buf].modified)
    assert.is_nil(vim.uv.fs_stat(path))
  end)

  it("requires a title for non-daily notes", function()
    local buf, err = quietly(snot.create_note)
    assert.is_nil(buf)
    assert.are.equal("a title is required for non-daily notes", err)
  end)

  it("opens an existing daily note as-is", function()
    write(vim.fs.joinpath(dir, "20240103.md"), { "existing" })
    local buf = snot.goto_daily({ date = "20240103" })
    assert.are.same({ "existing" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("does not clobber an existing note with the same title", function()
    write(vim.fs.joinpath(dir, "20240104__dup.md"), { "old" })
    local _, path = snot.create_note({ title = "dup", date = "20240104" })
    assert.are_not.equal(vim.fs.joinpath(dir, "20240104__dup.md"), path)
  end)

  it("indexes tags from front matter", function()
    write(vim.fs.joinpath(dir, "20240101__a.md"), { "+++", 'tags = ["x", "y"]', "+++" })
    write(vim.fs.joinpath(dir, "20240102__b.md"), { "+++", 'tags = ["y"]', "+++" })
    write(vim.fs.joinpath(dir, "20240103.md"), { "no front matter", 'tags = ["z"]' })
    assert.are.same({ "x", "y" }, snot.tags())
    assert.are.same({
      vim.fs.joinpath(dir, "20240102__b.md"),
      vim.fs.joinpath(dir, "20240101__a.md"),
    }, snot.notes_with_tag("y"))
  end)
end)

describe("daily_directory", function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("resolves relative paths inside the notes directory", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    assert.are.equal(vim.fs.joinpath(dir, "daily"), snot.config().daily_directory)
    snot.setup({ directory = dir, daily_directory = "/tmp/elsewhere" })
    assert.are.equal("/tmp/elsewhere", snot.config().daily_directory)
  end)

  it("creates daily notes there, and other notes in the root", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    local _, daily = snot.goto_daily({ date = "20240107" })
    assert.are.equal(vim.fs.joinpath(dir, "daily", "20240107.md"), daily)
    assert.are.equal(1, vim.fn.isdirectory(vim.fs.joinpath(dir, "daily")))
    local _, note = snot.create_note({ title = "x", date = "20240107" })
    assert.are.equal(vim.fs.joinpath(dir, "20240107__x.md"), note)
  end)

  it("completes and indexes daily notes from there", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    vim.fn.mkdir(vim.fs.joinpath(dir, "daily"), "p")
    write(vim.fs.joinpath(dir, "daily", "20240108.md"), { "+++", 'tags = ["d"]', "+++" })
    write(vim.fs.joinpath(dir, "20240109.md"), { "" })
    assert.are.same({ "20240108" }, require("snot.store").daily_dates())
    assert.are.same({ vim.fs.joinpath(dir, "daily", "20240108.md") }, snot.notes_with_tag("d"))
  end)
end)

describe(":Snot", function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    snot.setup({ directory = dir })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("is defined by plugin/", function()
    assert.is_not_nil(vim.api.nvim_get_commands({})["Snot"])
  end)

  it("completes subcommands and daily dates", function()
    write(vim.fs.joinpath(dir, "20240105.md"), { "" })
    write(vim.fs.joinpath(dir, "20240105__note.md"), { "" })
    assert.are.same({ "daily", "dir" }, vim.fn.getcompletion("Snot d", "cmdline"))
    assert.are.same({ "20240105" }, vim.fn.getcompletion("Snot daily 2024", "cmdline"))
    assert.are.same({ "today", "tomorrow" }, vim.fn.getcompletion("Snot daily to", "cmdline"))
  end)

  it("creates a note with the rest of the line as its title", function()
    vim.cmd("Snot new  Two  Spaces ")
    assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), "__two-spaces.md"))
    assert.are.equal("# Two  Spaces", vim.api.nvim_buf_get_lines(0, 6, 7, false)[1])
  end)

  it("honours window modifiers", function()
    local wins = #vim.api.nvim_tabpage_list_wins(0)
    vim.cmd("vertical Snot daily 20240106")
    assert.are.equal(wins + 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), "20240106.md"))
  end)
end)
