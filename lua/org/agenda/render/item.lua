---@mod org.agenda.render.item The line of an agenda item
---
--- Tags as displayed, priority and keyword faces, the parts of an item
--- line (org-agenda-format-item) with its habit graph, entry text
--- (org-agenda-get-some-entry-text), blocked entries and adding an item
--- line to a builder. Part of org.agenda.render, which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local habits = require("org.agenda.habits")
local utils = require("org.utils")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

local display_title = shared.display_title

--- Tags as displayed (org-agenda-fix-displayed-tags): inherited tags
--- first, then "::" and the entry's own tags; `hide_tags_regexp` drops
--- matching tags.
function M.tags_string(item)
  local acfg = config.opts.agenda
  local hl = item.headline
  local tags = item.tags or {}
  if not hl then
    return #tags > 0 and (":" .. table.concat(tags, ":") .. ":") or nil
  end
  local own = {}
  for _, t in ipairs(hl.tags) do
    own[t] = true
  end
  local hide = acfg.hide_tags_regexp and acfg.hide_tags_regexp ~= "" and vim.regex(acfg.hide_tags_regexp)
  -- item.tags is in org-get-tags order (inherited, then own), and a tag
  -- that is both counts as own
  local inh, loc = {}, {}
  for _, t in ipairs(tags) do
    if not (hide and hide:match_str(t)) then
      if not own[t] then
        if acfg.show_inherited_tags ~= false then
          inh[#inh + 1] = t
        end
      else
        loc[#loc + 1] = t
      end
    end
  end
  if #inh == 0 and #loc == 0 then
    return nil
  end
  if #inh == 0 then
    return ":" .. table.concat(loc, ":") .. ":"
  end
  if #loc == 0 then
    return ":" .. table.concat(inh, ":") .. "::"
  end
  return ":" .. table.concat(inh, ":") .. "::" .. table.concat(loc, ":") .. ":"
end

--- Split parts at display column `col`: (before, after).
local function split_parts(parts, col)
  local before, after = {}, {}
  local w = 0
  for _, p in ipairs(parts) do
    local s = p[1] or ""
    local sw = utils.width(s)
    if w >= col then
      after[#after + 1] = p
    elseif w + sw <= col then
      before[#before + 1] = p
    else
      local n = col - w
      local head = vim.fn.strcharpart(s, 0, n)
      while utils.width(head) > n do
        head = vim.fn.strcharpart(head, 0, vim.fn.strchars(head) - 1)
      end
      local tail = s:sub(#head + 1)
      before[#before + 1] = { head, p[2] }
      if utils.width(head) < n then
        before[#before + 1] = { string.rep(" ", n - utils.width(head)) }
      end
      after[#after + 1] = { tail, p[2] }
    end
    w = w + sw
  end
  if w < col then
    before[#before + 1] = { string.rep(" ", col - w) }
  end
  return before, after
end

--- Drop the first `n` display columns of parts.
local function drop_columns(parts, n)
  local _, after = split_parts(parts, n)
  return after
end

--- The highlight of an item's priority cookie (org-agenda-fontify-priorities):
--- nil when `agenda.fontify_priorities` is false, else the group of
--- `ui.priority_faces`, of a `fontify_priorities` table, italic for the
--- lowest priority, bold for the highest, or OrgAgendaPriority.
---@return string?
function M.priority_group(item)
  local fp = config.opts.agenda.fontify_priorities
  if fp == nil then
    fp = "cookies"
  end
  if not fp then
    return nil
  end
  local p = tostring(item.priority)
  local hls = require("org.highlights")
  local ui = config.opts.ui or {}
  if (ui.priority_faces or {})[p] then
    return hls.face_group("orgPriorityFace_", p)
  end
  if type(fp) == "table" and fp[p] ~= nil then
    local group = hls.face_group("OrgAgendaPriorityFace_", p)
    pcall(vim.api.nvim_set_hl, 0, group, hls.hl_from_face(fp[p]))
    return group
  end
  local file = item.headline and item.headline.file
  local pr = file and file.priorities and file:priorities() or nil
  local highest = pr and pr.highest or config.opts.priority_highest
  local lowest = pr and pr.lowest or config.opts.priority_lowest
  if p == tostring(lowest) then
    return "OrgAgendaPriorityLowest"
  elseif p == tostring(highest) then
    return "OrgAgendaPriorityHighest"
  end
  return "OrgAgendaPriority"
end

-- the `ui` table whose keyword and tag faces were last defined
local faces_for

--- Define the groups of `ui.todo_keyword_faces` / `ui.tag_faces` (the
--- agenda can be opened before any Org buffer did), again after setup().
local function ensure_faces()
  local ui = config.opts.ui
  if faces_for ~= ui then
    faces_for = ui
    local hls = require("org.highlights")
    hls.ensure()
    hls.apply_todo_faces()
  end
end

--- Highlight group of an item's TODO keyword (org-get-todo-face): its
--- `ui.todo_keyword_faces` face, else OrgAgendaDoneKeyword or
--- OrgAgendaTodoKeyword.
---@return string
function M.todo_group(item)
  local faces = (config.opts.ui or {}).todo_keyword_faces or {}
  if item.todo and faces[item.todo] then
    ensure_faces()
    return "orgTodoKw_" .. item.todo:gsub("[^%w_]", "_")
  end
  return item.done and "OrgAgendaDoneKeyword" or "OrgAgendaTodoKeyword"
end

--- Push the tag string `:a:b:` of a line: OrgAgendaTag, with the
--- `ui.tag_faces` face on the tags that have one (org-agenda-align-tags
--- adds org-tag-faces).
local function push_tags(push, tagstr)
  local faces = (config.opts.ui or {}).tag_faces or {}
  if next(faces) == nil then
    push(tagstr, "OrgAgendaTag")
    return
  end
  local hls = require("org.highlights")
  ensure_faces()
  local init = 1
  for s, tag, e in tagstr:gmatch("()([^:]+)()") do
    if faces[tag] then
      if s > init then
        push(tagstr:sub(init, s - 1), "OrgAgendaTag")
      end
      push(tag, hls.face_group("orgTagFace_", tag))
      init = e
    end
  end
  if init <= #tagstr then
    push(tagstr:sub(init), "OrgAgendaTag")
  end
end

--- Build the parts for an item line.
---@param item org.AgendaItem
---@param ctx { agenda?: boolean, kind?: string, width: integer, today: integer }
function M.item_parts(item, ctx)
  local acfg = config.opts.agenda
  local kind = ctx.kind or (ctx.agenda and "agenda" or "todo")
  local parts = {}
  local width = 0
  local function push(s, group)
    parts[#parts + 1] = { s, group }
    width = width + utils.width(s)
  end
  local prefix = M.prefix(item, kind)
  local cat = item.category or ""
  local ps, pe = prefix:find(cat .. ":", 1, true)
  if cat ~= "" and ps then
    push(prefix:sub(1, ps - 1))
    push(prefix:sub(ps, pe), "OrgAgendaCategory")
    local rest = prefix:sub(pe + 1)
    -- the leader gets the item face (Emacs faces the whole line)
    local ex = item.extra
    local es, ee = nil, nil
    if ex and ex ~= "" and not item.habit then
      es, ee = rest:find(ex, 1, true)
    end
    if es then
      push(rest:sub(1, es - 1))
      push(rest:sub(es, ee), item.face ~= "OrgAgendaTimestamp" and item.face or nil)
      push(rest:sub(ee + 1))
    else
      push(rest)
    end
  else
    push(prefix)
  end
  -- a headline with no title ("** TODO") is only its keyword (and
  -- priority), with no space after it (Emacs trims the headline text)
  local untitled = (item.title or "") == ""
  if item.todo then
    -- org-agenda-todo-keyword-format ("" drops the keyword and its space)
    local fmt = acfg.todo_keyword_format or "%-1s"
    if fmt ~= "" then
      local ok, kw = pcall(string.format, fmt, item.todo)
      push(ok and kw or item.todo, M.todo_group(item))
      if item.priority or not untitled then
        push(" ")
      end
    end
  end
  if item.priority then
    local group = M.priority_group(item)
    parts.priority_index = #parts + 1
    push("[#" .. item.priority .. "]", group or item.face)
    if not untitled then
      push(" ")
    end
  end
  push(display_title(item.display_title or item.title or ""), item.face)

  local rt = acfg.remove_tags
  local has_tag = M.compile_prefix(M.prefix_format(kind)).has.tag
  if not (rt == true or (rt == "prefix" and has_tag)) then
    local tagstr = M.tags_string(item)
    if tagstr then
      local col = acfg.tags_column
      local pad
      if type(col) == "number" and col >= 0 then
        -- 0: one space after the text (org-agenda-align-tags)
        pad = col - width
      elseif type(col) == "number" and col < 0 then
        pad = -col - width - utils.width(tagstr)
      else
        pad = (ctx.width - 1) - width - utils.width(tagstr)
      end
      push(string.rep(" ", math.max(pad, 1)))
      push_tags(push, tagstr)
    end
  end

  if item.habit then
    -- org-habit-insert-consistency-graphs: the graph overwrites the line
    -- from `graph_column`
    local hcfg = acfg.habits or {}
    local gc = hcfg.graph_column or 40
    local glen = (hcfg.preceding_days or 21) + (hcfg.following_days or 7) + 1
    local before, after = split_parts(parts, gc)
    after = drop_columns(after, glen)
    parts = before
    for _, g in ipairs(habits.graph(item.habit, ctx.today)) do
      parts[#parts + 1] = { g[1], g[2] }
    end
    vim.list_extend(parts, after)
  end
  return parts
end

--- `l` with each tab expanded to the next multiple of 8 columns
--- (untabify, as org-agenda-get-some-entry-text does).
function M.untabify(l)
  if not l:find("\t", 1, true) then
    return l
  end
  local out, col = {}, 0
  local segs = vim.split(l, "\t", { plain = true })
  for i, seg in ipairs(segs) do
    out[#out + 1] = seg
    col = col + utils.width(seg)
    if i < #segs then
      local n = 8 - col % 8
      out[#out + 1] = string.rep(" ", n)
      col = col + n
    end
  end
  return table.concat(out)
end

local PLANNING_LINE = vim.regex("\\c^[ \t]*\\<\\(SCHEDULED:\\|DEADLINE:\\|CLOSED:\\|CLOCK:\\) *[[<][^]>]\\+[]>]")

--- Body text of an entry (org-agenda-get-some-entry-text): the text up to
--- the next headline without drawers and planning / CLOCK lines, the
--- matches of `agenda.entry_text_exclude_regexps` (Emacs regexps)
--- removed, trailing blank text dropped, the common indentation stripped,
--- at most `max` lines.
---@param hl org.Headline
---@param max integer maximum number of lines
---@return string[]
function M.entry_text(hl, max)
  local lines = hl.file.lines
  local stop = hl.children[1] and (hl.children[1].line - 1) or hl.end_line
  local kept = {}
  local i = hl.line + 1
  while i <= stop do
    local l = lines[i] or ""
    if l:match("^[ \t]*:[%w_%-]+:[ \t]*$") then
      -- a drawer, up to its :END: line (or the end of the text)
      local j = i + 1
      while j <= stop and not (lines[j] or ""):match("^[ \t]*:END:") do
        j = j + 1
      end
      i = j + 1
    else
      if not PLANNING_LINE:match_str(l) then
        kept[#kept + 1] = l
      end
      i = i + 1
    end
  end
  local text = table.concat(kept, "\n")
  local search = require("org.agenda.search")
  for _, re in ipairs(config.opts.agenda.entry_text_exclude_regexps or {}) do
    local ok, pat = pcall(search.emacs_regexp, re, true)
    if ok then
      local ok2, res = pcall(vim.fn.substitute, text, "\\c" .. pat, "", "g")
      if ok2 then
        text = res
      end
    end
  end
  text = text:gsub("[ \t\n]+$", "")
  local out = vim.split(text, "\n", { plain = true })
  local indent
  for n, l in ipairs(out) do
    l = M.untabify(l)
    out[n] = l
    if not l:match("^[ \t]*$") then
      local w = #l:match("^( *)")
      indent = indent and math.min(indent, w) or w
    end
  end
  local res = {}
  for _, l in ipairs(out) do
    if #res == 0 and l:match("^[ \t]*$") then
      -- leading blank lines are dropped
    else
      res[#res + 1] = l:match("^[ \t]*$") and l or l:sub((indent or 0) + 1)
    end
  end
  return vim.list_slice(res, 1, max)
end

--- Is the item a TODO blocked by its children, an ORDERED sibling or
--- unchecked checkboxes (only with the enforce_todo_* options)?
function M.is_blocked(it)
  if not it.headline or not it.todo or it.done then
    return false
  end
  local ok, todo = pcall(require, "org.todo")
  if not ok or type(todo.blocked_reason) ~= "function" then
    return false
  end
  local ok2, reason = pcall(todo.blocked_reason, it.headline)
  return ok2 and reason ~= nil
end

--- The line of an item (org-agenda-format-item and the faces of
--- org-agenda-finalize): its text, highlights { start_col, end_col, group,
--- priority? } and line highlight; nil when it is not shown (a blocked
--- entry with `dim_blocked = "invisible"`).
---@return string|nil text, table[] hls, string|nil line_hl
function M.item_line(it, ctx)
  local parts = M.item_parts(it, ctx)
  local blocked = false
  if ctx.dim_blocked and M.is_blocked(it) then
    if ctx.dim_blocked == "invisible" then
      return nil, {}, nil
    end
    -- org-agenda-dim-blocked-tasks: the dimmed face over the whole line,
    -- above the other faces (its overlay has priority 50)
    blocked = true
    for _, p in ipairs(parts) do
      p[2] = "OrgAgendaDimmed"
    end
  end
  local text, hls = M.line_text(parts)
  local fp = config.opts.agenda.fontify_priorities
  if not blocked and parts.priority_index and (fp == true or type(fp) == "table") then
    -- the priority face from the cookie to the end of the line
    local col = 0
    for i = 1, parts.priority_index - 1 do
      col = col + #(parts[i][1] or "")
    end
    local group = M.priority_group(it)
    if group then
      hls[#hls + 1] = { col, #text, group, 115 }
    end
  end
  return text, hls, ctx.is_clocking and ctx.is_clocking(it) and "OrgAgendaClocking" or nil
end

--- Add an item line (plus its entry text in entry-text mode). The context
--- of the line is kept in `b.line_ctx`, to format it again after a change
--- of its entry (org-agenda-change-all-lines).
function M.add_item(b, it, ctx)
  local text, hls, line_hl = M.item_line(it, ctx)
  if not text then
    return
  end
  local row = b:add_line(text, hls, it, line_hl)
  b.line_ctx = b.line_ctx or {}
  b.line_ctx[row] = ctx
  if ctx.entry_text and it.headline then
    local acfg = config.opts.agenda
    -- a number: the count given to `E` (org-agenda-entry-text-mode N)
    local max = type(ctx.entry_text) == "number" and ctx.entry_text or acfg.entry_text_maxlines or 5
    local leader = acfg.entry_text_leaders or "    > "
    for _, l in ipairs(M.entry_text(it.headline, max)) do
      b:text(leader .. l, "OrgAgendaEntryText")
      b.entry_text_lines = b.entry_text_lines or {}
      b.entry_text_lines[#b.lines] = true
    end
  end
end

return M
