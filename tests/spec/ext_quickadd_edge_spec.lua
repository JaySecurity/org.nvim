-- Edge cases of the quickadd extension: empty and blank lines, unicode,
-- malformed quoting and escapes, very long lines, unusual keywords and
-- priority ranges, and adding to empty or missing files.

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"))
local date = require("org.date")
local parse = require("org.extensions.quickadd.parse")

local function setup(qa, extra)
  require("org").setup(vim.tbl_extend("force", {
    org_directory = root .. "/tests/fixtures",
    agenda_files = { root .. "/tests/fixtures/*.org" },
    extensions = qa ~= nil and { quickadd = qa } or nil,
  }, extra or {}))
end

-- Tuesday 2026-09-29 10:00
local NOW = date.Date.new({ year = 2026, month = 9, day = 29, hour = 10, min = 0 })
local KW = { keywords = { "TODO", "NEXT", "WAITING", "DONE" } }

local function P(text, o)
  return parse.parse(text, NOW, vim.tbl_extend("force", KW, o or {}))
end

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

describe("quickadd edge cases", function()
  describe("empty and blank input", function()
    it("parses nil, empty and blank lines to an empty title", function()
      for _, s in ipairs({ "", "   ", "\t\n " }) do
        local r = P(s)
        eq("", r.title)
        eq({}, r.tags)
        eq({}, r.planning)
        eq("TODO", r.todo)
      end
      eq("", parse.parse(nil, NOW, KW).title)
      eq({}, parse.tokenize(""))
    end)

    it("leaves bare sigils in the title", function()
      local r = P("Fix # @ ! ~ *")
      eq("Fix # @ ! ~ *", r.title)
      eq({}, r.tags)
      eq(nil, r.target)
      eq(nil, r.priority)
      eq(nil, r.effort)
      eq("TODO", r.todo)
    end)

    it("does not take an empty or blank @target", function()
      eq(nil, P('Call @""').target)
      eq(nil, P("Call @").target)
    end)

    it("leaves a dangling due, by and every in the title", function()
      eq("Pay due", P("Pay due").title)
      eq("Stand by", P("Stand by").title)
      eq("Read every", P("Read every").title)
      eq({}, P("Pay due").planning)
    end)

    it("adds nothing for a blank line or a line with no title", function()
      local d = tmpdir()
      setup({}, { org_directory = d, default_notes_file = d .. "/n.org" })
      local qa = require("org.extensions.quickadd")
      eq(nil, qa.add_text("", NOW))
      eq(nil, qa.add_text("   ", NOW))
      eq(nil, qa.add_text(nil, NOW))
      local warned
      local saved = vim.notify
      vim.notify = function(msg)
        warned = msg
      end
      local res = qa.add_text("#tag fri !A", NOW)
      vim.notify = saved
      eq(nil, res)
      ok(warned and warned:find("no title", 1, true), warned)
      eq(0, vim.fn.filereadable(d .. "/n.org"))
      setup(nil)
    end)
  end)

  describe("malformed quoting and escapes", function()
    it("keeps unclosed quotes as text", function()
      eq('Say "hello world', P('Say "hello world').title)
      eq("Say 'hello", P("Say 'hello").title)
      eq('"Big', P('Meet @"Big').target.raw)
    end)

    it("only closes a quote before a blank", function()
      local t = parse.tokenize('"a"b c" d')
      eq({ 'a"b c', "d" }, {
        t[1].text,
        t[2].text,
      })
      eq(false, t[1].plain)
    end)

    it("keeps a trailing backslash", function()
      local r = P("Path C:\\")
      eq("Path C:\\", r.title)
    end)

    it("escapes a multibyte character", function()
      local t = parse.tokenize("\\é")
      eq("é", t[1].text)
      eq(false, t[1].plain)
    end)

    it("escapes a byte that starts no UTF-8 character", function()
      -- a lone continuation byte, or a byte that is never valid UTF-8
      for _, b in ipairs({ "\128", "\255", "\192" }) do
        local t = parse.tokenize("a\\" .. b .. "z")
        eq(1, #t)
        eq("a" .. b .. "z", t[1].text)
      end
      eq("x\255", P("x\\\255").title)
    end)

    it("does not read invalid dates as dates", function()
      for _, s in ipairs({ "x 2026-13-45", "x 99/99", "x 32.13.", "x w99" }) do
        local r = P(s)
        eq(nil, r.planning.deadline, s)
        if r.planning.scheduled == nil then
          ok(r.title:find(s:sub(3), 1, true), s .. " -> " .. r.title)
        end
      end
    end)

    it("ignores an every with nothing it can repeat", function()
      local r = P("Water plants every 0 days")
      eq(nil, r.repeater)
      ok(r.title:find("every", 1, true))
      r = P("Water plants every 0d")
      eq(nil, r.repeater)
      r = P("Water plants every blue moon")
      eq(nil, r.repeater)
      eq("Water plants every blue moon", r.title)
    end)

    it("takes only the first every", function()
      local r = P("Run every day every week")
      eq("d", r.repeater.unit)
      eq("Run every week", r.title)
    end)
  end)

  describe("unicode", function()
    it("keeps unicode titles, tags and targets", function()
      local r = P("Café mit Jürgen 🍰 #café #日本 @Überblick fri")
      eq("Café mit Jürgen 🍰", r.title)
      eq({ "café", "日本" }, r.tags)
      eq("Überblick", r.target.heading)
      eq("<2026-10-02 Fri>", r.planning.scheduled)
    end)

    it("quotes unicode words", function()
      local r = P('"Ünïcödé fri" @"Grüne Ecke"')
      eq("Ünïcödé fri", r.title)
      eq({}, r.planning)
      eq("Grüne Ecke", r.target.heading)
    end)

    it("writes a unicode entry to the file", function()
      local d = tmpdir()
      setup({}, { org_directory = d, default_notes_file = d .. "/n.org" })
      local qa = require("org.extensions.quickadd")
      local _, lnum = qa.add_text("Größe prüfen #übung", NOW)
      local lines = vim.fn.readfile(d .. "/n.org")
      ok(lines[lnum]:match("^%* TODO Größe prüfen%s+:übung:$"), lines[lnum])
      setup(nil)
    end)
  end)

  describe("very long lines", function()
    it("parses a line of thousands of words", function()
      local words = {}
      for k = 1, 5000 do
        words[#words + 1] = "w" .. k
      end
      local text = table.concat(words, " ") .. " #t fri"
      local r = P(text)
      eq(5000, #vim.split(r.title, " "))
      eq({ "t" }, r.tags)
      eq("<2026-10-02 Fri>", r.planning.scheduled)
    end)

    it("parses one very long word", function()
      local long = string.rep("x", 100000)
      eq(long, P(long).title)
      eq({ long }, P("#" .. long).tags)
    end)

    it("parses many tags and dates, keeping the last date", function()
      local parts = {}
      for k = 1, 200 do
        parts[#parts + 1] = "#t" .. k
      end
      local r = P("Task 2026-12-01 " .. table.concat(parts, " ") .. " 2026-12-05")
      eq(200, #r.tags)
      eq("<2026-12-05 Sat>", r.planning.scheduled)
      eq("Task 2026-12-01", r.title)
    end)
  end)

  describe("unusual keywords and priorities", function()
    it("matches keywords case-insensitively and keeps their spelling", function()
      local r = P("Task *next", { keywords = { "TODO", "Next", "DONE" } })
      eq("Next", r.todo)
    end)

    it("reads keywords with non-letter characters", function()
      local r = P("Task *IN-PROGRESS", { keywords = { "TODO", "IN-PROGRESS", "DONE" } })
      eq("IN-PROGRESS", r.todo)
      eq("Task", r.title)
      r = P("Task *ÉTUDE", { keywords = { "TODO", "ÉTUDE" } })
      eq("ÉTUDE", r.todo)
    end)

    it("leaves an unknown keyword in the title", function()
      local r = P("Task *SOMEDAY")
      eq("TODO", r.todo)
      eq("Task *SOMEDAY", r.title)
    end)

    it("works with no keywords configured", function()
      local r = parse.parse("Task *TODO fri", NOW, { keywords = {}, keyword = false })
      eq(nil, r.todo)
      eq("Task *TODO", r.title)
      eq("<2026-10-02 Fri>", r.planning.scheduled)
    end)

    it("keeps priorities outside the range in the title", function()
      local r = P("Task !D !0 !9 p0 p9")
      eq(nil, r.priority)
      eq("Task !D !0 !9 p0 p9", r.title)
    end)

    it("reads a wider letter range", function()
      local r = P("Task !E", { priority_highest = "A", priority_lowest = "E" })
      eq("E", r.priority)
      eq("D", P("Task p4", { priority_highest = "A", priority_lowest = "E" }).priority)
    end)

    it("reads numeric priority ranges", function()
      local o = { priority_highest = "1", priority_lowest = "10" }
      eq("1", P("Task !1", o).priority)
      eq("5", P("Task !5", o).priority)
      eq("10", P("Task !10", o).priority)
      eq("3", P("Task p3", o).priority)
      local r = P("Task !11 !A", o)
      eq(nil, r.priority)
      eq("Task !11 !A", r.title)
      -- numbers as numbers, as `#+PRIORITIES: 1 10 5` and Lua configs give them
      eq("7", parse.parse("Task !7", NOW, { priority_highest = 1, priority_lowest = 10 }).priority)
    end)
  end)

  describe("effort", function()
    it("rejects malformed efforts", function()
      for _, e in ipairs({ "~", "~abc", "~1:5", "~h", "~1x", "~-5m" }) do
        local r = P("Task " .. e)
        eq(nil, r.effort, e)
        eq("Task " .. e, r.title)
      end
    end)

    it("reads large efforts", function()
      eq(6000, P("Task ~100h").effort)
      eq(1440 * 30, P("Task ~30d").effort)
    end)
  end)

  describe("targets and files", function()
    it("adds to an empty file and a file that does not exist yet", function()
      local d = tmpdir()
      vim.fn.writefile({}, d .. "/empty.org")
      setup({ file = "empty.org" }, { org_directory = d })
      local qa = require("org.extensions.quickadd")
      qa.add_text("One", NOW)
      eq({ "* TODO One" }, vim.fn.readfile(d .. "/empty.org"))
      setup({ file = "sub/dir/new.org", headline = "Inbox" }, { org_directory = d })
      qa.add_text("Two", NOW)
      eq({ "* Inbox", "** TODO Two" }, vim.fn.readfile(d .. "/sub/dir/new.org"))
      setup(nil)
    end)

    it("falls back to the default file for a target in an empty agenda", function()
      local d = tmpdir()
      setup({}, { org_directory = d, agenda_files = {}, default_notes_file = d .. "/n.org" })
      local qa = require("org.extensions.quickadd")
      local loc = qa.resolve_target({ raw = "Nowhere", heading = "Nowhere" })
      eq(d .. "/n.org", loc.filename)
      eq("Nowhere", loc.missing)
      eq({}, qa.complete_target("@"))
      setup(nil)
    end)

    it("previews a line with no title and an unknown target without errors", function()
      local d = tmpdir()
      setup({}, { org_directory = d, agenda_files = {}, default_notes_file = d .. "/n.org" })
      local qa = require("org.extensions.quickadd")
      for _, s in ipairs({ "", "#a", "@Nowhere", string.rep("y", 5000) }) do
        ok(type(qa.preview_lines(s)) == "table", s)
      end
      setup(nil)
    end)
  end)
end)
