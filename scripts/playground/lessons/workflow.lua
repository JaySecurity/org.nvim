-- What the playground recording of tutor/org/workflow.org does, exercise
-- by exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Capture, the agenda and the clock, all tried out in this one file." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "Inbox" },
      { say = ":Org capture_here files a capture at the cursor; t picks a template." },
      { key = ":Org capture_here<CR>" },
      { key = "t" },
      { type = "Call Bob" },
      { key = "<Esc>" },
      { say = "{{capture.finalize}} files the entry under Inbox." },
      { key = "{{capture.finalize}}" },
    },
  },
  {
    id = "2.1",
    steps = {
      { say = "{{global.agenda}} opens the agenda menu; < limits it to this file." },
      { key = "{{global.agenda}}" },
      { key = "<" },
      { key = "t" },
      { mark = "The TODO list" },
      { at = "Call the dentist", col = "Call the dentist" },
      { say = "{{agenda.todo}} marks the task DONE, in its file as well." },
      { key = "{{agenda.todo}}" },
      { key = "{{agenda.quit}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "Water the plants" },
      { say = "Schedule it for today, then find it in the week agenda: a." },
      { key = "{{org.schedule}}" },
      { key = "<CR>" },
      { key = "{{global.agenda}}" },
      { key = "<" },
      { key = "a" },
      { mark = "The week" },
      { key = "{{agenda.quit}}" },
    },
  },
  {
    id = "3.1",
    steps = {
      { at = "Write the report" },
      { say = "{{org.clock_in}} starts the clock on a task, {{org.clock_out}} stops it." },
      { key = "{{org.clock_in}}" },
      { wait = 25 },
      { key = "{{org.clock_out}}" },
      { at = ":LOGBOOK:" },
      { say = "The time goes in a CLOCK line, in the LOGBOOK drawer." },
      { key = "{{org.cycle}}" },
    },
  },
  {
    id = "3.2",
    steps = {
      { at = "Time spent" },
      { say = "{{org.clock_report}} inserts a clock table of this subtree." },
      { key = "{{org.clock_report}}" },
      -- zv: the child Neovim can show the new block folded (stale folds)
      { at = "#+BEGIN: clocktable", col = "subtree" },
      { key = "zv" },
      { say = "Make its scope the file, then {{org.context_action}} updates it." },
      { key = "ciw" },
      { type = "file" },
      { key = "<Esc>" },
      { key = "{{org.context_action}}" },
    },
  },
}
