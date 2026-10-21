-- What the playground recording of tutor/org/links.org does, exercise by
-- exercise (see scripts/playground/record.lua for the step format, and
-- CONTRIBUTING.md, "Writing a tutor lesson").
return {
  {
    id = "intro",
    title = "Welcome",
    hold = 1.5,
    steps = { { say = "Links to pages, headlines, files and IDs, and files attached to entries." } },
  },
  {
    id = "1.1",
    steps = {
      { at = "- Before you go out", col = "shopping" },
      { say = "{{org.open_at_point}} follows the link to the headline it names." },
      { key = "{{org.open_at_point}}" },
    },
  },
  {
    id = "1.2",
    steps = {
      { at = "- Manual:", col = ":" },
      { key = "A <Esc>" },
      { say = "{{org.insert_link}} asks for the target, then for a description." },
      { key = "{{org.insert_link}}" },
      { type = "https://orgmode.org" },
      { key = "<CR>" },
      { type = "Org manual" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.3",
    steps = {
      { at = "- Visitors:", col = ":" },
      { key = "A <Esc>" },
      { say = "A link to a <<target>> is its text in double brackets." },
      { key = "{{org.insert_link}}" },
      { type = "door code" },
      { key = "<CR>" },
      { key = "<CR>" },
    },
  },
  {
    id = "1.4",
    steps = {
      { at = "Meeting notes" },
      { say = "{{org.store_link}} stores a link to the headline at the cursor." },
      { key = "{{org.store_link}}" },
      { at = "- Notes:", col = ":" },
      { key = "A <Esc>" },
      { say = "{{org.insert_last_stored_link}} inserts the link stored last." },
      { key = "{{org.insert_last_stored_link}}" },
    },
  },
  {
    id = "1.5",
    steps = {
      { at = "- Ideas:", col = ":" },
      { key = "A <Esc>" },
      { say = "A file: link names a file, relative to this one." },
      { key = "{{org.insert_link}}" },
      { type = "file:ideas.txt" },
      { key = "<CR>" },
      { key = "<CR>" },
    },
  },
  {
    id = "2.1",
    steps = {
      { at = "Project plan" },
      { say = "{{org.id_get_create}} gives the entry a unique ID property." },
      { key = "{{org.id_get_create}}" },
    },
  },
  {
    id = "2.2",
    steps = {
      { at = "Project plan", whole = true },
      { say = ":Org id_store_link stores a link that finds the entry by its ID." },
      { key = ":Org id_store_link<CR>" },
      { at = "- Plan:", col = ":" },
      { key = "A <Esc>" },
      { key = "{{org.insert_last_stored_link}}" },
    },
  },
  {
    id = "3.1",
    steps = {
      { at = "Receipts" },
      { say = "{{org.attach}} opens the attachment menu; n creates a new file." },
      { key = "{{org.attach}}" },
      { key = "n" },
      { type = "march.txt" },
      { key = "<CR>" },
      { key = "i" },
      { type = "Rent 800" },
      { key = "<Esc>" },
      -- :silent: the written message would show the recording's data
      -- directory
      { key = ":silent wq<CR>" },
    },
  },
  {
    id = "3.2",
    steps = {
      { at = "- March:", col = ":", whole = true },
      { key = "A <Esc>" },
      { say = "An attachment: link names a file in the entry's folder." },
      { key = "{{org.insert_link}}" },
      { type = "attachment:march.txt" },
      { key = "<CR>" },
      { key = "<CR>" },
      { say = "{{org.open_at_point}} on it opens the attached file." },
      { key = "{{org.open_at_point}}" },
    },
  },
}
