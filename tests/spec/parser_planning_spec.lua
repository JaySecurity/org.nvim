-- parser.is_planning_line: the line test of org-planning-line-re.
local parser = require("org.parser")

describe("parser.is_planning_line", function()
  it("matches the three keywords after spaces or tabs", function()
    for _, l in ipairs({
      "SCHEDULED: <2024-01-01 Mon>",
      "DEADLINE: <2024-01-01 Mon>",
      "CLOSED: [2024-01-01 Mon]",
      "  SCHEDULED:",
      "\tDEADLINE: <2024-01-01 Mon>",
      " \t CLOSED: [2024-01-01 Mon] SCHEDULED: <2024-01-02 Tue>",
    }) do
      eq(true, parser.is_planning_line(l))
    end
  end)

  it("rejects other lines", function()
    for _, l in ipairs({
      "",
      "Text",
      "scheduled: <2024-01-01 Mon>", -- keywords are upper case
      "SCHEDULED <2024-01-01 Mon>", -- no colon
      "SCHED",
      "DEADLINES: <2024-01-01 Mon>",
      "NOTE: SCHEDULED: <2024-01-01 Mon>", -- must start the line
      "CLOCK: [2024-01-01 Mon 10:00]",
      "\fSCHEDULED: <2024-01-01 Mon>", -- only spaces and tabs, as [ \t]*
      "\rDEADLINE: <2024-01-01 Mon>",
    }) do
      eq(false, parser.is_planning_line(l))
    end
    eq(false, parser.is_planning_line(nil))
  end)

  it("is what parse_planning starts from", function()
    eq(nil, parser.parse_planning("NOTE: SCHEDULED: <2024-01-01 Mon>"))
    local p = parser.parse_planning("  DEADLINE: <2024-01-01 Mon>")
    ok(p and p.deadline)
  end)
end)
