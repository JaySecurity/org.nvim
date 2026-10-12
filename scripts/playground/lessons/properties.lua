-- What the playground recording of tutor/org/properties.org does,
-- exercise by exercise (see scripts/playground/record.lua for the step
-- format, and CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Properties: named values on headlines, and column view to see them." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "Coffee grinder" },
      { say = "{{org.set_property}} asks for a property name, then its value." },
      { key = "{{org.set_property}}" },
      { type = "Color" },
      { key = "<CR>" },
      { type = "red" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "Blue shirt" },
      { key = "j" },
      { say = "{{org.cycle}} on a folded drawer opens it." },
      { key = "{{org.cycle}}" },
      { at = ":Size:", col = "M" },
      { say = "{{org.shift_right}} on a property moves to its next allowed value." },
      { key = "{{org.shift_right}}" },
    },
  },
  {
    id = "1.3",
    steps = {
      { at = "Red shirt" },
      { say = "With allowed values, {{org.set_property}} offers them in a menu." },
      { key = "{{org.set_property}}" },
      { type = "Size" },
      { key = "<CR>" },
      { key = "1" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.4",
    steps = {
      { at = "Write the intro" },
      { say = "{{org.set_effort}} sets the Effort property: hours and minutes." },
      { key = "{{org.set_effort}}" },
      { type = "0:45" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.5",
    steps = {
      { at = "Old lamp" },
      { say = "{{org.delete_property}} removes a property, and the drawer once empty." },
      { key = "{{org.delete_property}}" },
      { key = "1" },
      { key = "<CR>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "Website" },
      { say = "{{org.column_view}} shows the subtree's properties as columns." },
      { key = "{{org.column_view}}" },
      { say = "The parent row sums the efforts below it: 2:00 and 1:30 make 3:30." },
      { say = "q closes column view and gives the headlines back." },
      { key = "q" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "Garden" },
      { key = "{{org.column_view}}" },
      { at = "Dig the beds" },
      { say = "l moves to the next column, n to the next allowed value." },
      { key = "l" },
      { key = "l" },
      { key = "n" },
      { say = "The new value is written in the drawer of Dig the beds." },
      { key = "q" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "Kitchen" },
      { key = "{{org.column_view}}" },
      { at = "Paint the walls" },
      { key = "l" },
      { say = "e edits the value under the cursor; the sum above follows." },
      { key = "e" },
      { type = "3:00" },
      { key = "<CR>" },
      { key = "q" },
    },
  },
  {
    id = "2.4",
    steps = {
      { at = "Report:" },
      { say = "{{emacs.insert_columnview}} writes the column view into the file." },
      { key = "{{emacs.insert_columnview}}" },
      { key = "<CR>" },
    },
  },
  {
    id = "2.5",
    steps = {
      { at = "#+BEGIN: columnview" },
      { say = "{{org.context_action}} on #+BEGIN: writes the table again, up to date." },
      { key = "{{org.context_action}}" },
    },
  },
}
