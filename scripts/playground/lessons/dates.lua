-- What the playground recording of tutor/org/dates.org does, exercise by
-- exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson"). Today is Mon 2026-10-12.
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Dates: the prompt, shifting, repeaters, deadlines and ranges." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "- Dentist:" },
      { key = "$" },
      { say = "{{org.timestamp}} opens the calendar; <CR> picks the day shown." },
      { key = "{{org.timestamp}}" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "Call the plumber" },
      { say = "At the prompt, i types a date: +2d is two days from today." },
      { key = "{{org.schedule}}" },
      { key = "i" },
      { type = "+2d" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.3",
    steps = {
      { at = "- Lunch with Ana:" },
      { key = "$" },
      { say = "A weekday name is the next such day, with a time if you add one." },
      { key = "{{org.timestamp}}" },
      { key = "i" },
      { type = "fri 12:30" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.4",
    steps = {
      { at = "- Bought the tickets:" },
      { key = "$" },
      { say = "{{org.timestamp_inactive}} writes the date in brackets: the agenda skips it." },
      { key = "{{org.timestamp_inactive}}" },
      { key = "<CR>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "- Party:", col = "12" },
      { say = "{{org.shift_right}} moves the date a day later; the weekday follows." },
      { key = "{{org.shift_right}}" },
      { key = "{{org.shift_right}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "- Call:", col = "10:" },
      { say = "{{org.shift_up}} changes the part under the cursor: here the hour." },
      { key = "{{org.shift_up}}" },
    },
  },
  {
    id = "3.1",
    steps = {
      { at = "SCHEDULED: <2026-10-12 Mon>", col = ">" },
      { say = "A repeater after the date: +1w brings the task back every week." },
      { key = "i" },
      { type = " +1w" },
      { key = "<Esc>" },
    },
  },
  {
    id = "3.2",
    steps = {
      { at = "Take out the bins" },
      { say = "{{org.todo_next}} on a repeating task moves its date on a week." },
      { key = "{{org.todo_next}}" },
      { say = "It stays TODO; LAST_REPEAT and a note say when you did it." },
    },
  },
  {
    id = "3.3",
    steps = {
      { at = "Stretch" },
      { say = "With .+1d the next date counts from today: tomorrow." },
      { key = "{{org.todo_next}}" },
    },
  },
  {
    id = "4.1",
    steps = {
      { at = "DEADLINE: <2026-10-20 Tue>", col = ">" },
      { say = "-3d after a deadline: the agenda warns 3 days before, not 14." },
      { key = "i" },
      { type = " -3d" },
      { key = "<Esc>" },
    },
  },
  {
    id = "4.2",
    steps = {
      { at = "- Holiday:" },
      { key = "$" },
      { key = "{{org.timestamp}}" },
      { key = "<CR>" },
      { say = "{{org.timestamp}} again right away adds the end of a range." },
      { key = "{{org.timestamp}}" },
      { key = "l" },
      { key = "l" },
      { key = "<CR>" },
    },
  },
  {
    id = "4.3",
    steps = {
      { at = "- Meeting:" },
      { key = "$" },
      { say = "Two times with a dash make a time range on one day." },
      { key = "{{org.timestamp}}" },
      { key = "i" },
      { type = "14:00-15:30" },
      { key = "<CR>" },
    },
  },
  {
    id = "4.4",
    steps = {
      { say = "The week agenda of this file shows every active date of the lesson." },
      { key = "{{global.agenda}}" },
      { key = "<" },
      { key = "a" },
      { mark = "The week" },
      { key = "{{agenda.quit}}" },
    },
  },
}
