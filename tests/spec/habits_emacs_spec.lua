-- Habit consistency graphs pinned to Emacs Org 9.8.10: org-habit-build-graph
-- over org-habit-parse-todo, drawn from (time-subtract nil ...) with "now"
-- at 2026-10-01 12:00 UTC and the default 21 preceding and 7 following
-- days. Each case is a habit's SCHEDULED line and its done dates; the
-- expected text and faces (per column, the blank last one left out) are
-- what Emacs prints for it.

local P = require("tests.emacs_parity")
local files = require("org.files")
local habits = require("org.agenda.habits")

local CASES = {
  {
    "a done date after the scheduled day",
    "SCHEDULED: <2026-09-21 +1d>",
    { "2026-09-29" },
    "                   * !       ",
    "cccccccccccaOOOOOOOOOOoooooo",
  },
  {
    ".+ with a maximum interval",
    "SCHEDULED: <2026-10-01 .+2d/4d>",
    { "2026-09-20", "2026-09-25", "2026-09-29" },
    "          *    *   * !       ",
    "ccccccccccRcrraOcrrRcRraoooo",
  },
  {
    "++ weekly",
    "SCHEDULED: <2026-10-05 ++1w>",
    { "2026-09-14", "2026-09-21", "2026-09-28" },
    "    *      *      *  !       ",
    "ccccRccccccRccccccRccCcccaoo",
  },
  {
    "+ overdue",
    "SCHEDULED: <2026-09-27 +3d>",
    { "2026-09-12", "2026-09-18" },
    "  *     *            !       ",
    "ccCcccccCccccccccaOOOOoooooo",
  },
  {
    ".+ with a done date before the graph",
    "SCHEDULED: <2026-09-30 .+1d>",
    { "2026-09-05", "2026-09-20" },
    "          *          !       ",
    "OOOOOOOOOOOcccccccccaOoooooo",
  },
  {
    "+ with a maximum interval, scheduled ahead",
    "SCHEDULED: <2026-10-03 +2d/5d>",
    { "2026-09-11", "2026-09-13", "2026-09-26" },
    " * *            *    !       ",
    "cRcCccccccccccccCccccCcrrrao",
  },
}

-- one letter per face: upper case for the face, lower case for its
-- Future variant
local LETTER = {
  C = "OrgAgendaHabitClear",
  R = "OrgAgendaHabitReady",
  A = "OrgAgendaHabitAlert",
  O = "OrgAgendaHabitOverdue",
}

local function expected_groups(letters)
  local out = {}
  for ch in letters:gmatch(".") do
    local base = LETTER[ch:upper()]
    out[#out + 1] = ch:match("%u") and base or (base .. "Future")
  end
  return out
end

describe("habit graphs (Emacs org-habit-build-graph)", function()
  P.freeze_time()

  for _, case in ipairs(CASES) do
    local name, scheduled, done, text, faces = unpack(case)
    it(name, function()
      local lines = { "* TODO Habit", scheduled, ":PROPERTIES:", ":STYLE: habit", ":END:" }
      for i = #done, 1, -1 do
        lines[#lines + 1] = ('- State "DONE"       from "TODO"       [%s 09:00]'):format(done[i])
      end
      local buf = org_buffer(lines)
      local h = habits.parse(files.get_buffer(buf).headlines[1])
      local g = habits.graph(h, require("org.date").today():days())
      local chars, groups = {}, {}
      for i, cell in ipairs(g) do
        chars[i] = cell[1]
        if i < #g then
          groups[i] = cell[2]
        end
      end
      eq(text, table.concat(chars))
      eq(expected_groups(faces), groups)
    end)
  end
end)
