local format = require("snot.format")
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
  it("slugifies titles like headings, dropping tokens", function()
    assert.are.equal("hello-world", util.slugify("Hello, World!"))
    assert.are.equal("open-risks-q4", util.slugify("Open Risks (Q4) @status:open"))
    assert.are.equal("snake-case", util.slugify("snake_case"))
    assert.are.equal("untitled", util.slugify("!!!"))
  end)

  it("renders templates, leaving missing values empty", function()
    assert.are.equal("a=1 b=", util.render("a=${a} b=${b}", { a = 1 }))
  end)

  it("normalizes tags to metadata keys", function()
    assert.are.same({ "a", "b", "c" }, util.normalize_tags("a, @b C"))
    assert.are.same({ "x" }, util.normalize_tags({ "x" }))
    assert.are.same({}, util.normalize_tags(nil))
    local tags, err = util.normalize_tags("ok 1x")
    assert.is_nil(tags)
    assert.matches("invalid tag", err)
  end)

  it("resolves relative dates", function()
    assert.is_nil(util.resolve_date("", "%Y%m%d"))
    assert.are.equal(os.date("%Y%m%d"), util.resolve_date("today", "%Y%m%d"))
    assert.are.equal(util.resolve_date("-1", "%Y%m%d"), util.resolve_date("yesterday", "%Y%m%d"))
    assert.are.equal("20240101", util.resolve_date("20240101", "%Y%m%d"))
  end)
end)

