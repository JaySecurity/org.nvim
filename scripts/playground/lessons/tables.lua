-- What the playground recording of tutor/org/tables.org does, exercise by
-- exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Tables you can move around, reshape and compute, like a spreadsheet." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "| Milk", col = "Milk" },
      { key = "i" },
      { say = "{{org_insert.insert_tab}} jumps to the next field and lines the table up." },
      { key = "{{org_insert.insert_tab}}" },
      { key = "{{org_insert.insert_tab}}" },
      { type = "1.20" },
      { key = "<Esc>" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "| Eggs", col = "Eggs" },
      { key = "i" },
      { key = "{{org_insert.insert_tab}}" },
      { type = "12" },
      { say = "<CR> goes down to the same field of the next row." },
      { key = "<CR>" },
      { type = "3" },
      { key = "<Esc>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "| Item", col = "Qty" },
      { say = "{{org.meta_left}} moves the column at the cursor to the left." },
      { key = "{{org.meta_left}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "| Coffee", col = "Coffee" },
      { say = "{{org.meta_up}} moves the row up, like a headline." },
      { key = "{{org.meta_up}}" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "| Item", col = "Notes" },
      { say = "{{org.shift_meta_left}} deletes the column at the cursor." },
      { key = "{{org.shift_meta_left}}" },
    },
  },
  {
    id = "2.4",
    steps = {
      { at = "| Old", col = "Old" },
      { say = "{{org.shift_meta_up}} deletes the row, {{org.shift_meta_down}} inserts one." },
      { key = "{{org.shift_meta_up}}" },
    },
  },
  {
    id = "2.5",
    steps = {
      { at = "| Day", col = "Day" },
      { say = "{{org.table_insert_hline}} draws a separator line under the row." },
      { key = "{{org.table_insert_hline}}" },
    },
  },
  {
    id = "2.6",
    steps = {
      { at = "| Ana", col = "12" },
      { say = "{{org.table_sort}} sorts by this column; N is by number, largest first." },
      { key = "{{org.table_sort}}" },
      { key = "N" },
    },
  },
  {
    id = "3.1",
    steps = {
      { at = "| Apples", col = "Apples" },
      { key = "i" },
      { key = "{{org_insert.insert_tab}}" },
      { key = "{{org_insert.insert_tab}}" },
      { key = "{{org_insert.insert_tab}}" },
      { say = "A field typed as =formula becomes the formula of its column." },
      { type = "=$2*$3" },
      { key = "{{org_insert.insert_tab}}" },
      { key = "<Esc>" },
    },
  },
  {
    id = "3.2",
    steps = {
      { at = "| 10", col = " 0 |" },
      { say = "{{emacs.table_formula}} asks for the formula of this column." },
      { key = "{{emacs.table_formula}}" },
      { type = "$1*0.62" },
      { key = "<CR>" },
    },
  },
  {
    id = "3.3",
    steps = {
      { at = "| Apples", col = "Apples" },
      { say = "{{org.table_recalc}} recalculates every formula of the table." },
      { key = "{{org.table_recalc}}" },
    },
  },
  {
    id = "3.4",
    steps = {
      { at = "| Sum", col = "Sum" },
      { key = "i" },
      { key = "{{org_insert.insert_tab}}" },
      { say = "A field typed as :=formula gets a formula of its own." },
      { type = ":=vsum(@2..@-1)" },
      { key = "<Esc>" },
      { key = "{{org.context_action}}" },
    },
  },
  {
    id = "3.5",
    steps = {
      { at = "#+TBLFM:" },
      { key = "A" },
      { say = "After a semicolon, %.2f rounds the result to two decimals." },
      { type = ";%.2f" },
      { key = "<Esc>" },
      { key = "{{org.context_action}}" },
    },
  },
  {
    id = "4.1",
    steps = {
      { at = "city" },
      { key = "V" },
      { key = "jj" },
      { say = "{{org.table_create}} on selected comma-separated lines makes a table." },
      { key = "{{org.table_create}}" },
    },
  },
}
