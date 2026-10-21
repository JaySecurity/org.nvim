-- Checks and hints of the exercises of tutor/org/agenda.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson").

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    -- any priority: the first press gives the default one (B)
    ["1.1"] = { heading = "Renew the passport", contains = "[#" },
    ["1.2"] = { heading = "Pay the rent", todo = "DONE" },
    ["2.1"] = {
      heading = "Call the bank",
      scheduled = true,
      -- scheduled again: not on the date the lesson gives it any more
      fn = function(ctx)
        for _, line in ipairs(ctx.lines) do
          if line:find("SCHEDULED:", 1, true) then
            return not line:find("2026-10-05", 1, true)
          end
        end
        return false
      end,
    },
    ["3.1"] = { heading = "Buy stamps", todo = "DONE" },
    ["3.2"] = { cursor = "Ask the plumber" },
    ["4.1"] = { { heading = "Tidy the shed", scheduled = true }, { heading = "Fix the bike", scheduled = true } },
    ["4.2"] = { { heading = "Send the report", deadline = true }, { heading = "Book the train", deadline = true } },
    ["5.1"] = { heading = "Read the manual", todo = "DONE" },
  },
  hints = {
    ["1.1"] = "Press {{global.agenda}}, <, t; on Renew the passport press {{agenda.priority_up}}.",
    ["1.2"] = "Press {{global.agenda}}, <, a; on Pay the rent press {{agenda.todo}}.",
    ["2.1"] = "Press {{global.agenda}}, <, a; on Call the bank press {{agenda.schedule}}, . and <CR>.",
    ["3.1"] = "Press {{global.agenda}}, <, m, type errand, <CR>; on Buy stamps press {{agenda.todo}}.",
    ["3.2"] = "Press {{global.agenda}}, <, s, type invoice, <CR>; then {{agenda.switch_to}} on the entry.",
    ["4.1"] = "In the TODO list press {{agenda.mark}} on both tasks, then {{agenda.bulk_action}}, s, +1d <CR>.",
    ["4.2"] = "In the TODO list: {{agenda.filter}} +work <CR>, {{agenda.mark_all}}, {{agenda.bulk_action}}, d, fri <CR>.",
    ["5.1"] = "Press {{global.agenda}}, <, n; on Read the manual press {{agenda.todo}}.",
  },
}
