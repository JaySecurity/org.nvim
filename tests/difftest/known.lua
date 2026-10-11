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

--- `s` with all whitespace runs as one space.
local function squash(s)
  return (s:gsub("%s+", " "))
end

--- `s` line by line through `fn`.
local function each_line(s, fn)
  local out = {}
  for _, l in ipairs(vim.split(s, "\n", { plain = true })) do
    out[#out + 1] = fn(l)
  end
  return table.concat(out, "\n")
end

local function is_item(l)
  return l:match("^%s*[%-%+] ") or l:match("^%s*[%-%+]$") or l:match("^%s*%d+[%.%)] ") or l:match("^%s*%d+[%.%)]$")
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

--- Per line of `lines`, whether it's in a subtree that isn't exported
--- (a COMMENT headline or a :noexport: tag).
local function excluded_lines(lines)
  local out, level = {}, nil -- level: of the excluded subtree we're in
  for i, l in ipairs(lines) do
    local stars, rest = l:match("^(%*+) (.*)$")
    if stars and not l:match(INLINETASK) then
      if level and #stars <= level then
        level = nil
      end
      if not level then
        local r = rest
          :gsub("^%u+ ", function(kw)
            return kw == "COMMENT " and kw or ""
          end)
          :gsub("^%[#%a%] ", "")
        local tags = rest:match("%s(:[%w_@:]+:)$")
        if r:match("^COMMENT%f[%s%z]") or (tags and tags:find(":noexport:", 1, true)) then
          level = #stars
        end
      end
    end
    out[i] = level ~= nil
  end
  return out
end

--- Whether a footnote label is defined twice (in exported parts).
local function duplicate_footnotes(lines)
  local seen = {}
  local excluded = excluded_lines(lines)
  for i, l in ipairs(lines) do
    local label = not excluded[i] and l:match("^%[fn:([^%]]+)%]")
    if label then
      if seen[label] then
        return true
      end
      seen[label] = true
    end
  end
  return false
end

---@type difftest.Known[]
return {
  {
    oracle = "export%-latex",
    reason = [[A backslash next to another: "\\ x" is "$\backslash$\ x" in Emacs
      (org-latex-plain-text only escapes a backslash not preceded by one,
      which leaves broken LaTeX), "$\backslash$$\backslash$ x" in org.nvim.
      Emacs bug? Decide whether to follow it.]],
    same = function(s)
      return (s:gsub("%$\\backslash%$%$\\backslash%$", "\0"):gsub("%$\\backslash%$\\", "\0"))
    end,
  },
  {
    oracle = "export%-org",
    reason = [[Org export of plain lists: Emacs writes ordered bullets with
      "." whatever the source used (org-plain-list-ordered-item-terminator
      is t); org.nvim keeps "1)".]],
    ours = "%d%) ",
    same = function(s)
      return each_line(s, function(l)
        return (l:gsub("^(%s*%d+)%)", "%1."))
      end)
    end,
  },
  {
    oracle = "export%-org",
    reason = [[Org export of nested plain lists: sub-lists are indented deeper
      than in Emacs (by a description tag's width), and a parent's checkbox
      isn't recomputed from its children as Emacs does.]],
    either = "\n%s+[%-%+] ",
    same = function(s)
      return each_line(s, function(l)
        if is_item(l) or l:match("^%s+%S") then
          l = vim.trim(l):gsub("%[[ X%-]%]", "[?]")
        end
        return l
      end)
    end,
  },
  {
    oracle = "export%-org",
    reason = [[Org export of an item with a checkbox and nothing else, followed
      by a sub-list: org.nvim puts the first sub-item on the parent's line
      ("- [X] - [-]").]],
    ours = "%[[ X%-]%] [%-%+%d]+[%.%)]? ",
  },
  {
    oracle = "export%-org",
    reason = [[Org export aligns headline tags by byte length instead of
      display width: after a non-ASCII title (日本語) they land too far left.]],
    either = "[\128-\255]",
    same = function(s)
      return each_line(s, function(l)
        if l:match("^%*+ .*%s:[%w_@:]+:$") then
          l = squash(l)
        end
        return l
      end)
    end,
  },
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
    reason = [[A timestamp with a habit repeater (<... .+2d/4d>): org.nvim
      exports it without the "/4d".]],
    emacs = "[%.%+]%d+[hdwmy]/%d+[hdwmy]",
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
    reason = [[A property drawer without its :END: line: Emacs doesn't read
      it as a drawer (no CUSTOM_ID), org.nvim does.]],
    input = function(lines)
      for i, l in ipairs(lines) do
        if l == ":PROPERTIES:" then
          local j = i + 1
          while lines[j] and lines[j]:match("^:[%w_%-]+:") and lines[j] ~= ":END:" do
            j = j + 1
          end
          if lines[j] ~= ":END:" then
            return true
          end
        end
      end
      return false
    end,
  },
  {
    oracle = "export%-.*",
    reason = [[A footnote label defined twice: Emacs and org.nvim export
      different definitions.]],
    input = duplicate_footnotes,
  },
  {
    oracle = "export%-.*",
    reason = [[A description item with an empty tag ("- :: text") is a plain
      item for Emacs, a description item with an empty term for org.nvim.]],
    input = "^%s*[%-%+] ::",
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
    oracle = "export%-latex",
    reason = [[An entity in a caption ("#+CAPTION: A \alpha"): Emacs exports
      it as in the text, "\(\alpha\)"; org.nvim's \captionof keeps
      "\alpha".]],
    emacs = "\\caption",
    same = function(s)
      return (s:gsub("\\%((\\%a+)\\%)", "%1"))
    end,
  },
  {
    oracle = "export%-ascii",
    reason = [[A block holding only a blank line: org.nvim's ASCII export
      prints a "| " line, Emacs a blank one.]],
    ours = "|%s*$",
    input = "^#%+begin_",
  },
  {
    oracle = "agenda",
    reason = [[A headline that is only tags ("* :work:"): Emacs shows the tags
      as the title too, org.nvim an empty title.]],
    emacs = "%s(:[%w_@:]+:)%s+%1",
  },
  {
    oracle = "table",
    reason = [[Formulas over text or out-of-range references: Emacs (Calc)
      keeps symbolic results ("42 + title") or leaves the field; org.nvim
      writes #ERROR.]],
    ours = "#ERROR",
  },
  {
    oracle = "table",
    reason = [[A Calc function over a text field: Emacs keeps the call
      unevaluated ("vsum(task)"), org.nvim gives the text.]],
    emacs = "%l+%(%a",
  },
  {
    oracle = "table",
    reason = [[A Calc vector over a quoted field ($3=$1..$2 with "quoted"):
      Emacs shows the string as character codes ([113, 117, ...]),
      org.nvim as the text.]],
    emacs = "%[%d+, %d+, %d+",
  },
  {
    oracle = "table",
    reason = [[A table with an empty #+TBLFM line: Emacs leaves it alone
      (nothing to compute), org.nvim aligns it.]],
    input = "^#%+TBLFM:%s*$",
    same = function(s)
      return (s:gsub("[ %-]+", ""))
    end,
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
    reason = [[A date range whose start has a time and whose end has none, as
      <2026-10-01 17:30>--<2026-10-03 Sat>, is exported by Emacs with the
      start's time on the end too (org-element-timestamp-interpreter), by
      org.nvim without. The longer line can wrap elsewhere, and a line break
      next to CJK text (日本語) is filled without a space.]],
    emacs = "%a%a%a %d%d:%d%d[%]>&]",
    same = function(s)
      s = squash(s):gsub("(%d%d%d%d%-%d%d%-%d%d %a+) %d%d:%d%d", "%1"):gsub("(%a%a%a) %d%d:%d%d([%]>])", "%1%2")
      return (s:gsub("([\128-\255]) ", "%1"):gsub(" ([\128-\255])", "%1"))
    end,
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
