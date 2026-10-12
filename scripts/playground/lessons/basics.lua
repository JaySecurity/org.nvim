-- What the playground recording of tutor/org/basics.org does, exercise by
-- exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "A real org file: do each exercise and a ✓ appears on its headline." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "Kitchen" },
      { say = "{{org.cycle}} on a headline cycles it: folded, its children, everything." },
      { key = "{{org.cycle}}" },
      { key = "{{org.cycle}}" },
      { key = "{{org.cycle}}" },
      { mark = "The whole file" },
      { say = "{{org.global_cycle}} does the same for the whole file." },
      { key = "{{org.global_cycle}}" },
      { key = "{{org.global_cycle}}" },
      { key = "{{org.global_cycle}}" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "Apples", col = "Apples" },
      { say = "{{org.meta_return}} opens a new headline below, in Insert mode." },
      { key = "{{org.meta_return}}" },
      { type = "Pears" },
      { key = "<Esc>" },
    },
  },
  {
    id = "1.3",
    steps = {
      { at = "Carrot" },
      { say = "{{org.demote_heading}} demotes a headline one level." },
      { key = "{{org.demote_heading}}" },
      { at = "Spoon" },
      { say = "{{org.promote_heading}} promotes it one level up." },
      { key = "{{org.promote_heading}}" },
    },
  },
  {
    id = "1.4",
    steps = {
      { at = "Tuesday" },
      { say = "{{org.meta_down}} moves the subtree down, past its next sibling." },
      { key = "{{org.meta_down}}" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "Buy milk" },
      { say = "{{org.todo_next}} cycles the keyword: TODO becomes DONE." },
      { key = "{{org.todo_next}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "Write a letter" },
      { say = "The same key makes a plain headline a TODO item." },
      { key = "{{org.todo_next}}" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "Pay rent" },
      { say = "{{org.priority}} asks for a priority: A is the highest." },
      { key = "{{org.priority}}" },
      { key = "A" },
    },
  },
  {
    id = "3.1",
    steps = {
      { at = "Prepare slides" },
      { say = "{{org.set_tags}} asks for tags: type one and press <CR>." },
      { key = "{{org.set_tags}}" },
      { type = "work" },
      { key = "<CR>" },
    },
  },
  {
    id = "4.1",
    steps = {
      { at = "Water the plants" },
      { say = "{{org.schedule}} opens the date prompt; <CR> takes today." },
      { key = "{{org.schedule}}" },
      { key = "<CR>" },
    },
  },
  {
    id = "4.2",
    steps = {
      { at = "File the tax return" },
      { say = "{{org.deadline}} adds a DEADLINE the same way." },
      { key = "{{org.deadline}}" },
      { key = "<CR>" },
    },
  },
  {
    id = "5.1",
    steps = {
      { at = "- Bread", col = "Bread" },
      { say = "In a list, {{org.meta_return}} adds an item below." },
      { key = "{{org.meta_return}}" },
      { type = "Butter" },
      { key = "<Esc>" },
    },
  },
  {
    id = "5.2",
    steps = {
      { at = "- [ ] Eggs", col = "Eggs" },
      { say = "{{org.context_action}} ticks the checkbox; the cookie counts the ticks." },
      { key = "{{org.context_action}}" },
    },
  },
  {
    id = "6.1",
    steps = {
      { at = "| Apple", col = "Apple" },
      { say = "{{org.context_action}} in a table lines its columns up." },
      { key = "{{org.context_action}}" },
    },
  },
  {
    id = "6.2",
    steps = {
      { at = "| Lemon", col = "Lemon" },
      { key = "A" },
      { say = "In Insert mode, {{org_insert.insert_tab}} past the last field opens a new row." },
      { key = "{{org_insert.insert_tab}}" },
      { type = "Kiwi" },
      { key = "{{org_insert.insert_tab}}" },
      { type = "5" },
      { key = "<Esc>" },
    },
  },
  {
    id = "7.1",
    steps = {
      { at = "Map:" },
      { key = "$" },
      { say = "{{org.insert_link}} asks for the link, then for its description." },
      { key = "{{org.insert_link}}" },
      { type = "*Treasure chest" },
      { key = "<CR>" },
      { type = "the treasure" },
      { key = "<CR>" },
      { key = "<Esc>" },
    },
  },
  {
    id = "7.2",
    steps = {
      { at = "Map:", col = "[[", whole = true },
      { say = "{{org.open_at_point}} on a link follows it: here, to a headline." },
      { key = "{{org.open_at_point}}" },
    },
  },
}
