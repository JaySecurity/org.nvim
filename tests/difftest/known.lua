-- Known differences between org.nvim and Emacs Org 9.8.10 that `make
-- difftest` finds on generated documents. A diff hunk matching an entry
-- doesn't fail the run (the report counts it); any other hunk does.
--
-- Intentional differences belong in NORMALISE (tests/emacs_parity.lua,
-- documented under :h org-differences), not here. This list is for real
-- bugs not fixed yet (or Emacs behaviour still to decide on): each entry
-- says what differs, and goes away with the fix. Keep the entries narrow,
-- so that they don't hide other bugs.
--
--   oracle  Lua pattern for the oracle name (anchored), e.g. "export%-.*"
--   emacs   Lua pattern searched in the hunk's Emacs lines (joined by \n)
--   ours    the same for org.nvim's lines
--   either  Lua pattern searched in the Emacs or in org.nvim's lines
--   input   Lua pattern one line of the input document must match, or a
--           function(lines) -> boolean
--   same    function(text) -> string: the hunk matches when both sides
--           (their lines joined by \n) are equal once rewritten by it
--   broad   the `same` rewrite erases a lot (digits, whitespace, line
--           order): when several rewrites apply to one hunk, it goes last
--   moves   the `same` rewrite sorts lines: the hunks left unknown (lines
--           moved between them) match together when it makes all their
--           lines equal
--   reason  what's wrong
-- Every field given must match. A hunk that no entry matches alone but
-- that all applicable `same` rewrites together make equal (two known
-- differences next to each other) is known too.
---@class difftest.Known
---@field oracle? string
---@field emacs? string
---@field ours? string
---@field either? string
---@field input? string|fun(lines: string[]): boolean
---@field same? fun(text: string): string
---@field broad? boolean
---@field moves? boolean
---@field reason string

local INLINETASK = "^%*%*%*%*%*%*%*%*%*%*%*%*%*%*%*+ "

--- `s` line by line through `fn`.
local function each_line(s, fn)
  local out = {}
  for _, l in ipairs(vim.split(s, "\n", { plain = true })) do
    out[#out + 1] = fn(l)
  end
  return table.concat(out, "\n")
end

--- Is there an active timestamp after an inline task's END line, before
--- the next heading?
local function timestamp_after_inline_end(lines)
  local after_end = false
  for _, l in ipairs(lines) do
    if l:match(INLINETASK .. "[Ee][Nn][Dd]%s*$") then
      after_end = true
    elseif l:match("^%*+ ") then
      after_end = false
    elseif after_end and l:match("<%d%d%d%d%-%d%d%-%d%d") then
      return true
    end
  end
  return false
end

---@type difftest.Known[]
return {
  {
    oracle = "agenda",
    reason = [[A headline that is only tags ("* :work:"): Emacs shows the tags
      as the title too, org.nvim an empty title.]],
    emacs = "%s(:[%w_@:]+:)%s+%1",
  },
  {
    oracle = "agenda",
    reason = [[A timestamp after an inline task's END line (in the text of
      the enclosing headline): Emacs' agenda titles it "END" (the line
      org-agenda-get-timestamps finds with org-outline-regexp-bol), org.nvim
      with the enclosing headline.]],
    input = timestamp_after_inline_end,
    emacs = "%sEND%f[%s:%z]",
  },
  {
    oracle = "commands",
    reason = [[org-todo on a COMMENT headline with tags: Emacs takes COMMENT
      out, changes the keyword, aligns the tags and puts COMMENT back
      without aligning again, so its tags end 8 columns past
      org-tags-column; org.nvim aligns them at tags_column. An Emacs bug,
      not copied.]],
    either = "%*+ %u+ [^\n]-COMMENT [^\n]-%s:[^%s]+:",
    same = function(s)
      return each_line(s, function(l)
        return (l:gsub("^(%*+ .-COMMENT .-)%s+(:[^%s]+:)$", "%1 %2"))
      end)
    end,
  },
  {
    oracle = "commands",
    reason = [[A timestamp with the wrong weekday (<2026-10-12 Fri>) on a
      planning line or next to a timestamp org.nvim changes: org.nvim
      writes it again with the right weekday, Emacs leaves its text
      alone.]],
    either = "%d%d%d%d%-%d%d%-%d%d %a%a%a",
    same = function(s)
      return (s:gsub("(%d%d%d%d%-%d%d%-%d%d) %a%a%a", "%1"))
    end,
  },
  {
    oracle = "commands",
    reason = [[Archiving the Archive sibling itself (C-c C-x A on "** Archive
      :ARCHIVE:"): Emacs finds that headline as its own Archive sibling,
      cuts it and pastes it one level deeper, under the previous sibling;
      org.nvim leaves it alone.]],
    emacs = "Archive%s+:ARCHIVE:\n:PROPERTIES:\n:ARCHIVE_TIME:",
  },
  {
    oracle = "commands",
    reason = [[Sorting the children of a headline whose text holds an inline
      task: Emacs (org-sort-entries) takes the inline task for the first
      child and sorts the entries of its level, so nothing moves; org.nvim
      sorts the children.]],
    input = function(lines)
      for _, l in ipairs(lines) do
        if l:match(INLINETASK) then
          return true
        end
      end
      return false
    end,
    either = "^%*+ ",
    same = function(s)
      local t = vim.split(s, "\n", { plain = true })
      table.sort(t)
      return table.concat(t, "\n")
    end,
    broad = true,
    moves = true,
  },
}
