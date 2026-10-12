-- What the playground recording of tutor/org/code.org does, exercise by
-- exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Code that runs inside your notes, and exports of them." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "#+begin_src" },
      { say = "{{org.context_action}} runs the block; y answers the question before it runs." },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "#+begin_src" },
      { say = "With :results output the result is what the code prints." },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "1.3",
    steps = {
      { at = "#+begin_src" },
      { say = "A list of rows comes back as an org table." },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "1.4",
    steps = {
      { at = "Your block" },
      { key = "j" },
      { say = "{{org.insert_structure_template}} inserts a block; s makes it a source block." },
      { key = "{{org.insert_structure_template}}" },
      { key = "s" },
      { type = "lua" },
      { key = "<Esc>" },
      { key = "o" },
      { type = "return 1 + 2" },
      { key = "<Esc>" },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "1.5",
    steps = {
      { at = "return", col = "World" },
      { say = "{{org.edit_special}} opens the code in a Lua buffer of its own." },
      { key = "{{org.edit_special}}" },
      { key = "ciw" },
      { type = "Ada" },
      { key = "<Esc>" },
      { say = "{{edit_src.save_exit}} writes the change back into the block." },
      { key = "{{edit_src.save_exit}}" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "#+begin_src" },
      { say = ":var data=prices hands the table to the block as a list of rows." },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "#+CALL" },
      { say = "#+CALL runs the named block with the values it gives." },
      { key = "{{org.context_action}}" },
      { key = "y" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "#+begin_src lua :var" },
      { say = "dice runs first, and its value becomes n." },
      { key = "{{org.context_action}}" },
      { key = "y" },
      { key = "y" },
    },
  },
  {
    id = "3.1",
    steps = {
      { say = "{{org.babel_tangle}} writes each block to the file its :tangle names." },
      { key = "{{org.babel_tangle}}" },
      { at = "[[file:" },
      { say = "The link opens the file it wrote; :q closes it." },
      { key = "{{org.open_at_point}}" },
      { key = ":q<CR>" },
    },
  },
  {
    id = "4.1",
    steps = {
      { at = "Trip notes" },
      { say = "{{org.export}} opens the export menu; s limits it to this subtree." },
      { key = "{{org.export}}" },
      { key = "s" },
      { key = "m" },
      { say = "M exports to a Markdown buffer, in a new window." },
      { key = "M" },
      { key = ":q<CR>" },
    },
  },
  {
    id = "4.2",
    steps = {
      { at = "is. Then export" },
      { key = "j" },
      { say = "An #+OPTIONS line sets how the whole file exports." },
      { key = "i" },
      { type = "#+OPTIONS: toc:nil num:nil author:nil" },
      { key = "<Esc>" },
      { at = "Packing" },
      { key = "{{org.export}}" },
      { key = "s" },
      { key = "t" },
      { say = "A gives plain text in a buffer: no contents, numbers or author." },
      { key = "A" },
      { key = ":q<CR>" },
    },
  },
  {
    id = "4.3",
    steps = {
      { at = "Private" },
      { say = "The noexport tag keeps a headline and its subtree out of exports." },
      { key = "{{org.set_tags}}" },
      { type = "noexport" },
      { key = "<CR>" },
      { at = "Diary" },
      { key = "{{org.export}}" },
      { key = "s" },
      { key = "m" },
      { key = "M" },
      { key = ":q<CR>" },
    },
  },
}
