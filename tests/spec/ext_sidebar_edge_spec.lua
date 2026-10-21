-- Edge cases of the sidebar extension: no agenda files, an empty day, a
-- missing inbox, unicode, many entries, malformed options, narrow windows.
local date = require("org.date")
local utils = require("org.utils")
local sidebar = require("org.extensions.sidebar")

local root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h"))

local today = date.today_days()
local function day(offset)
  return date.from_days(today + offset):to_string({ brackets = false })
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/edge.org"
local inbox = dir .. "/inbox.org"

local LINES = {
  "* TODO 会議の準備をする、とても長いタイトルで幅を超える 🗓️ :仕事:",
  "  SCHEDULED: <" .. day(0) .. " 11:00>",
  "* TODO Réunion équipe",
  "  DEADLINE: <" .. day(0) .. ">",
  "* TODO",
  "  SCHEDULED: <" .. day(0) .. ">",
}

local function write(lines, inbox_lines)
  for _, p in ipairs({ path, inbox }) do
    local b = utils.find_buffer(p)
    if b then
      vim.api.nvim_buf_delete(b, { force = true })
    end
    require("org.files").invalidate(p)
  end
  utils.writefile(path, lines or LINES)
  if inbox_lines then
    utils.writefile(inbox, inbox_lines)
  else
    vim.fn.delete(inbox)
  end
end

local function setup(ext, o)
  o = o or {}
  require("org").setup({
    org_directory = dir,
    agenda_files = o.files or { path },
    -- never the default notes file of the machine running the specs
    default_notes_file = o.notes or (dir .. "/no-notes.org"),
    todo_keywords = { "TODO NEXT | DONE" },
    extensions = { sidebar = ext },
  })
end

local function restore()
  require("org").setup({
    org_directory = root .. "/tests/fixtures",
    agenda_files = { root .. "/tests/fixtures/*.org" },
  })
end

local real_now = date.now
local function fake_now()
  return date.today():clone({ hour = 10, min = 0 })
end

local function text(st)
  return table.concat(buf_lines(st.buf), "\n")
end

--- Every line of the sidebar fits its window.
local function fits(st)
  local w = vim.api.nvim_win_get_width(st.win)
  for _, l in ipairs(buf_lines(st.buf)) do
    -- the title line keeps the date; the rest must fit
    if not l:find("Today", 1, true) then
      ok(vim.fn.strdisplaywidth(l) <= w, ("%q is wider than %d"):format(l, w))
    end
  end
end

