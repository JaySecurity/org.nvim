-- Edge cases of the present extension: empty and headline-less buffers,
-- unicode and very long lines, unusual TODO keywords, odd options and
-- slide numbers, and the source changing under the presentation.

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"))

local function setup(present)
  require("org").setup({
    org_directory = root .. "/tests/fixtures",
    agenda_files = { root .. "/tests/fixtures/*.org" },
    extensions = present ~= nil and { present = present } or nil,
  })
end

local slides = require("org.extensions.present.slides")
local present = require("org.extensions.present")

local function slide_lines()
  return buf_lines(present.state.buf)
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

-- The column the slide headline's highlight starts at.
local function heading_col()
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(present.state.buf, -1, 0, -1, { details = true })) do
    if m[4].hl_group == "OrgPresentHeading" then
      return m[3]
    end
  end
end

describe("present edge cases", function()
  describe("splitting", function()
    it("finds no slides in an empty file or one of blank lines", function()
      eq({}, slides.split({}, {}))
      eq({}, slides.split({ "" }, {}))
      eq({}, slides.split({ "", "   ", "\t" }, {}))
      eq({}, slides.split({ "#+STARTUP: showall", "#+TITLE:", "" }, {}))
    end)

    it("makes one title slide of a file without headlines", function()
      eq({ { first = 1, last = 2, title = true } }, slides.split({ "Just text", "more" }, {}))
      eq({}, slides.split({ "Just text" }, { title_slide = false }))
    end)

    it("splits on headlines with an empty title", function()
      local s = slides.split({ "* ", "text", "* TODO", "*" }, {})
      eq(2, #s)
      eq({ 1, 2 }, { s[1].first, s[1].last })
      -- a lone star is no headline: it stays on the slide before
      eq({ 3, 4 }, { s[2].first, s[2].last })
    end)

    it("handles slide levels below and above the outline", function()
      local lines = { "* A", "** B", "*** C" }
      -- no headline starts a slide: the whole file is the title slide
      eq({ { first = 1, last = 3, title = true } }, slides.split(lines, { slide_level = 0 }))
      eq(3, #slides.split(lines, { slide_level = 99 }))
    end)

    it("does not start slides at inline tasks", function()
      local lines = { "* A", string.rep("*", 15) .. " TODO Inline", string.rep("*", 15) .. " END", "* B" }
      local cfg = require("org.config").opts
      local saved = cfg.inlinetask_min_level
      cfg.inlinetask_min_level = 15
      local okk, s = pcall(slides.split, lines, { slide_level = 20 })
      cfg.inlinetask_min_level = saved
      assert(okk, s)
      eq(2, #s)
      eq({ 1, 3 }, { s[1].first, s[1].last })
    end)

    it("does not start slides inside blocks", function()
      local s = slides.split({ "* A", "#+begin_example", ",* not a slide", "#+end_example" }, {})
      eq(1, #s)
    end)

    it("finds the first slide for lines outside every slide", function()
      local s = slides.split({ "#+STARTUP: showall", "* A", "* B" }, {})
      eq(1, slides.find(s, 1))
      eq(1, slides.find(s, 99))
      eq(1, slides.find({}, 1))
    end)

    it("reads keywords with odd spacing and case", function()
      eq({ "title", "Talk" }, { slides.keyword("  #+TiTlE:   Talk   ") })
      eq({ "title", "" }, { slides.keyword("#+TITLE:") })
      eq({ "x-y_z", "v" }, { slides.keyword("#+X-Y_Z: v") })
      eq(nil, slides.keyword("#+ TITLE: no"))
      eq(nil, slides.keyword("# +TITLE: no"))
    end)
  end)

  describe("presenting", function()
    after_each(function()
      present.quit()
      setup()
      vim.cmd("enew!")
    end)

    it("warns and does not start on an empty buffer or one with nothing to show", function()
      setup({})
      for _, lines in ipairs({ { "" }, { "", "", "" }, { "#+STARTUP: showall" } }) do
        org_buffer(lines, { 1, 0 })
        local tabs = #vim.api.nvim_list_tabpages()
        local msgs = notified(function()
          present.start()
        end)
        eq(nil, present.state)
        eq(tabs, #vim.api.nvim_list_tabpages())
        ok(msgs[1] and msgs[1]:find("nothing to present", 1, true), msgs[1])
      end
      -- the navigation actions are no-ops without a presentation
      eq(nil, present.state)
      ok(not present.next())
      ok(not present.prev())
      ok(not present.quit())
      ok(not present.toggle_one_big_page())
      ok(not present.big())
    end)

    it("clamps the slide number of :Org present", function()
      setup({})
      local deck = { "* One", "* Two", "* Three" }
      for _, c in ipairs({ { "0", 1 }, { "-5", 1 }, { "99", 3 }, { "abc", 2 }, { "", 2 } }) do
        org_buffer(deck, { 2, 0 })
        present.command(c[1])
        eq(c[2], present.state.index, c[1])
        present.quit()
      end
    end)

    it("presents unicode headings and very long lines", function()
      setup({})
      local long = string.rep("très long ", 2000)
      org_buffer({ "* Überschrift 🎉 日本語", long, "* " .. long }, { 1, 0 })
      present.start()
      eq({ "* Überschrift 🎉 日本語", long }, slide_lines())
      eq("Überschrift 🎉 日本語", present.state.heading)
      eq(2, heading_col())
      present.next()
      eq({ "* " .. long }, slide_lines())
      -- the underline is never wider than the window
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(present.state.buf, -1, 0, -1, { details = true })) do
        local vl = m[4].virt_lines
        if vl and vl[1][1] and vl[1][1][2] == "OrgPresentUnderline" then
          ok(vim.fn.strdisplaywidth(vl[1][1][1]) <= vim.api.nvim_win_get_width(present.state.win))
        end
      end
    end)

    it("keeps the colour of unusual TODO keywords", function()
      setup({})
      org_buffer(
        { "#+TODO: À-FAIRE IN_PROGRESS | FINI", "* À-FAIRE Write", "* IN_PROGRESS [#A] Talk", "* FINI" },
        { 2, 0 }
      )
      present.start()
      -- the #+TODO line is hidden: no title slide
      eq(1, present.state.index)
      eq(#"* À-FAIRE ", heading_col())
      present.next()
      eq(#"* IN_PROGRESS ", heading_col())
      present.next()
      eq({ "* FINI" }, slide_lines())
      -- a headline that is only a keyword (it used to fail to render)
      eq(#"* FINI", heading_col())
    end)

    it("does not take a keyword-like word in the title for the TODO keyword", function()
      setup({})
      org_buffer({ "* Write TODO list" }, { 1, 0 })
      present.start()
      eq(2, heading_col())
      eq("Write TODO list", present.state.heading)
    end)

    it("starts with unusual width options", function()
      for _, w in ipairs({ 0, -10, 0.5, 100000 }) do
        setup({ width = w })
        org_buffer({ "* A" }, { 1, 0 })
        present.start()
        local width = vim.api.nvim_win_get_width(present.state.win)
        ok(width >= math.min(20, vim.o.columns) and width <= vim.o.columns, tostring(w))
        present.quit()
      end
    end)

    it("keeps a usable view when the source is emptied", function()
      setup({})
      local src = org_buffer({ "* One", "text", "* Two" }, { 1, 0 })
      present.start()
      vim.api.nvim_buf_set_lines(src, 0, -1, false, {})
      present.next()
      eq(1, #present.state.slides)
      eq(1, present.state.index)
      eq({ "" }, slide_lines())
      present.prev()
      present.toggle_one_big_page()
      present.toggle_one_big_page()
      vim.api.nvim_buf_set_lines(src, 0, -1, false, { "* Back" })
      present.first()
      eq({ "* Back" }, slide_lines())
      present.quit()
      eq({ "* Back" }, buf_lines(src))
    end)

    it("presents a single slide and stays on it", function()
      setup({})
      org_buffer({ "* Only" }, { 1, 0 })
      present.start()
      present.next()
      present.prev()
      present.last()
      present.first()
      eq(1, present.state.index)
      eq("%=%#OrgPresentCounter#1/1 ", vim.wo[present.state.win].winbar)
    end)

    it("does not fail when a hook throws", function()
      setup({
        on_start = function()
          error("boom")
        end,
        on_slide = function()
          error("boom")
        end,
      })
      org_buffer({ "* A", "* B" }, { 1, 0 })
      local msgs = notified(function()
        present.start()
        present.next()
      end)
      eq(2, present.state.index)
      ok(#msgs >= 2)
      ok(msgs[1]:find("callback failed", 1, true), msgs[1])
    end)
  end)
end)
