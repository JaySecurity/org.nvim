-- What the playground recording of tutor/org/writing.org does, exercise
-- by exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Markup, paragraphs, blocks and footnotes, tried out in this file." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "This step", col = "important" },
      { key = "viw" },
      { say = "{{org.emphasize}} asks for a marker and puts it around the selection." },
      { key = "{{org.emphasize}}" },
      { key = "*" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "Notes:" },
      { key = "j" },
      { say = "With nothing selected, it opens a pair of markers to type in." },
      { key = "{{org.emphasize}}" },
      { key = "/" },
      { type = "in italics" },
      { key = "<Esc>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "Org files are plain" },
      { say = "gqip fills the paragraph: org.nvim keeps lists and comments intact." },
      { key = "gqip" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "First part" },
      { say = "Five dashes on a line of their own make a horizontal rule." },
      { key = "o" },
      { type = "-----" },
      { key = "<Esc>" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "Draft:" },
      { say = "gcc comments the line out with a #: it won't be exported." },
      { key = "gcc" },
    },
  },
  {
    id = "3.1",
    steps = {
      { key = "gg" },
      { say = "Keywords at the top of a file set its title, author and options." },
      { key = "o" },
      { type = "#+AUTHOR: Ada" },
      { key = "<Esc>" },
    },
  },
  {
    id = "3.2",
    steps = {
      { at = "Hope is", col = "Hope" },
      { key = "Vj" },
      { say = "{{org.insert_structure_template}} wraps the selection in a block; q is a quote." },
      { key = "{{org.insert_structure_template}}" },
      { key = "q" },
    },
  },
  {
    id = "3.3",
    steps = {
      { at = "Code:" },
      { key = "j" },
      { say = "On an empty line, s inserts a source block; the language goes first." },
      { key = "{{org.insert_structure_template}}" },
      { key = "s" },
      { type = "python" },
      { key = "<CR>" },
      { type = 'print("hello")' },
      { key = "<Esc>" },
    },
  },
  {
    id = "3.4",
    steps = {
      { at = 'print("hello")', col = "hello" },
      { say = "{{org.edit_special}} opens the code in a window with the language's own setup." },
      { key = "{{org.edit_special}}" },
      { key = "ciw" },
      { type = "world" },
      { key = "<Esc>" },
      { say = "{{edit_src.save_exit}} puts the code back in the block and closes the window." },
      { key = "{{edit_src.save_exit}}" },
    },
  },
  {
    id = "4.1",
    steps = {
      { at = "Tea is ready" },
      { key = "$" },
      { say = "{{org.insert_footnote}} adds a reference and jumps to its definition." },
      { key = "{{org.insert_footnote}}" },
      { type = "Green or black." },
      { key = "<Esc>" },
    },
  },
  {
    id = "4.2",
    steps = {
      { at = "Coffee with milk", col = "[fn:milk]" },
      { say = "On a reference, {{org.insert_footnote}} jumps to the definition." },
      { key = "{{org.insert_footnote}}" },
      { key = "A" },
      { type = " Just a drop." },
      { key = "<Esc>" },
      { key = "0" },
      { say = "On the definition's label, it jumps back to the reference." },
      { key = "{{org.insert_footnote}}" },
    },
  },
}
