-- Checks and hints of the exercises of tutor/org/dates.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson"). Exercises without a check get no mark. The reader's dates
-- are their own today's, so the checks look for the shape of a date.

--- A check that a line of the exercise starting with `start` (after
--- blanks) matches `pattern`.
---@param start string
---@param pattern string
---@return org.tutor.Condition
local function line_matches(start, pattern)
  return {
    fn = function(ctx)
      for _, line in ipairs(ctx.lines) do
        local rest = line:match("^%s*(.*)$")
        if rest:sub(1, #start) == start and rest:find(pattern) then
          return true
        end
      end
      return false
    end,
  }
end

local DATE = "%d%d%d%d%-%d%d%-%d%d"

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = line_matches("- Dentist:", "<" .. DATE),
    ["1.2"] = { heading = "Call the plumber", scheduled = true },
    ["1.3"] = line_matches("- Lunch with Ana:", "<" .. DATE .. " %a+ %d%d?:%d%d>"),
    ["1.4"] = line_matches("- Bought the tickets:", "%[" .. DATE),
    ["2.1"] = { contains = "<2026-10-14 Wed>" },
    ["2.2"] = { contains = "<2026-10-12 Mon 11:00>" },
    ["3.1"] = { heading = "Water the plants", contains = "<2026-10-12 Mon +1w>" },
    ["3.2"] = { heading = "Take out the bins", todo = "TODO", contains = "<2026-10-19 Mon +1w>" },
    -- the new date is the reader's tomorrow: only check that it moved
    ["3.3"] = {
      { heading = "Stretch", todo = "TODO", contains = "LAST_REPEAT" },
      {
        fn = function(ctx)
          return not table.concat(ctx.lines, "\n"):find("<2026-10-05 Mon .+1d>", 1, true)
        end,
      },
    },
    ["4.1"] = { contains = "<2026-10-20 Tue -3d>" },
    ["4.2"] = line_matches("- Holiday:", "<" .. DATE .. " %a+>%-%-<" .. DATE .. " %a+>"),
    ["4.3"] = line_matches("- Meeting:", "<" .. DATE .. " %a+ 14:00%-15:30>"),
  },
  hints = {
    ["1.1"] = "At the end of Dentist: press {{org.timestamp}}, then <CR>.",
    ["1.2"] = "On Call the plumber press {{org.schedule}}, i, type +2d, then <CR>.",
    ["1.3"] = "At the end of Lunch with Ana: press {{org.timestamp}}, i, type fri 12:30, then <CR>.",
    ["1.4"] = "At the end of Bought the tickets: press {{org.timestamp_inactive}}, then <CR>.",
    ["2.1"] = "On the date press {{org.shift_right}} twice.",
    ["2.2"] = "On the 10 of 10:00 press {{org.shift_up}}.",
    ["3.1"] = "On the > of the date press i, type a space and +1w, then <Esc>.",
    ["3.2"] = "On Take out the bins press {{org.todo_next}}.",
    ["3.3"] = "On Stretch press {{org.todo_next}}.",
    ["4.1"] = "On the > of the deadline press i, type a space and -3d, then <Esc>.",
    ["4.2"] = "At the end of Holiday: press {{org.timestamp}}, <CR>, {{org.timestamp}}, l, l, <CR>.",
    ["4.3"] = "At the end of Meeting: press {{org.timestamp}}, i, type 14:00-15:30, then <CR>.",
    ["4.4"] = "Press {{global.agenda}}, <, a; {{agenda.quit}} closes the agenda.",
  },
}