describe("sidebar edge cases", function()
  before_each(function()
    write()
    date.now = fake_now
    vim.cmd("silent! only")
    vim.cmd("enew!")
  end)
  after_each(function()
    date.now = real_now
    sidebar.close()
    vim.cmd("silent! only")
    restore()
  end)

  it("opens without agenda files or a notes file", function()
    vim.fn.delete(dir .. "/no-notes.org")
    setup({}, { files = {} })
    local st = sidebar.open()
    ok(st)
    local s = text(st)
    ok(s:find("not clocked in", 1, true), s)
    ok(s:find("nothing else today", 1, true), s)
    ok(s:find("nothing planned", 1, true), s)
    ok(s:find("all done", 1, true), s)
    ok(not s:find("Inbox", 1, true), s)
  end)

  it("shows an empty day", function()
    write({ "* TODO Some day", "* DONE Done long ago", "  CLOSED: [2001-01-01 Mon 10:00]" })
    setup({})
    local s = text(sidebar.open())
    ok(s:find("nothing planned", 1, true), s)
    ok(not s:find("Some day", 1, true), s)
  end)

  it("leaves out the inbox when the inbox file is missing", function()
    setup({ inbox_file = dir .. "/missing.org" })
    local st = sidebar.open()
    ok(not text(st):find("Inbox", 1, true))
    -- the health check warns about it
    local warned
    sidebar.health({
      warn = function(m)
        warned = m
      end,
      ok = function() end,
    }, { inbox_file = dir .. "/missing.org" })
    ok(warned and warned:find("missing.org", 1, true))
  end)

  it("counts an empty inbox and one with a single entry", function()
    write(nil, {})
    setup({}, { notes = inbox })
    ok(text(sidebar.open()):find("Inbox  0 entries", 1, true))
    sidebar.close()
    write(nil, { "* 📥 Ünïcode idea" })
    setup({}, { notes = inbox })
    ok(text(sidebar.open()):find("Inbox  1 entry", 1, true))
  end)

  it("cuts wide unicode titles to the window", function()
    setup({ width = 24 })
    local st = sidebar.open()
    local s = text(st)
    ok(s:find("会議", 1, true), s)
    ok(s:find("Réuni", 1, true), s)
    fits(st)
  end)

  it("draws a headline without a title", function()
    setup({})
    local st = sidebar.open()
    ok(text(st):find("TODO", 1, true))
    fits(st)
  end)

  it("fits a window much narrower than its width option", function()
    setup({ width = 40 })
    local st = sidebar.open()
    vim.api.nvim_win_set_width(st.win, 8)
    sidebar.refresh()
    ok(text(st):find("Agenda", 1, true))
  end)

  it("lists many entries and jumps to the right one", function()
    local lines = {}
    for i = 1, 200 do
      lines[#lines + 1] = ("* TODO Task %03d ✓"):format(i)
      lines[#lines + 1] = "  SCHEDULED: <" .. day(0) .. ">"
    end
    write(lines)
    setup({ sections = { "today" } })
    local st = sidebar.open()
    local s = text(st)
    ok(s:find("Agenda  200", 1, true), s:sub(1, 200))
    local row
    for i, l in ipairs(buf_lines(st.buf)) do
      if l:find("Task 137", 1, true) then
        row = i
      end
    end
    ok(row)
    vim.api.nvim_set_current_win(st.win)
    vim.api.nvim_win_set_cursor(st.win, { row, 0 })
    sidebar.jump()
    eq("* TODO Task 137 ✓", vim.api.nvim_get_current_line())
  end)

  it("does nothing on a line that is not an entry", function()
    setup({})
    local st = sidebar.open()
    vim.api.nvim_set_current_win(st.win)
    for _, row in ipairs({ 1, 2 }) do
      vim.api.nvim_win_set_cursor(st.win, { row, 0 })
      sidebar.jump()
      eq(st.win, vim.api.nvim_get_current_win())
    end
  end)

  it("draws only the title with no sections, and skips unknown ones", function()
    setup({ sections = {} })
    local st = sidebar.open()
    eq(1, #buf_lines(st.buf))
    sidebar.close()
    setup({ sections = { "bogus", "today", 42 } })
    st = sidebar.open()
    ok(text(st):find("Agenda", 1, true))
    ok(not text(st):find("Clock", 1, true))
  end)

  it("takes a single section name as a string", function()
    setup({ sections = "today" })
    local ok_open, st = pcall(sidebar.open)
    ok(ok_open, st)
    ok(text(st):find("Agenda", 1, true))
    ok(not text(st):find("Clock", 1, true))
  end)

  it("takes odd numbers for width and interval", function()
    for _, o in ipairs({
      { width = 0, interval = 0 },
      { width = -5, interval = -1 },
      { width = "abc", interval = "soon" },
      { width = 100000, interval = 1e9 },
      { width = "30", interval = "5" },
    }) do
      setup(o)
      local ok_open, st = pcall(sidebar.open)
      ok(ok_open, vim.inspect(o) .. ": " .. tostring(st))
      ok(st and vim.api.nvim_win_get_width(st.win) >= 1)
      ok(st.timer)
      sidebar.close()
    end
  end)

  it("takes an unknown position as right", function()
    setup({ position = "middle" })
    local prev = vim.api.nvim_get_current_win()
    local st = sidebar.open()
    ok(vim.api.nvim_win_get_position(st.win)[2] > vim.api.nvim_win_get_position(prev)[2])
  end)

  it("draws without icons", function()
    setup({ icons = {} })
    local st = sidebar.open()
    local s = text(st)
    ok(s:find(" Clock", 1, true), s)
    ok(s:find("Réunion", 1, true), s)
    fits(st)
  end)

  it("takes icons that are not a table", function()
    setup({ icons = false })
    local ok_open, st = pcall(sidebar.open)
    ok(ok_open, st)
    ok(text(st):find("Agenda", 1, true))
  end)

  it("lists every deadline from today with deadline_days = 0 or less", function()
    write({
      "* TODO Due today",
      "  DEADLINE: <" .. day(0) .. ">",
      "* TODO Due tomorrow",
      "  DEADLINE: <" .. day(1) .. ">",
      "* TODO Overdue",
      "  DEADLINE: <" .. day(-3) .. ">",
    })
    setup({ deadline_days = 0 })
    local s = text(sidebar.open())
    ok(s:find("Due today", 1, true))
    ok(s:find("Overdue", 1, true))
    ok(not s:find("Due tomorrow", 1, true))
    sidebar.close()
    setup({ deadline_days = -1 })
    s = text(sidebar.open())
    ok(s:find("Overdue", 1, true))
    ok(not s:find("Due today", 1, true))
  end)

  it("keeps working after an agenda file is deleted", function()
    setup({})
    local st = sidebar.open()
    vim.fn.delete(path)
    require("org.files").invalidate(path)
    local ok_r, err = pcall(sidebar.refresh)
    ok(ok_r, err)
    ok(text(st):find("nothing planned", 1, true), text(st))
  end)

  it("ignores malformed timestamps", function()
    write({
      "* TODO Broken",
      "  SCHEDULED: <2024-13-45 Xyz 25:99>",
      "* TODO Fine",
      "  SCHEDULED: <" .. day(0) .. " 23:59>",
    })
    setup({})
    local s = text(sidebar.open())
    ok(s:find("23:59 TODO Fine", 1, true), s)
  end)

  it("draws progress bars for any fraction", function()
    for _, f in ipairs({ -1, 0, 0.5, 1, 7, math.huge, -math.huge }) do
      local full, empty = sidebar.bar(f, 6)
      eq(6, vim.fn.strchars(full .. empty), tostring(f))
    end
    eq("", select(1, sidebar.bar(0.5, 0)))
  end)

  it("works without its keys", function()
    setup({ keys = { jump = false, refresh = false, close = false } })
    local ok_open, st = pcall(sidebar.open)
    ok(ok_open, st)
    ok(sidebar.is_open())
  end)

  it("survives its buffer being wiped", function()
    setup({})
    local st = sidebar.open()
    vim.api.nvim_buf_delete(st.buf, { force = true })
    eq(false, sidebar.is_open())
    eq(nil, sidebar.state)
    sidebar.refresh()
    sidebar.toggle()
    ok(sidebar.is_open())
  end)

  it("closes and reopens in a single-window tab", function()
    setup({})
    local st = sidebar.open()
    vim.cmd("tabnew")
    sidebar.toggle()
    ok(sidebar.is_open())
    ok(st.win ~= sidebar.state.win)
    -- the only other window is closed: the sidebar is the last one in the tab
    vim.cmd("wincmd p")
    vim.cmd("silent! only")
    ok(pcall(sidebar.close))
    eq(false, sidebar.is_open())
    vim.cmd("silent! tabonly")
  end)
end)
