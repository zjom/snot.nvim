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

  it("hands tagged notes to the configured picker", function()
    write(vim.fs.joinpath(dir, "20240101__a.md"), { "+++", 'tags = ["x"]', "+++" })
    local got
    snot.setup({
      directory = dir,
      picker = function(items, opts)
        got = { items = items, prompt = opts.prompt }
      end,
    })
    vim.cmd("Snot tag x")
    assert.are.equal('Notes tagged "x"', got.prompt)
    assert.are.same({ { path = vim.fs.joinpath(dir, "20240101__a.md") } }, got.items)
  end)

  it("chooses a tag first when none is given", function()
    write(vim.fs.joinpath(dir, "20240101__a.md"), { "+++", 'tags = ["x", "y"]', "+++" })
    snot.setup({ directory = dir, picker = "quickfix" })
    local select = vim.ui.select
    local offered
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(items, _, on_choice)
      offered = items
      on_choice("y")
    end
    vim.cmd("Snot tag")
    vim.ui.select = select
    assert.are.same({ "x", "y" }, offered)
    assert(vim.wait(1000, function()
      return #vim.fn.getqflist() > 0
    end))
    assert.are.equal('Notes tagged "y"', vim.fn.getqflist({ title = 0 }).title)
    vim.cmd("cclose")
    vim.fn.setqflist({}, "f")
    vim.fn.setqflist({}, "f")
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

describe("backlinks", function()
  local dir

  --- Run store.backlinks and wait for its result.
  ---@param note string
  local function backlinks(note)
    local result, err
    snot.backlinks(note, function(r, e)
      result, err = r or false, e
    end)
    assert(
      vim.wait(5000, function()
        return result ~= nil
      end),
      "timed out waiting for backlinks"
    )
    return result, err
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(vim.fs.joinpath(dir, "daily"), "p")
    snot.setup({ directory = dir, daily_directory = "daily" })
    write(vim.fs.joinpath(dir, "20240101__target.md"), { "links to self: [[20240101__target]]" })
    write(vim.fs.joinpath(dir, "20240102__a.md"), { "intro", "see [[20240101__target]]" })
    write(vim.fs.joinpath(dir, "20240103__b.md"), { "aliased [[20240101__target|the target]]" })
    write(vim.fs.joinpath(dir, "20240104__c.md"), { "not a link: [[20240101__target-2]] or 20240101__target" })
    write(vim.fs.joinpath(dir, "daily", "20240105.md"), { "- [[20240101__target]] from a daily" })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("finds plain and aliased links, newest first, skipping the note itself", function()
    local found = assert(backlinks("20240101__target"))
    assert.are.same({
      {
        path = vim.fs.joinpath(dir, "daily", "20240105.md"),
        lnum = 1,
        col = 3,
        text = "- [[20240101__target]] from a daily",
      },
      {
        path = vim.fs.joinpath(dir, "20240103__b.md"),
        lnum = 1,
        col = 9,
        text = "aliased [[20240101__target|the target]]",
      },
      { path = vim.fs.joinpath(dir, "20240102__a.md"), lnum = 2, col = 5, text = "see [[20240101__target]]" },
    }, found)
  end)

  it("accepts a path as well as a stem", function()
    assert.are.equal(3, #assert(backlinks(vim.fs.joinpath(dir, "20240101__target.md"))))
  end)

  it("returns nothing for an unlinked note", function()
    assert.are.same({}, backlinks("20240104__c"))
  end)

  it("hands the links to the configured picker", function()
    local got
    snot.setup({
      directory = dir,
      daily_directory = "daily",
      picker = function(items, opts)
        got = { items = items, prompt = opts.prompt }
      end,
    })
    vim.cmd.edit(vim.fs.joinpath(dir, "20240101__target.md"))
    vim.cmd("Snot backlinks")
    assert(vim.wait(5000, function()
      return got ~= nil
    end))
    assert.are.equal("Links to 20240101__target", got.prompt)
    assert.are.equal(3, #got.items)
  end)

  it("can fill the quickfix list", function()
    snot.setup({ directory = dir, daily_directory = "daily", picker = "quickfix" })
    vim.cmd("Snot backlinks 20240101__target")
    assert(vim.wait(5000, function()
      return #vim.fn.getqflist() > 0
    end))
    local qf = vim.fn.getqflist()
    assert.are.equal(3, #qf)
    assert.are.equal(vim.fs.joinpath(dir, "daily", "20240105.md"), vim.api.nvim_buf_get_name(qf[1].bufnr))
    vim.cmd("cclose")
  end)

  it("refuses to run outside a note", function()
    local _, err = quietly(snot.find_backlinks)
    assert.are.equal("the current buffer is not a note", err)
  end)

  it("rejects unknown pickers", function()
    quietly(function()
      snot.setup({ directory = dir, picker = "nope" })
    end)
    assert.is_nil(snot.config().picker)
  end)
end)
