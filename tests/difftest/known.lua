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
    oracle = "visibility",
    reason = [[The END line of an inline task ("*************** END") is hidden
      by Emacs in OVERVIEW and CONTENTS (S-TAB), shown by org.nvim.]],
    emacs = "h %*+ [Ee][Nn][Dd]",
    same = function(s)
      return each_line(s, function(l)
        return (l:gsub("^[hv] (%*%*%*%*%*%*%*%*%*%*%*%*%*%*%*+ [Ee][Nn][Dd])", "? %1"))
      end)
    end,
  },
  {
    oracle = "visibility",
    reason = [[A drawer before the first headline (:NOTES: ... :END:) is
      folded by Emacs on S-TAB, left open by org.nvim.]],
    input = "^:%u+:$",
    emacs = "h :END:",
  },
  {
    oracle = "export%-.*",
    reason = [[A macro that expands to nothing at the start of a line: Emacs
      expands macros before parsing, so the line can become empty (and
      split a paragraph) or stop continuing a list item; org.nvim parses
      first, and keeps the space after the macro at the start of the
      line. Only where the lines, list items and paragraphs break (and
      that space) differs.]],
    input = "^%s*{{{title}}}",
    broad = true,
    moves = true,
    same = function(s)
      return (s:gsub("</?p>", ""):gsub("</li>", ""):gsub("</[ou]l>", ""):gsub("%s+", ""))
    end,
  },
  {
    oracle = "export%-.*",
    reason = [[A description item whose tag is a macro that expands to nothing
      ("- {{{title}}} :: text"): Emacs expands macros before parsing, so
      it's a plain item; org.nvim exports a description item.]],
    input = "^%s*[%-%+] .*{{{title}}} ::",
    either = "::",
  },
  {
    oracle = "export%-latex",
    reason = [[The same (a description item whose tag is a macro that expands
      to nothing), where the LaTeX list ends: \end{description} in
      org.nvim.]],
    input = "^%s*[%-%+] .*{{{title}}} ::",
    emacs = "^\\end{itemize}$",
    ours = "^\\end{description}$",
  },
  {
    oracle = "agenda",
    reason = [[A headline that is only tags ("* :work:"): Emacs shows the tags
      as the title too, org.nvim an empty title.]],
    emacs = "%s(:[%w_@:]+:)%s+%1",
  },
  {
    oracle = "visibility",
    reason = [[Indented lines (sub-items, item bodies, blank lines between
      them) of a plain list before the first headline: org.nvim folds them
      on S-TAB, Emacs leaves them visible.]],
    emacs = "v  ",
    same = function(s)
      -- an indented line, or a blank one before an indented line (a
      -- blank line inside the list)
      local lines = vim.split(s, "\n", { plain = true })
      for i = #lines, 1, -1 do
        local l = lines[i]
        if l:match("^[hv]  +") then
          lines[i] = "?" .. l:sub(2)
        elseif l:match("^[hv] $") and (lines[i + 1] or ""):match("^%?  +") then
          lines[i] = "? "
        end
      end
      return table.concat(lines, "\n")
    end,
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
    oracle = "export%-.*",
    reason = [[A macro that expands to nothing ("{{{title}}}" without
      #+title) next to a space: Emacs drops the space (at the start or end
      of a paragraph or headline), org.nvim keeps it.]],
    input = "{{{title}}}",
    same = function(s)
      -- line by line: the lines break at the same places
      return each_line(s, function(l)
        return (vim.trim(l:gsub("  +", " ")):gsub("([>%[#{]) ", "%1"):gsub(" ([}<\\%]&])", "%1"))
      end)
    end,
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
