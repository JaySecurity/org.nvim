-- Checks and hints of the exercises of tutor/org/workflow.org, by
-- exercise number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a
-- tutor lesson"). Exercises without a check get no mark.

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    -- the captured entry goes next to or under Inbox
    ["1.1"] = { min_headings = 2 },
    ["2.1"] = { heading = "Call the dentist", todo = "DONE" },
    ["2.2"] = { heading = "Water the plants", scheduled = true },
    ["3.1"] = { heading = "Write the report", clocked = true },
    ["3.2"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.lines) do
          if line:lower():match("^%s*#%+begin:%s+clocktable") then
            return true
          end
        end
        return false
      end,
    },
  },
  hints = {
    ["1.1"] = "On Inbox run :Org capture_here, press t, type a title, then {{capture.finalize}}.",
    ["2.1"] = "Press {{global.agenda}}, <, t; on Call the dentist press {{agenda.todo}}, then {{agenda.quit}}.",
    ["2.2"] = "On Water the plants press {{org.schedule}} and <CR>; then {{global.agenda}}, <, a.",
    ["3.1"] = "On Write the report press {{org.clock_in}}, wait a moment, then {{org.clock_out}}.",
    ["3.2"] = "On Time spent press {{org.clock_report}}; change subtree to file, {{org.context_action}} on #+BEGIN:.",
  },
}