describe("format", function()
  ---@param lines string[]
  local function tokens(lines)
    return vim.tbl_map(function(t)
      return { t.key, t.values, t.lnum, t.col }
    end, (format.parse(lines)))
  end

  it("reads each token form", function()
    assert.are.same({
      { "urgent", { "true" }, 1, 1 },
      { "due", { "2026-10-01" }, 1, 9 },
      { "person", { "bob", "priya" }, 1, 25 },
      { "empty", {}, 1, 46 },
      { "client", { "Acme, Corp" }, 2, 3 },
    }, tokens({ "@urgent @due:2026-10-01 @person:[bob, priya] @empty:[]", "- @client:[Acme\\, Corp, ]" }))
  end)

  it("only recognises tokens at the start of a word", function()
    assert.are.same({}, tokens({ "bob@example.com @Bob @1x \\@esc *@bold*" }))
    assert.are.same({}, tokens({ "@open:[unclosed" }))
  end)

  it("skips code, math and links", function()
    assert.are.same(
      { { "real", { "true" }, 8, 1 } },
      tokens({
        "`@a` ``b `@b` c`` $@c$ [[x|@d]]",
        "```python",
        "@e",
        "```",
        "$$",
        "@f",
        "$$",
        "@real",
      })
    )
    assert.are.same({ { "real", { "true" }, 5, 1 } }, tokens({ "````", "```", "@a", "````", "@real" }))
  end)

  it("ends values at | in table rows", function()
    assert.are.same(
      { { "owner", { "bob" }, 1, 3 }, { "id", { "beta" }, 1, 14 } },
      tokens({ "| @owner:bob|@id:beta |" })
    )
  end)

  it("reads links and their targets", function()
    local _, links = format.parse({ "see [[ projects/atlas#risks | risk list ]] and [[a\\|b]]" })
    assert.are.same({
      { target = "projects/atlas#risks", label = "risk list", lnum = 1, col = 5 },
      { target = "a|b", lnum = 1, col = 48 },
    }, links)
    assert.are.same({ "projects/atlas", "risks" }, { format.note_target("projects/atlas#risks") })
    assert.is_nil(format.note_target("https://example.com/a"))
    assert.is_nil(format.note_target("#decisions"))
    assert.is_nil(format.note_target("img/wb.png"))
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
    assert.are.equal(vim.fs.joinpath(dir, "20240102__my-idea.snot"), path)
    assert.are.same({
      "@created:" .. os.date("%Y-%m-%d") .. " @a @b",
      "",
      "# My Idea",
      "",
      "body",
    }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.is_false(vim.bo[buf].modified)
    assert.is_nil(vim.uv.fs_stat(path))
    assert.are.equal("snot", vim.bo[buf].filetype)
  end)

  it("rejects tags that aren't metadata keys", function()
    local buf, err = quietly(function()
      return snot.create_note({ title = "x", tags = "a b!" })
    end)
    assert.is_nil(buf)
    assert.matches("invalid tag", err)
  end)

  it("requires a title for non-daily notes", function()
    local buf, err = quietly(snot.create_note)
    assert.is_nil(buf)
    assert.are.equal("a title is required for non-daily notes", err)
  end)

  it("opens an existing daily note as-is", function()
    write(vim.fs.joinpath(dir, "20240103.snot"), { "existing" })
    local buf = snot.goto_daily({ date = "20240103" })
    assert.are.same({ "existing" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("does not clobber an existing note with the same title", function()
    write(vim.fs.joinpath(dir, "20240104__dup.snot"), { "old" })
    local _, path = snot.create_note({ title = "dup", date = "20240104" })
    assert.are_not.equal(vim.fs.joinpath(dir, "20240104__dup.snot"), path)
  end)

  it("indexes flags in any scope as tags", function()
    write(vim.fs.joinpath(dir, "20240101__a.snot"), { "@x @y", "# A", "- item @y @due:2024-01-01" })
    write(vim.fs.joinpath(dir, "20240102__b.snot"), { "# B @y:true" })
    write(vim.fs.joinpath(dir, "20240103.snot"), { "`@z`", "```", "@z", "```", "mail@w.com" })
    write(vim.fs.joinpath(dir, "20240104__c.md"), { "@other-extension" })
    vim.fn.mkdir(vim.fs.joinpath(dir, "projects"))
    write(vim.fs.joinpath(dir, "projects", "atlas.snot"), { "@nested" })
    assert.are.same({ "nested", "x", "y" }, snot.tags())
    assert.are.same({
      vim.fs.joinpath(dir, "20240102__b.snot"),
      vim.fs.joinpath(dir, "20240101__a.snot"),
    }, snot.notes_with_tag("y"))
    assert.are.same({
      { path = vim.fs.joinpath(dir, "20240102__b.snot"), lnum = 1, col = 5, text = "# B @y:true" },
      { path = vim.fs.joinpath(dir, "20240101__a.snot"), lnum = 1, col = 4, text = "@x @y" },
      { path = vim.fs.joinpath(dir, "20240101__a.snot"), lnum = 3, col = 8, text = "- item @y @due:2024-01-01" },
    }, snot.tag_locations("y"))
  end)

  it("hands tag locations to the configured picker", function()
    write(vim.fs.joinpath(dir, "20240101__a.snot"), { "", "text @x" })
    local got
    snot.setup({
      directory = dir,
      picker = function(items, opts)
        got = { items = items, prompt = opts.prompt }
      end,
    })
    vim.cmd("Snot tag @x")
    assert.are.equal("Tagged @x", got.prompt)
    assert.are.same(
      { { path = vim.fs.joinpath(dir, "20240101__a.snot"), lnum = 2, col = 6, text = "text @x" } },
      got.items
    )
  end)

  it("chooses a tag first when none is given", function()
    write(vim.fs.joinpath(dir, "20240101__a.snot"), { "@x @y" })
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
    assert.are.equal("Tagged @y", vim.fn.getqflist({ title = 0 }).title)
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

  it("resolves inside the notes directory, and must stay there", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    assert.are.equal(vim.fs.joinpath(dir, "daily"), snot.config().daily_directory)
    for _, outside in ipairs({ "/tmp/elsewhere", "~/daily", "../daily" }) do
      quietly(function()
        snot.setup({ directory = dir, daily_directory = outside })
      end)
      assert.is_nil(snot.config().daily_directory)
    end
  end)

  it("creates daily notes there, and other notes in the root", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    local _, daily = snot.goto_daily({ date = "20240107" })
    assert.are.equal(vim.fs.joinpath(dir, "daily", "20240107.snot"), daily)
    assert.are.equal(1, vim.fn.isdirectory(vim.fs.joinpath(dir, "daily")))
    local _, note = snot.create_note({ title = "x", date = "20240107" })
    assert.are.equal(vim.fs.joinpath(dir, "20240107__x.snot"), note)
  end)

  it("completes and indexes daily notes from there", function()
    snot.setup({ directory = dir, daily_directory = "daily" })
    vim.fn.mkdir(vim.fs.joinpath(dir, "daily"), "p")
    write(vim.fs.joinpath(dir, "daily", "20240108.snot"), { "@d" })
    write(vim.fs.joinpath(dir, "20240109.snot"), { "" })
    assert.are.same({ "20240108" }, require("snot.store").daily_dates())
    assert.are.same({ vim.fs.joinpath(dir, "daily", "20240108.snot") }, snot.notes_with_tag("d"))
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
    write(vim.fs.joinpath(dir, "20240105.snot"), { "" })
    write(vim.fs.joinpath(dir, "20240105__note.snot"), { "" })
    assert.are.same({ "daily", "dir" }, vim.fn.getcompletion("Snot d", "cmdline"))
    assert.are.same({ "20240105" }, vim.fn.getcompletion("Snot daily 2024", "cmdline"))
    assert.are.same({ "today", "tomorrow" }, vim.fn.getcompletion("Snot daily to", "cmdline"))
  end)

  it("creates a note with the rest of the line as its title", function()
    vim.cmd("Snot new  Two  Spaces ")
    assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), "__two-spaces.snot"))
    assert.are.equal("# Two  Spaces", vim.api.nvim_buf_get_lines(0, 2, 3, false)[1])
  end)

  it("honours window modifiers", function()
    local wins = #vim.api.nvim_tabpage_list_wins(0)
    vim.cmd("vertical Snot daily 20240106")
    assert.are.equal(wins + 1, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_true(vim.endswith(vim.api.nvim_buf_get_name(0), "20240106.snot"))
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
    write(vim.fs.joinpath(dir, "20240101__target.snot"), { "links to self: [[20240101__target]]" })
    write(vim.fs.joinpath(dir, "20240102__a.snot"), { "intro", "see [[20240101__target]]" })
    write(vim.fs.joinpath(dir, "20240103__b.snot"), { "labelled [[ 20240101__target#risks | the target ]]" })
    write(vim.fs.joinpath(dir, "20240104__c.snot"), {
      "not links: [[20240101__target-2]] or 20240101__target or [[20240101__target.png]]",
      "`[[20240101__target]]`",
      "```",
      "[[20240101__target]]",
      "```",
      "to a daily: [[daily/20240105]]",
    })
    write(vim.fs.joinpath(dir, "daily", "20240105.snot"), { "- [[20240101__target]] from a daily" })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("finds plain, anchored and labelled links, newest first, skipping the note itself", function()
    local found = assert(backlinks("20240101__target"))
    assert.are.same({
      {
        path = vim.fs.joinpath(dir, "daily", "20240105.snot"),
        lnum = 1,
        col = 3,
        text = "- [[20240101__target]] from a daily",
      },
      {
        path = vim.fs.joinpath(dir, "20240103__b.snot"),
        lnum = 1,
        col = 10,
        text = "labelled [[ 20240101__target#risks | the target ]]",
      },
      { path = vim.fs.joinpath(dir, "20240102__a.snot"), lnum = 2, col = 5, text = "see [[20240101__target]]" },
    }, found)
  end)

  it("accepts a path as well as a link path", function()
    assert.are.equal(3, #assert(backlinks(vim.fs.joinpath(dir, "20240101__target.snot"))))
  end)

  it("links to notes in folders by their path from the notes directory", function()
    local found = assert(backlinks(vim.fs.joinpath(dir, "daily", "20240105.snot")))
    assert.are.same({ vim.fs.joinpath(dir, "20240104__c.snot") }, { found[1].path })
    assert.are.same({}, backlinks("20240105"))
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
    vim.cmd.edit(vim.fs.joinpath(dir, "20240101__target.snot"))
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
    assert.are.equal(vim.fs.joinpath(dir, "daily", "20240105.snot"), vim.api.nvim_buf_get_name(qf[1].bufnr))
    vim.cmd("cclose")
  end)

  it("completes link paths", function()
    assert.are.same({ "daily/20240105" }, vim.fn.getcompletion("Snot backlinks da", "cmdline"))
  end)

  it("opens links with gf", function()
    vim.cmd.edit(vim.fs.joinpath(dir, "20240103__b.snot"))
    vim.api.nvim_win_set_cursor(0, { 1, 14 })
    vim.cmd("normal! gf")
    assert.are.equal(vim.fs.joinpath(dir, "20240101__target.snot"), vim.api.nvim_buf_get_name(0))
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

describe("treesitter", function()
  after_each(function()
    package.loaded["nvim-treesitter.parsers"] = nil
  end)

  it("registers the parsers with nvim-treesitter on TSUpdate", function()
    local parsers = {}
    package.loaded["nvim-treesitter.parsers"] = parsers
    vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
    assert.are.equal("tree-sitter-snot", parsers.snot.install_info.location)
    assert.are.same({ "snot_inline" }, parsers.snot.requires)
    assert.are.equal("tree-sitter-snot-inline", parsers.snot_inline.install_info.location)
  end)

  it("sets conceallevel in notes", function()
    vim.cmd.edit(vim.fn.tempname() .. ".snot")
    assert.are.equal(2, vim.wo.conceallevel)
    vim.cmd("bwipeout!")
  end)

  it("conceals the target of a labelled link", function()
    if not require("snot.treesitter").has_parser("snot_inline") then
      pending("snot_inline parser not installed")
      return
    end
    vim.cmd.edit(vim.fn.tempname() .. ".snot")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[a#x|Label]] [[plain]]" })
    vim.treesitter.get_parser(0):parse(true)
    local concealed = {}
    for col = 0, 22 do
      for _, cap in ipairs(vim.treesitter.get_captures_at_pos(0, 0, col)) do
        if cap.metadata.conceal then
          concealed[#concealed + 1] = col
          break
        end
      end
    end
    -- "[[a#x|" and "]]", but not the label or the unlabelled link.
    assert.are.same({ 0, 1, 2, 3, 4, 5, 11, 12 }, concealed)
    vim.cmd("bwipeout!")
  end)
end)

describe("align", function()
  local align = require("snot.align")
  local opts = { width = 30, expandtab = true, tabstop = 8 }

  it("pushes the metadata ending a heading or list item to the margin", function()
    assert.are.equal("# Kickoff    @project:atlas @a", align.line("# Kickoff @project:atlas @a", opts))
    assert.are.equal("## Decisions     @id:decisions", align.line("## Decisions\t@id:decisions  ", opts))
    assert.are.equal("  - [ ] Plan   @due:2026-09-30", align.line("  - [ ] Plan @due:2026-09-30", opts))
    assert.are.equal("+ Ship                      @x", align.line("+ Ship @x", opts))
    assert.are.equal("12. [x] Room                @x", align.line("12. [x] Room @x", opts))
  end)

  it("keeps one space when the line is too long", function()
    assert.are.equal("# A long heading about things @a @b", align.line("# A long heading about things    @a @b", opts))
  end)

  it("measures display width", function()
    assert.are.equal("# ünï                       @a", align.line("# ünï @a", opts))
  end)

  it("pads with tabs unless expandtab is set", function()
    local tabs = { width = 30, expandtab = false, tabstop = 8 }
    assert.are.equal("# Kickoff\t    @project:x", align.line("# Kickoff @project:x", tabs))
  end)

  it("leaves other lines alone", function()
    for _, line in ipairs({
      "text @a",
      "| row | @a |",
      "# @work",
      "- [ ] @due:2026-09-30",
      "# Tokens @a in the middle",
      "# Code `@a`",
      "# Link [[x|@a]]",
      "####### Seven @a",
      "#Nospace @a",
    }) do
      assert.are.equal(line, align.line(line, opts))
    end
  end)

  describe("buffers", function()
    local aligned = "# A" .. (" "):rep(15) .. "@b"
    local function note(lines)
      vim.cmd.edit(vim.fn.tempname() .. ".snot")
      vim.bo.textwidth = 20
      vim.bo.expandtab = true
      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    end

    after_each(function()
      snot.setup()
      vim.cmd("bwipeout!")
    end)

    it("uses textwidth, or 79 when it is unset", function()
      note({ "# A @b" })
      snot.format()
      assert.are.equal(20, #vim.api.nvim_get_current_line())
      vim.bo.textwidth = 0
      snot.format()
      assert.are.equal(79, #vim.api.nvim_get_current_line())
    end)

    it("skips code and math blocks, and lines outside the range", function()
      note({ "# A @b", "```", "# A @b", "```", "$$", "- x @y", "$$", "- x @y" })
      snot.format(0, 2)
      assert.are.same(
        { "# A @b", "```", "# A @b", "```", "$$", "- x @y", "$$", "- x" .. (" "):rep(15) .. "@y" },
        vim.api.nvim_buf_get_lines(0, 0, -1, false)
      )
    end)

    it("formats a range with :Snot format", function()
      note({ "# A @b", "# A @b" })
      vim.cmd("2Snot format")
      assert.are.same({ "# A @b", aligned }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    end)

    it("formats on save unless format_on_save is off", function()
      note({ "# A @b" })
      vim.cmd.write()
      assert.are.equal(aligned, vim.api.nvim_get_current_line())
      snot.setup({ format_on_save = false })
      vim.api.nvim_set_current_line("# A @b")
      vim.cmd.write()
      assert.are.equal("# A @b", vim.api.nvim_get_current_line())
    end)
  end)
end)

describe("lsp", function()
  local lsp = require("snot.lsp")
  local dir

  --- Skip the test when the server isn't installed.
  local function need_server()
    if lsp.enabled() then
      return true
    end
    pending("snot is not installed")
    return false
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    snot.setup({ directory = dir })
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
    snot.setup()
  end)

  it("attaches to notes and reports broken links", function()
    if not need_server() then
      return
    end
    write(vim.fs.joinpath(dir, "a.snot"), { "see [[missing]]" })
    vim.cmd.edit(vim.fs.joinpath(dir, "a.snot"))
    assert(vim.wait(5000, function()
      return #vim.diagnostic.get(0) > 0
    end))
    local d = vim.diagnostic.get(0)[1]
    assert.are.same({ "L003", "snot", 0, 6 }, { d.code, d.source, d.lnum, d.col })
  end)

  it("formats with the server, which also trims trailing whitespace", function()
    if not need_server() then
      return
    end
    vim.cmd.edit(vim.fs.joinpath(dir, "a.snot"))
    vim.bo.textwidth = 20
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# A @b  ", "text  ", "", "" })
    snot.format()
    assert.are.same({ "# A" .. (" "):rep(15) .. "@b", "text" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("finds backlinks in unsaved buffers", function()
    if not need_server() then
      return
    end
    write(vim.fs.joinpath(dir, "b.snot"), { "# B" })
    vim.cmd.edit(vim.fs.joinpath(dir, "a.snot"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved [[b]]" })
    local result
    snot.backlinks("b", function(r)
      result = r
    end)
    assert(vim.wait(5000, function()
      return result ~= nil
    end))
    assert.are.same({ { path = vim.fs.joinpath(dir, "a.snot"), lnum = 1, col = 9, text = "unsaved [[b]]" } }, result)
  end)

  it("goes to the heading a link points at", function()
    if not need_server() then
      return
    end
    write(vim.fs.joinpath(dir, "b.snot"), { "# B", "", "## Two" })
    write(vim.fs.joinpath(dir, "a.snot"), { "[[b#two]]" })
    vim.cmd.edit(vim.fs.joinpath(dir, "a.snot"))
    assert(lsp.attached(0))
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    vim.lsp.buf.definition()
    assert(vim.wait(5000, function()
      return vim.api.nvim_buf_get_name(0) == vim.fs.joinpath(dir, "b.snot")
    end))
    assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("can be turned off", function()
    snot.setup({ directory = dir, lsp = false })
    assert.is_false(lsp.enabled())
    assert.is_nil(lsp.client())
  end)
end)
