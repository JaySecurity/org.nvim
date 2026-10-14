-- org-datetree-add-timestamp and org-datetree-cleanup. Expected buffers come
-- from Emacs 9.8.10 (probes with org-datetree-find-date-create and
-- org-datetree-cleanup).
local capture = require("org.capture")
local config = require("org.config")
local date = require("org.date")
vim.g.org_test = true

local function D(y, m, d)
  return date.Date.new({ year = y, month = m, day = d })
end

describe("datetree_add_timestamp (org-datetree-add-timestamp)", function()
  it("adds nothing by default", function()
    config.setup({})
    local buf = org_buffer({ "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2026, 9, 25))
    eq({ "", "* 2026", "** 2026-09 September", "*** 2026-09-25 Friday" }, buf_lines(buf))
  end)

  it("stamps new day nodes only, inactive", function()
    config.setup({ datetree_add_timestamp = "inactive" })
    local buf = org_buffer({ "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2026, 9, 25))
    capture.ensure_datetree(buf, nil, D(2026, 9, 25))
    capture.ensure_datetree(buf, nil, D(2026, 9, 26))
    eq({
      "",
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "[2026-09-25 Fri]",
      "*** 2026-09-26 Saturday",
      "[2026-09-26 Sat]",
    }, buf_lines(buf))
  end)

  it("stamps a new day node that replaces blank lines, keeping one before the next month", function()
    -- Emacs: org-datetree-find-date-create '(10 7 2026), for 0 to 3 blank lines
    for n = 0, 3 do
      config.setup({ datetree_add_timestamp = "inactive" })
      local lines = { "* 2026", "** 2026-10 October", "*** 2026-10-06 Tuesday", "entry" }
      for _ = 1, n do
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = "** 2026-11 November"
      local buf = org_buffer(lines, { 1, 0 })
      capture.ensure_datetree(buf, nil, D(2026, 10, 7))
      eq({
        "* 2026",
        "** 2026-10 October",
        "*** 2026-10-06 Tuesday",
        "entry",
        "*** 2026-10-07 Wednesday",
        "[2026-10-07 Wed]",
        "",
        "** 2026-11 November",
      }, buf_lines(buf))
    end
  end)

  it("stamps a new day node at the end of the buffer over trailing blank lines", function()
    config.setup({ datetree_add_timestamp = "inactive" })
    local buf = org_buffer({ "* 2026", "** 2026-10 October", "*** 2026-10-06 Tuesday", "entry", "", "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2026, 10, 7))
    eq({
      "* 2026",
      "** 2026-10 October",
      "*** 2026-10-06 Tuesday",
      "entry",
      "*** 2026-10-07 Wednesday",
      "[2026-10-07 Wed]",
    }, buf_lines(buf))
  end)

  it("indents an active stamp with adapt_indentation, and skips month trees", function()
    config.setup({ datetree_add_timestamp = "active", adapt_indentation = true })
    local buf = org_buffer({ "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2026, 9, 25))
    eq({ "", "* 2026", "** 2026-09 September", "*** 2026-09-25 Friday", "    <2026-09-25 Fri>" }, buf_lines(buf))
    config.setup({ datetree_add_timestamp = "active" })
    buf = org_buffer({ "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2026, 9, 25), "month")
    eq({ "", "* 2026", "** 2026-09 September" }, buf_lines(buf))
  end)
end)

describe("datetree_cleanup (org-datetree-cleanup)", function()
  before_each(function()
    config.setup({})
  end)

  it("moves entries under the day of their time stamp", function()
    local buf = org_buffer({
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "**** Entry A",
      "<2026-09-27 Sun>",
      "**** Entry B",
      "<2026-09-25 Fri>",
    }, { 1, 0 })
    require("org.datetree").cleanup(buf)
    eq({
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "**** Entry B",
      "<2026-09-25 Fri>",
      "*** 2026-09-27 Sunday",
      "**** Entry A",
      "<2026-09-27 Sun>",
    }, buf_lines(buf))
  end)

  it("appends to an existing day, skips range ends, inactive stamps and non-tree entries", function()
    local buf = org_buffer({
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "**** Entry A",
      "<2026-09-27 Sun>",
      "body",
      "**** Entry D",
      "[2026-10-02 Fri]",
      "**** Entry E",
      "<2026-09-25 Fri 10:00>--<2026-09-28 Mon>",
      "*** 2026-09-27 Sunday",
      "**** Existing",
      "* Other",
      "<2026-01-01 Thu>",
      "** Entry F",
      "<2026-01-02 Fri>",
    }, { 1, 0 })
    require("org.datetree").cleanup(buf)
    eq({
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "**** Entry D",
      "[2026-10-02 Fri]",
      "**** Entry E",
      "<2026-09-25 Fri 10:00>--<2026-09-28 Mon>",
      "*** 2026-09-27 Sunday",
      "**** Existing",
      "**** Entry A",
      "<2026-09-27 Sun>",
      "body",
      "* Other",
      "<2026-01-01 Thu>",
      "** Entry F",
      "<2026-01-02 Fri>",
    }, buf_lines(buf))
  end)

  it("leaves SCHEDULED and DEADLINE stamps alone (intentional difference)", function()
    local lines = {
      "* 2026",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "**** Entry A",
      "DEADLINE: <2026-09-27 Sun> SCHEDULED: <2026-09-20 Sun>",
    }
    local buf = org_buffer(lines, { 1, 0 })
    require("org.datetree").cleanup(buf)
    eq(lines, buf_lines(buf))
  end)
end)

describe("datetree reversed (newest first, as org-reverse-datetree)", function()
  local utils = require("org.utils")

  it("keeps day, month and year nodes newest first", function()
    config.setup({})
    local buf = org_buffer({ "" }, { 1, 0 })
    capture.ensure_datetree(buf, nil, D(2025, 12, 31), "day", true)
    capture.ensure_datetree(buf, nil, D(2026, 9, 25), "day", true)
    capture.ensure_datetree(buf, nil, D(2026, 10, 11), "day", true)
    capture.ensure_datetree(buf, nil, D(2026, 10, 14), "day", true)
    capture.ensure_datetree(buf, nil, D(2026, 10, 13), "day", true)
    capture.ensure_datetree(buf, nil, D(2026, 10, 13), "day", true)
    eq({
      "",
      "* 2026",
      "** 2026-10 October",
      "*** 2026-10-14 Wednesday",
      "*** 2026-10-13 Tuesday",
      "*** 2026-10-11 Sunday",
      -- a node added at the end of a parent followed by more keeps one
      -- blank line before it, as in an oldest-first tree
      "",
      "** 2026-09 September",
      "*** 2026-09-25 Friday",
      "",
      "* 2025",
      "** 2025-12 December",
      "*** 2025-12-31 Wednesday",
    }, buf_lines(buf))
  end)

  -- issue #267: `prepend` alone doesn't reverse the tree (Emacs inserts the
  -- 14th after the 11th here too); `datetree = { reversed = true }` does
  for _, case in ipairs({
    {
      datetree = { tree_type = "day" },
      want = { "*** 2026-10-13 Tuesday", "*** 2026-10-11 Sunday", "*** 2026-10-14 Wednesday" },
    },
    {
      datetree = { tree_type = "day", reversed = true },
      want = { "*** 2026-10-14 Wednesday", "*** 2026-10-13 Tuesday", "*** 2026-10-11 Sunday" },
    },
  }) do
    it("captures with prepend into a newest-first journal, reversed = " .. tostring(case.datetree.reversed), function()
      config.setup({})
      local p = vim.fn.tempname() .. ".org"
      utils.writefile(p, {
        "* 2026",
        "** 2026-10 October",
        "*** 2026-10-13 Tuesday",
        "",
        "Some note.",
        "",
        "*** 2026-10-11 Sunday",
        "",
        "Another note.",
        "",
      })
      local tpl = {
        target = p,
        type = "plain",
        template = "Newest note",
        datetree = case.datetree,
        prepend = true,
        empty_lines = 1,
        immediate_finish = true,
      }
      ok(utils.run(function()
        capture.capture(tpl, { date = D(2026, 10, 14) })
      end))
      local b = utils.find_buffer(p)
      local lines = b and vim.api.nvim_buf_get_lines(b, 0, -1, false) or utils.readfile(p)
      local days = vim.tbl_filter(function(l)
        return l:match("^%*%*%* ") ~= nil
      end, lines)
      eq(case.want, days)
      local i = assert(vim.tbl_contains(lines, "Newest note") and vim.fn.index(lines, "Newest note"))
      eq("*** 2026-10-14 Wednesday", lines[i - 1])
    end)
  end
end)
