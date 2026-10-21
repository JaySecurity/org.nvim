-- Edge cases of the ql extension: malformed and empty queries, empty and
-- headline-less files, unicode, very long lines and deep outlines, unusual
-- TODO keywords and priorities, and broken saved views.

local utils = require("org.utils")

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")

local function setup(extra)
  require("org").setup(vim.tbl_deep_extend("force", {
    org_directory = dir,
    agenda_files = { dir .. "/*.org" },
    extensions = { ql = { views_file = dir .. "/views.json" } },
  }, extra or {}))
end

local function titles(hls)
  return vim.tbl_map(function(hl)
    return hl:plain_title()
  end, hls)
end

local function sel(buf, q, o)
  return titles(require("org.extensions.ql").select(buf, q, o))
end

-- Run `fn` with vim.notify captured; returns the messages.
local function notified(fn)
  local msgs = {}
  local saved = vim.notify
  vim.notify = function(m)
    msgs[#msgs + 1] = m
  end
  local okk, err = pcall(fn)
  vim.notify = saved
  assert(okk, err)
  return msgs
end

describe("ql edge cases", function()
  local query = require("org.extensions.ql.query")
  local ql = require("org.extensions.ql")

  before_each(function()
    setup()
  end)
  after_each(function()
    require("org").setup({
      org_directory = vim.fn.getcwd() .. "/tests/fixtures",
      agenda_files = { vim.fn.getcwd() .. "/tests/fixtures/*.org" },
    })
    vim.cmd("enew!")
  end)

  describe("malformed queries", function()
    it("reports empty and unbalanced queries", function()
      for _, q in ipairs({ "", "   ", "\n", "(", "(todo))", '(todo "x', "(and (todo)", "(todo) (done)" }) do
        local pred, err = query.try_compile(q)
        eq(nil, pred, q)
        ok(type(err) == "string" and err ~= "", q)
      end
    end)

    it("reports queries that are no predicate", function()
      for _, q in ipairs({ "()", "(1 2)", "((todo))", "(t)", "(nil)" }) do
        local pred, err = query.try_compile(q)
        eq(nil, pred, q)
        ok(err ~= nil, q)
      end
      eq(nil, (query.try_compile({ 42 })))
      eq(nil, (query.try_compile({ "pred", "not a function" })))
      eq(nil, (query.try_compile("(property)")))
    end)

    it("reports invalid regexps, numbers and dates at compile time", function()
      eq(nil, (query.try_compile('(regexp "\\\\(")')))
      eq(nil, (query.try_compile('(heading-regexp "[")')))
      eq(nil, (query.try_compile('(level "x")')))
      eq(nil, (query.try_compile('(level \'> "x")')))
      eq(nil, (query.try_compile('(effort "lots")')))
      eq(nil, (query.try_compile('(deadline :to "someday")')))
      eq(nil, (query.try_compile('(ts :on "2026-13-45")')))
      eq(nil, (query.try_compile('(ts :on "2026-02-30")')))
      ok(query.try_compile('(ts :on "2028-02-29")'))
    end)

    it("reports an invalid regexp in link :regexp-p at compile time", function()
      local pred, err = query.try_compile('(link "[" :regexp-p t)')
      eq(nil, pred)
      ok(err)
    end)

    it("reads empty logical forms like org-ql", function()
      local buf = org_buffer({ "* TODO One", "* Two" })
      eq({ "One", "Two" }, sel(buf, "(and)"))
      eq({}, sel(buf, "(or)"))
      eq({}, sel(buf, "(not)"))
    end)

    it("reads plain queries with stray punctuation", function()
      local buf = org_buffer({ "* TODO One", "* Two" })
      eq({ "One" }, sel(buf, "todo:"))
      eq({ "One" }, sel(buf, "todo:,,,"))
      eq({ "One", "Two" }, sel(buf, '""'))
      eq({}, sel(buf, "!"))
      eq({ "Two" }, sel(buf, "!todo:"))
    end)

    it("reads comments, quotes and escapes in sexps", function()
      eq({ "heading", 'a "b" c' }, query.read_sexp('(heading "a \\"b\\" c") ; trailing'))
      eq({ "heading", "x\ny" }, query.read_sexp('(heading "x\\ny")'))
      eq({ "todo" }, query.read_sexp("; comment\n(todo)"))
      eq({ "todo" }, query.read_sexp("`(todo)"))
    end)

    it("reads deeply nested queries", function()
      local q = string.rep("(not ", 200) .. "(todo)" .. string.rep(")", 200)
      local buf = org_buffer({ "* TODO One", "* Two" })
      eq({ "One" }, sel(buf, q))
    end)

    it("shows an invalid query instead of failing in search and the dblock", function()
      local msgs = notified(function()
        ql.search("(frobnicate)")
      end)
      ok(msgs[1] and msgs[1]:find("Invalid query", 1, true), msgs[1])
      local buf = org_buffer({ "* TODO One", '#+BEGIN: org-ql :query "(todo"', "#+END:" }, { 2, 0 })
      notified(function()
        require("org.dblock").update_at_cursor()
      end)
      eq({ "* TODO One", '#+BEGIN: org-ql :query "(todo"', "#+END:" }, buf_lines(buf))
    end)
  end)

  describe("empty and unusual files", function()
    it("selects nothing in an empty buffer or one without headlines", function()
      eq({}, sel(org_buffer({ "" }), "(todo)"))
      eq({}, sel(org_buffer({ "" }), "(and)"))
      eq({}, sel(org_buffer({ "#+TITLE: x", "just text", "TODO not a headline" }), '(rifle "text")'))
    end)

    it("selects nothing from missing files and globs that match nothing", function()
      eq({}, ql.files(dir .. "/missing.org"))
      eq({}, ql.files(dir .. "/nothing/*.org"))
      eq({}, ql.files({}))
      eq({}, ql.select({}, "(todo)"))
      eq({}, ql.select(dir .. "/missing.org", "(todo)"))
    end)

    it("selects from an agenda with no files", function()
      setup({ agenda_files = {} })
      eq({}, ql.select("agenda", "(todo)"))
    end)

    it("matches headlines with an empty title", function()
      local buf = org_buffer({ "* ", "* TODO", "** TODO :tag:", "*** [#A]" })
      eq(4, #sel(buf, "(and)"))
      eq(2, #sel(buf, "(todo)"))
      eq(1, #sel(buf, '(tags-local "tag")'))
      eq(1, #sel(buf, '(priority "A")'))
      eq(0, #sel(buf, '(heading "x")'))
    end)

    it("does not take src block lines for headlines", function()
      local buf = org_buffer({ "* TODO Real", "#+begin_src org", ",* TODO Fake", "#+end_src" })
      eq({ "Real" }, sel(buf, "(todo)"))
      eq({ "Real" }, sel(buf, '(src :lang "org")'))
    end)

    it("searches an empty buffer view without errors", function()
      local buf = org_buffer({ "" })
      ok(vim.api.nvim_buf_is_valid(buf))
      ql.search("(todo)", { files = "buffer" })
      ok(vim.bo.filetype == "orgagenda")
    end)
  end)

  describe("unicode", function()
    it("matches unicode headings, tags, properties and categories", function()
      local buf = org_buffer({
        "* TODO Größe prüfen :übung:日本:",
        "  :PROPERTIES:",
        "  :CATEGORY: Küche",
        "  :ÉTAT: prêt",
        "  :END:",
        "  Notizen über Käse 🧀",
        "* TODO Other",
      })
      eq({ "Größe prüfen" }, sel(buf, '(heading "größe")'))
      eq({ "Größe prüfen" }, sel(buf, '(tags "übung")'))
      eq({ "Größe prüfen" }, sel(buf, "tags:日本"))
      eq({ "Größe prüfen" }, sel(buf, '(category "Küche")'))
      eq({ "Größe prüfen" }, sel(buf, '(property "ÉTAT" "prêt")'))
      eq({ "Größe prüfen" }, sel(buf, "🧀"))
      eq({ "Größe prüfen" }, sel(buf, '(regexp "K.se")'))
      eq({ "Größe prüfen" }, sel(buf, '(tags-regexp "^üb")'))
    end)

    it("folds case of non-ASCII letters, as Emacs does", function()
      local buf = org_buffer({ "* TODO Größe PRÜFEN", "  ÜBER Käse", "* TODO Other" })
      eq({ "Größe PRÜFEN" }, sel(buf, '(heading "prüfen")'))
      eq({ "Größe PRÜFEN" }, sel(buf, '(heading "GRÖßE")'))
      eq({ "Größe PRÜFEN" }, sel(buf, "über"))
      eq({ "Größe PRÜFEN" }, sel(buf, '(rifle "KÄSE")'))
      eq({ "Größe PRÜFEN" }, sel(buf, '(outline-path "größe")'))
    end)
  end)

  describe("very long input", function()
    it("matches in very long headlines and body lines", function()
      local long = string.rep("word ", 20000)
      local buf = org_buffer({ "* TODO " .. long .. "needle", "  " .. long .. "haystack", "* TODO Other" })
      eq(1, #sel(buf, '(heading "needle")'))
      eq(1, #sel(buf, '(rifle "haystack")'))
      eq(1, #sel(buf, '(regexp "hay.tack")'))
    end)

    it("selects in a deep outline and in a file of many headlines", function()
      local lines = {}
      for k = 1, 60 do
        lines[#lines + 1] = string.rep("*", k) .. " TODO L" .. k
      end
      local buf = org_buffer(lines)
      eq({ "L60" }, sel(buf, "(level 60)"))
      eq({ "L60" }, sel(buf, '(outline-path-segment "L58" "L59" "L60")'))
      eq(59, #sel(buf, '(ancestors (heading "L1"))'))
      lines = {}
      for k = 1, 5000 do
        lines[#lines + 1] = "* " .. (k % 2 == 0 and "TODO" or "DONE") .. " Item " .. k
      end
      buf = org_buffer(lines)
      eq(2500, #sel(buf, "(todo)"))
      eq(2500, #sel(buf, "(done)", { sort = "todo" }))
    end)

    it("reads a query with thousands of terms", function()
      local terms = {}
      for k = 1, 2000 do
        terms[#terms + 1] = "!w" .. k
      end
      local buf = org_buffer({ "* TODO One" })
      eq({ "One" }, sel(buf, table.concat(terms, " ")))
    end)
  end)

  describe("unusual TODO keywords and priorities", function()
    it("matches keywords with punctuation and unicode", function()
      local buf = org_buffer({
        "#+TODO: IN-PROGRESS À_FAIRE | FINI",
        "* IN-PROGRESS One",
        "* À_FAIRE Two",
        "* FINI Three",
        "* TODO Not a keyword here",
      })
      eq({ "One" }, sel(buf, '(todo "IN-PROGRESS")'))
      eq({ "One" }, sel(buf, "todo:IN-PROGRESS"))
      eq({ "Two" }, sel(buf, '(todo "À_FAIRE")'))
      eq({ "One", "Two" }, sel(buf, "(todo)"))
      eq({ "Three" }, sel(buf, "(done)"))
      -- keywords are case-sensitive, as in Org
      eq({}, sel(buf, '(todo "in-progress")'))
      eq({ "Three", "Two", "One" }, sel(buf, "(or (todo) (done))", { sort = { "todo", "reverse" } }))
    end)

    it("compares and sorts numeric priorities by value", function()
      local buf = org_buffer({
        "#+PRIORITIES: 1 20 10",
        "* TODO [#9] Nine",
        "* TODO [#10] Ten",
        "* TODO [#2] Two",
        "* TODO None",
      })
      -- a smaller number is a higher priority
      eq({ "Nine", "Two" }, sel(buf, '(priority \'> "10")'))
      eq({ "Ten" }, sel(buf, '(priority "10")'))
      eq({ "Two", "Nine", "Ten", "None" }, sel(buf, "(todo)", { sort = "priority" }))
    end)

    it("leaves entries without the sort key last", function()
      local buf = org_buffer({ "* TODO A", "* TODO [#A] B", "* C", "  DEADLINE: <2026-01-01 Thu>" })
      eq({ "B", "A", "C" }, sel(buf, "(and)", { sort = "priority" }))
      eq({ "C", "A", "B" }, sel(buf, "(and)", { sort = "deadline" }))
      eq({ "A", "B", "C" }, sel(buf, "(and)", { sort = "closed" }))
    end)

    it("reports an unknown sorter and keeps the order", function()
      local buf = org_buffer({ "* TODO A", "* TODO B" })
      local res
      notified(function()
        res = sel(buf, "(todo)", { sort = "frobnicate" })
      end)
      eq({ "A", "B" }, res)
    end)
  end)

  describe("saved views", function()
    it("ignores a views file that is not JSON or not an object", function()
      for _, text in ipairs({ "not json", "", "[1, 2]", "42", '{"v": 5}', '{"v": {"title": "no query"}}' }) do
        utils.writefile(dir .. "/views.json", { text })
        local msgs = notified(function()
          ql.view("v")
        end)
        ok(#msgs > 0, text)
      end
    end)

    it("works with views turned off", function()
      setup({ extensions = { ql = { views_file = false } } })
      eq({}, ql.saved_views())
      local msgs = notified(function()
        eq(false, ql.save_view("x", { query = "(todo)" }))
      end)
      ok(msgs[1])
    end)

    it("saves and reads views with unicode names", function()
      eq(true, ql.save_view("Küche 日本", { query = "(todo)" }))
      eq("(todo)", ql.saved_views()["Küche 日本"].query)
    end)
  end)

  describe("dynamic block", function()
    it("writes an empty table when nothing matches", function()
      local buf = org_buffer({ "* One", "#+BEGIN: org-ql :query (todo)", "#+END:" }, { 2, 0 })
      require("org.dblock").update_at_cursor()
      local lines = buf_lines(buf)
      eq("| Heading | Todo |", lines[3])
      eq("#+END:", lines[5])
    end)

    it("escapes a | in a heading", function()
      local buf = org_buffer({ "* TODO a | b", "#+BEGIN: org-ql :query (todo)", "#+END:" }, { 2, 0 })
      require("org.dblock").update_at_cursor()
      ok(buf_lines(buf)[5]:find("\\vert{}", 1, true), buf_lines(buf)[5])
    end)

    it("ignores a non-numeric :take", function()
      local buf = org_buffer({ "* TODO a", "* TODO b", "#+BEGIN: org-ql :query (todo) :take many", "#+END:" }, { 3, 0 })
      require("org.dblock").update_at_cursor()
      eq("#+END:", buf_lines(buf)[8])
    end)
  end)
end)
