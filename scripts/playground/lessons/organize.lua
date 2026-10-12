-- What the playground recording of tutor/org/organize.org does, exercise
-- by exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Refile, archive and search, all tried out in this one file." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "Buy stamps" },
      { say = "{{org.refile}} moves the subtree under a headline you pick." },
      { key = "{{org.refile}}" },
      { key = "2" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "Renew the passport" },
      { say = "{{org.refile_copy}} files a copy and keeps the original." },
      { key = "{{org.refile_copy}}" },
      { key = "2" },
      { key = "<CR>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "Old ideas" },
      { say = "{{org.toggle_archive_tag}} tags it ARCHIVE: it stays folded." },
      { key = "{{org.toggle_archive_tag}}" },
      { key = "{{org.cycle}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "Fix the fence" },
      { say = "{{emacs.archive_to_sibling}} moves it under the Archive sibling." },
      { key = "{{emacs.archive_to_sibling}}" },
    },
  },
  {
    id = "2.3",
    steps = {
      { at = "Pay the rent" },
      { say = "{{org.archive_subtree}} moves it to the archive file." },
      { key = "{{org.archive_subtree}}" },
    },
  },
  {
    id = "3.1",
    steps = {
      { say = "{{org.sparse_tree}} t shows only the open TODO entries." },
      { key = "{{org.sparse_tree}}" },
      { key = "t" },
    },
  },
  {
    id = "3.2",
    steps = {
      { say = "r searches for a regexp and opens the entries that have it." },
      { key = "{{org.sparse_tree}}" },
      { key = "r" },
      { type = "invoice" },
      { key = "<CR>" },
    },
  },
  {
    id = "3.3",
    steps = {
      { say = "m matches tags: the headlines tagged phone show." },
      { key = "{{org.sparse_tree}}" },
      { key = "m" },
      { type = "phone" },
      { key = "<CR>" },
    },
  },
  {
    id = "3.4",
    steps = {
      { say = "C clears the highlights; {{org.global_cycle}} shows the whole file." },
      { key = "{{org.sparse_tree}}" },
      { key = "C" },
      { key = "{{org.global_cycle}}" },
      { key = "{{org.global_cycle}}" },
      { key = "{{org.global_cycle}}" },
    },
  },
  {
    id = "4.1",
    steps = {
      { say = "{{org.buffer_goto}} shows the outline; type to search, <CR> to jump." },
      { key = "{{org.buffer_goto}}" },
      { type = "What next" },
      { key = "<CR>" },
      { key = "<CR>" },
    },
  },
  {
    id = "4.2",
    steps = {
      { at = "Packing list" },
      { say = "{{org.narrow_subtree}} opens the subtree alone, in an edit buffer." },
      { key = "{{org.narrow_subtree}}" },
      { key = "G" },
      { key = "o" },
      { type = "- Sunscreen" },
      { key = "<Esc>" },
      { say = "{{edit_src.save_exit}} writes it back and closes the edit buffer." },
      { key = "{{edit_src.save_exit}}" },
    },
  },
  {
    id = "4.3",
    steps = {
      { say = "In the agenda menu, m searches tags; < keeps it to this file." },
      { key = "{{global.agenda}}" },
      { key = "<" },
      { key = "m" },
      { type = "errand" },
      { key = "<CR>" },
      { at = "Return the books", col = "Return the books" },
      { say = "{{agenda.goto}} jumps to the entry in its file." },
      { key = "{{agenda.goto}}" },
    },
  },
}
