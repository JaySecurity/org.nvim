-- Minimized inputs found by the fuzz specs (fuzz_*_spec.lua).
describe("fuzz regressions", function()
  it("M-down from the blank lines after the last-but-one element keeps the cursor in the buffer", function()
    local buf = org_buffer({ "a", "", "", "#+title: x" }, { 2, 0 })
    require("org.element").drag_forward()
    eq({ "#+title: x", "", "", "a" }, buf_lines(buf))
    eq(4, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("S-M-up on the bracket of a CLOCK timestamp toggles it without an error", function()
    local line = "CLOCK: [2003-10-04 Fri 05:00]--[2003-10-04 Fri 23:30] => 18:30"
    local buf = org_buffer({ "* T", line }, { 2, 52 })
    eq(true, require("org.clock").timestamps_adjust_closest(-1))
    eq("CLOCK: [2003-10-04 Fri 05:00]--<2003-10-04 Fri 23:30> => 18:30", buf_lines(buf)[2])
  end)

  it("merge keeps a one-sided deletion of a property drawer's :END:", function()
    local merge = require("org.extensions.merge.merge")
    local base = { "** H", ":PROPERTIES:", ":END:", ":LOGBOOK:", ":END:" }
    local ours = { "** H", ":PROPERTIES:", ":LOGBOOK:", ":END:" }
    local res = merge.merge(base, ours, base)
    eq(0, res.conflicts)
    eq(ours, res.lines)
    res = merge.merge(base, base, ours)
    eq(ours, res.lines)
  end)

  it("the export parser reads no properties from a drawer that isn't a property drawer", function()
    local E = require("org.export.element")
    local function props(lines)
      return E.parse(lines).contents[1].props
    end
    -- org-property-drawer-re: property lines only, up to an :END: line
    eq({}, props({ "* H", ":PROPERTIES:", ":Effort: 1:00" }))
    eq({}, props({ "* H", ":PROPERTIES:", ":A: 1", "text", ":END:" }))
    eq({}, props({ "* H", ":PROPERTIES:", ":A: 1", ":B:2", ":END:" }))
    eq({ A = "1", B = "" }, props({ "* H", ":PROPERTIES:", ":A: 1", ":B:", ":END:" }))
    -- the same for the file's drawer and a property-drawer element
    eq({}, E.parse({ ":PROPERTIES:", ":A: 1" }).props)
    local data = E.parse({ "* H", ":PROPERTIES:", ":A: 1", "x", ":END:" })
    eq(0, #E.map(data, "property-drawer", function(n)
      return n
    end))
  end)

  it("the export parser reads a planning keyword after a broken timestamp", function()
    local E = require("org.export.element")
    local hl = E.parse({
      "*** x",
      "CLOSED: [2023-06-05 Wed  SCHEDULED: <2028-12-08 Fri> DEADLINE: <2020-03-14 Sat 15:00>",
    }).contents[1]
    -- org-element-planning-parser: each keyword takes the timestamp after
    -- it, or none
    eq("<2028-12-08 Fri>", hl.scheduled.raw_value)
    eq("<2020-03-14 Sat 15:00>", hl.deadline.raw_value)
    -- a keyword found again replaces the first one
    hl = E.parse({ "* x", "SCHEDULED: <2024-01-01 Mon> SCHEDULED: none" }).contents[1]
    eq(nil, hl.scheduled)
  end)
end)
