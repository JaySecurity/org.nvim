-- Completion candidates (org.completion) for every context, as in Emacs'
-- org-pcomplete.el (org-thing-at-point), and the omnifunc / blink.cmp /
-- nvim-cmp adapters (with the plugins stubbed: neither is required).

local c = require("org.completion")

local function words(r)
  return vim.tbl_map(function(i)
    return i.word
  end, r and r.items or {})
end

local function has(list, w)
  return vim.tbl_contains(list, w)
end

local function count_of(list, w)
  local n = 0
  for _, x in ipairs(list) do
    if x == w then
      n = n + 1
    end
  end
  return n
end

--- Complete `typed` as the whole line `lnum` with the cursor at its end.
local function at(lnum, typed, buf)
  vim.api.nvim_buf_set_lines(buf or 0, lnum - 1, lnum, false, { typed })
  return c.get(typed, #typed, buf or 0)
end

describe("completion contexts", function()
  describe("#+STARTUP and #+OPTIONS values", function()
    it("offers startup options after the keyword, any case, after earlier options", function()
      org_buffer({ "" })
      local r = c.get("#+STARTUP: ", 11, 0)
      eq(11, r.start)
      ok(has(words(r), "overview"))
      ok(has(words(r), "hidestars"))
      eq("startup", r.items[1].kind)
      r = c.get("#+startup: overview ind", 23, 0)
      eq(20, r.start)
      ok(has(words(r), "indent"))
      r = c.get("  #+STARTUP: lo", 15, 0)
      eq(13, r.start)
    end)

    it("offers export options after #+OPTIONS:", function()
      org_buffer({ "" })
      local r = c.get("#+OPTIONS: toc:nil n", 20, 0)
      eq(19, r.start)
      ok(has(words(r), "num:"))
      ok(has(words(r), "^:"))
      eq("option", r.items[1].kind)
      r = c.get("#+options: ", 11, 0)
      eq(11, r.start)
    end)
  end)

  describe("source blocks", function()
    it("offers languages after #+begin_src, sorted and without duplicates", function()
      org_buffer({ "" })
      local r = c.get("#+BEGIN_SRC ", 12, 0)
      eq(12, r.start)
      local w = words(r)
      ok(#w > 0)
      local sorted = vim.deepcopy(w)
      table.sort(sorted)
      eq(sorted, w)
      local seen = {}
      for _, l in ipairs(w) do
        ok(not seen[l], "duplicate " .. l)
        seen[l] = true
      end
      for alias in pairs(require("org.syntax").lang_aliases) do
        ok(seen[alias], alias)
      end
      eq("language", r.items[1].kind)
    end)

    it("includes the configured babel languages", function()
      local cfg = require("org.config").opts
      local saved = cfg.babel.languages
      cfg.babel.languages = vim.tbl_extend("force", saved or {}, { zzlang = true })
      org_buffer({ "" })
      local w = words(c.get("#+begin_src zz", 14, 0))
      cfg.babel.languages = saved
      ok(has(w, "zzlang"))
    end)

    it("offers header arguments and switches after the language", function()
      org_buffer({ "" })
      local r = c.get("#+begin_src sh :results output :ex", 34, 0)
      eq(31, r.start)
      ok(has(words(r), ":exports"))
      eq("header arg", r.items[1].kind)
      r = c.get("#+begin_src emacs-lisp -", 24, 0)
      eq(23, r.start)
      ok(has(words(r), "-n"))
      ok(has(words(r), "-r"))
    end)

    it("offers header arguments on #+HEADER: lines", function()
      org_buffer({ "" })
      local r = c.get("#+header: :v", 12, 0)
      eq(10, r.start)
      ok(has(words(r), ":var"))
    end)

    it("does not offer header arguments while the language is typed", function()
      org_buffer({ "" })
      local r = c.get("#+begin_src :", 13, 0)
      eq("language", r.items[1].kind)
    end)
  end)

  it("offers clock table parameters on a #+BEGIN: clocktable line", function()
    org_buffer({ "" })
    local r = c.get("#+BEGIN: clocktable :maxlevel 2 :sc", 35, 0)
    eq(32, r.start)
    ok(has(words(r), ":scope"))
    eq("parameter", r.items[1].kind)
    -- any other dynamic block: no clocktable parameters
    r = c.get("#+BEGIN: columnview :", 21, 0)
    ok(not r or not has(words(r), ":maxlevel"))
  end)

  describe("entities", function()
    it("completes \\name from org-entities, the start on the backslash", function()
      org_buffer({ "" })
      local r = c.get("x \\", 3, 0)
      eq(2, r.start)
      ok(has(words(r), "\\alpha"))
      eq("entity", r.items[1].kind)
      r = c.get("\\rar", 4, 0)
      eq(0, r.start)
      ok(has(words(r), "\\rarr"))
    end)

    it("accepts trailing digits, as the entity names do (\\frac12)", function()
      org_buffer({ "" })
      local r = c.get("half: \\frac1", 12, 0)
      ok(r, "no context")
      eq(6, r.start)
      ok(has(words(r), "\\frac12"), vim.inspect(words(r)))
    end)

    it("not on a #+ keyword line", function()
      org_buffer({ "" })
      local r = c.get("#+TITLE: \\al", 12, 0)
      ok(not r or r.items[1].kind ~= "entity")
    end)
  end)

  describe("#+FILETAGS", function()
    it("offers the buffer's tags after the colon of the previous tag", function()
      org_buffer({ "#+FILETAGS: :", "* A :work:", "* B :home:" })
      local r = c.get("#+FILETAGS: :work:h", 19, 0)
      eq(18, r.start)
      ok(has(words(r), "home"))
      eq("tag", r.items[1].kind)
      r = c.get("#+filetags: ", 12, 0)
      eq(12, r.start)
      ok(has(words(r), "work"))
    end)
  end)

  describe("#+ keywords", function()
    it("offers upper-case keywords after a bare #+", function()
      org_buffer({ "" })
      local r = c.get("#+", 2, 0)
      eq(2, r.start)
      local w = words(r)
      ok(has(w, "TITLE:"))
      ok(has(w, "BEGIN_SRC"))
      ok(has(w, "END_SRC"))
      ok(has(w, "BEGIN:"))
      ok(not has(w, "BEGIN::"))
      eq("keyword", r.items[1].kind)
    end)

    it("follows the case of what is typed", function()
      org_buffer({ "" })
      local w = words(c.get("#+ti", 4, 0))
      ok(has(w, "title:"))
      ok(has(w, "begin_src"))
      w = words(c.get("#+TI", 4, 0))
      ok(has(w, "TITLE:"))
      local r = c.get("  #+Ti", 6, 0)
      eq(4, r.start)
      ok(has(words(r), "title:"))
    end)
  end)

  describe("links", function()
    after_each(function()
      require("org.links").stored = {}
    end)

    it("offers link types, #+LINK and configured abbreviations, stored links and headings", function()
      local links = require("org.links")
      local cfg = require("org.config").opts
      local saved = cfg.links.abbreviations
      cfg.links.abbreviations = { gh = "https://github.com/%s" }
      links.stored = { { link = "file:/tmp/x.org::*X", description = "X" } }
      org_buffer({ "#+LINK: wiki https://en.wikipedia.org/wiki/%s", "* First", "* Second", "see [[" })
      local r = c.get("see [[", 6, 0)
      cfg.links.abbreviations = saved
      eq(6, r.start)
      local w = words(r)
      for _, t in ipairs({ "file:", "id:", "https://", "mailto:", "attachment:" }) do
        ok(has(w, t), t)
      end
      ok(has(w, "wiki:"), vim.inspect(w))
      ok(has(w, "gh:"), vim.inspect(w))
      ok(has(w, "file:/tmp/x.org::*X"), vim.inspect(w))
      ok(has(w, "*First"))
      ok(has(w, "*Second"))
      eq("link", r.items[1].kind)
    end)

    it("starts after [[ wherever it is on the line, and stays in the link while typing", function()
      org_buffer({ "" })
      local r = c.get("a [[b]] and [[fi", 16, 0)
      eq(14, r.start)
      ok(has(words(r), "file:"))
      -- a closed link: nothing to complete
      eq(nil, c.get("a [[b]] x", 9, 0))
    end)

    it("completes headings after [[*, without duplicates", function()
      org_buffer({ "* Same", "** Same", "* TODO [#A] Other :tag:" })
      local r = c.get("[[*", 3, 0)
      eq(2, r.start)
      local w = words(r)
      eq(1, count_of(w, "*Same"), vim.inspect(w))
      ok(has(w, "*Other"), vim.inspect(w))
      eq("heading", r.items[1].kind)
    end)

    it("completes custom IDs after [[#", function()
      org_buffer({ "* A", ":PROPERTIES:", ":CUSTOM_ID: one", ":END:", "* B" })
      local r = c.get("[[#o", 4, 0)
      eq(2, r.start)
      eq({ "#one" }, words(r))
      eq("custom_id", r.items[1].kind)
    end)
  end)

  describe("headlines", function()
    it("offers the buffer's TODO keywords and COMMENT on an empty headline", function()
      org_buffer({ "#+TODO: NEXT WAIT | FINISHED", "* " })
      local r = at(2, "* ")
      eq(2, r.start)
      local w = words(r)
      ok(has(w, "NEXT"))
      ok(has(w, "WAIT"))
      ok(has(w, "FINISHED"))
      ok(has(w, "COMMENT"))
      ok(not has(w, "TODO"), vim.inspect(w))
      eq("todo", r.items[1].kind)
      r = at(2, "*** NE")
      eq(4, r.start)
    end)

    it("offers nothing in the title after the first word", function()
      org_buffer({ "* TODO Write" })
      eq(nil, c.get("* TODO Write", 12, 0))
      eq(nil, c.get("* TODO ", 7, 0))
    end)

    it("not on a line that only looks like a headline", function()
      org_buffer({ " * x" })
      local r = c.get(" * x", 4, 0)
      ok(not r or r.items[1].kind ~= "todo")
      eq(nil, c.get("*bold", 5, 0))
    end)

    it("offers tags after a colon, with the start after the last colon", function()
      org_buffer({ "* A :work:", "* B :" })
      local r = at(2, "* B :")
      eq(5, r.start)
      ok(has(words(r), "work:"))
      eq("tag", r.items[1].kind)
      r = at(2, "* B :work:")
      eq(10, r.start)
    end)

    it("offers only the #+TAGS definitions when there are any (org-current-tag-alist)", function()
      org_buffer({ "#+TAGS: @home(h) @work(w) { project : alpha beta } {^@.*}", "* A :stray:", "* B :" })
      local w = words(at(3, "* B :"))
      ok(has(w, "@home:"), vim.inspect(w))
      ok(has(w, "@work:"), vim.inspect(w))
      ok(has(w, "project:"), vim.inspect(w))
      ok(has(w, "alpha:"), vim.inspect(w))
      ok(not has(w, "stray:"), vim.inspect(w))
      -- a regular-expression group member is not a tag
      ok(not has(w, "{^@.*}:"), vim.inspect(w))
      for _, x in ipairs(w) do
        ok(not x:match("^[{}%[%]:]"), x)
      end
    end)

    it("does not take colons in the title for tags already set", function()
      org_buffer({ "* A :30:", "* Meeting at 10:30 :" })
      local w = words(at(2, "* Meeting at 10:30 :"))
      ok(has(w, "30:"), vim.inspect(w))
    end)
  end)

  describe("drawers and properties", function()
    it("offers drawer names used in the buffer outside a property drawer", function()
      org_buffer({ "* A", ":NOTES:", "x", ":END:", "* B", "body", ":" }, { 7, 0 })
      local r = c.get(":", 1, 0)
      eq(1, r.start)
      local w = words(r)
      ok(has(w, "PROPERTIES:"))
      ok(has(w, "LOGBOOK:"))
      ok(has(w, "END:"))
      ok(has(w, "NOTES:"), vim.inspect(w))
      eq(1, count_of(w, "PROPERTIES:"))
      eq("property", r.items[1].kind)
    end)

    it("offers property names after a headline with planning", function()
      org_buffer({
        "* A",
        "SCHEDULED: <2024-01-01 Mon>",
        ":PROPERTIES:",
        ":CATEGORY: x",
        ":",
        ":END:",
      }, { 5, 0 })
      local w = words(c.get(":", 1, 0))
      ok(has(w, "ID: "), vim.inspect(w))
      ok(has(w, "END:"))
      ok(not has(w, "CATEGORY: "))
    end)

    it("offers properties other entries use", function()
      org_buffer({
        "* A",
        ":PROPERTIES:",
        ":MYPROP: 1",
        ":END:",
        "* B",
        ":PROPERTIES:",
        ":",
        ":END:",
      }, { 7, 0 })
      local w = words(c.get(":", 1, 0))
      ok(has(w, "MYPROP: "), vim.inspect(w))
    end)

    it("is a drawer name, not a property, on the line opening the drawer or below its end", function()
      org_buffer({ "* A", ":", ":PROPERTIES:", ":END:" }, { 2, 0 })
      ok(has(words(c.get(":", 1, 0)), "PROPERTIES:"))
      org_buffer({ "* A", ":PROPERTIES:", ":ID: x", ":END:", ":" }, { 5, 0 })
      local w = words(c.get(":", 1, 0))
      ok(has(w, "PROPERTIES:"), vim.inspect(w))
      ok(not has(w, "ID: "))
    end)

    it("not after body text in the drawer (a broken drawer)", function()
      org_buffer({ "* A", ":PROPERTIES:", "not a property", ":", ":END:" }, { 4, 0 })
      local w = words(c.get(":", 1, 0))
      ok(has(w, "PROPERTIES:"), vim.inspect(w))
    end)
  end)

  it("offers nothing in plain text", function()
    org_buffer({ "just text" })
    eq(nil, c.get("just text", 9, 0))
    eq(nil, c.get("", 0, 0))
  end)

  it("looks only at the text before the cursor", function()
    org_buffer({ "" })
    local r = c.get("#+STARTUP: over and more", 15, 0)
    eq(11, r.start)
  end)
end)

describe("completion omnifunc", function()
  it("returns -3 to cancel when there is nothing to complete", function()
    org_buffer({ "plain" }, { 1, 5 })
    eq(-3, c.omnifunc(1, ""))
    eq({}, c.omnifunc(0, "x"))
  end)

  it("returns the start, then the matches of the base with a menu", function()
    org_buffer({ "#+STARTUP: " }, { 1, 10 })
    vim.o.virtualedit = "onemore"
    vim.api.nvim_win_set_cursor(0, { 1, 11 })
    eq(11, c.omnifunc(1, ""))
    local out = c.omnifunc(0, "OVER")
    vim.o.virtualedit = ""
    eq({ { word = "overview", menu = "[org startup]" } }, out)
  end)
end)

describe("completion adapters", function()
  local saved_types

  before_each(function()
    saved_types = package.loaded["blink.cmp.types"]
  end)

  after_each(function()
    package.loaded["blink.cmp.types"] = saved_types
  end)

  describe("blink.cmp", function()
    local Source = require("org.completion.blink")

    it("is enabled in org buffers only, with its trigger characters", function()
      local s = Source.new()
      org_buffer({ "" })
      eq(true, s:enabled())
      vim.bo.filetype = "text"
      eq(false, s:enabled())
      ok(has(s:get_trigger_characters(), "#"))
      ok(has(s:get_trigger_characters(), "["))
    end)

    it("returns items with text edits over the completed word", function()
      package.loaded["blink.cmp.types"] = { CompletionItemKind = { EnumMember = 20, Text = 1, Keyword = 14 } }
      local buf = org_buffer({ "#+STARTUP: ov" }, { 1, 12 })
      local got
      Source.new():get_completions({ line = "#+STARTUP: ov", cursor = { 1, 13 }, bufnr = buf }, function(r)
        got = r
      end)
      eq(false, got.is_incomplete_forward)
      local item
      for _, it in ipairs(got.items) do
        if it.label == "overview" then
          item = it
        end
      end
      ok(item)
      eq(20, item.kind)
      eq("org startup", item.labelDetails.description)
      eq({
        newText = "overview",
        range = { start = { line = 0, character = 11 }, ["end"] = { line = 0, character = 13 } },
      }, item.textEdit)
    end)

    it("works without blink's types module and returns no items outside a context", function()
      package.loaded["blink.cmp.types"] = nil
      package.preload["blink.cmp.types"] = nil
      local buf = org_buffer({ "plain", "#+begin_src py" }, { 1, 0 })
      local got
      Source.new():get_completions({ line = "plain", cursor = { 1, 5 }, bufnr = buf }, function(r)
        got = r
      end)
      eq({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false }, got)
      Source.new():get_completions({ line = "#+begin_src py", cursor = { 2, 14 }, bufnr = buf }, function(r)
        got = r
      end)
      ok(#got.items > 0)
      eq(nil, got.items[1].kind)
      eq(1, got.items[1].textEdit.range.start.line)
    end)
  end)

  describe("nvim-cmp", function()
    local Source = require("org.completion.cmp")

    it("is available in org buffers only, with trigger characters and a keyword pattern", function()
      local s = Source.new()
      org_buffer({ "" })
      eq(true, s:is_available())
      vim.bo.filetype = "text"
      eq(false, s:is_available())
      ok(has(s:get_trigger_characters(), ":"))
      -- the pattern is a valid Vim regex covering #+ keywords and :tags:
      eq(0, vim.fn.match("#+title", "^" .. s:get_keyword_pattern() .. "$"))
      eq(0, vim.fn.match(":work:", "^" .. s:get_keyword_pattern() .. "$"))
    end)

    it("completes the text before the cursor", function()
      local buf = org_buffer({ "* A :work:", "* B :w and more" }, { 2, 6 })
      local got
      Source.new():complete({
        context = {
          cursor_before_line = "* B :w",
          cursor_line = "* B :w and more",
          cursor = { row = 2, col = 7 },
          bufnr = buf,
        },
      }, function(r)
        got = r
      end)
      eq(false, got.isIncomplete)
      local item
      for _, it in ipairs(got.items) do
        if it.label == "work:" then
          item = it
        end
      end
      ok(item, vim.inspect(got))
      eq("org tag", item.detail)
      eq({ start = { line = 1, character = 5 }, ["end"] = { line = 1, character = 6 } }, item.textEdit.range)
    end)

    it("returns no items outside a context", function()
      local buf = org_buffer({ "text" }, { 1, 3 })
      local got
      Source.new():complete({
        context = { cursor_before_line = "text", cursor_line = "text", cursor = { row = 1, col = 5 }, bufnr = buf },
      }, function(r)
        got = r
      end)
      eq({ items = {}, isIncomplete = false }, got)
    end)
  end)
end)
