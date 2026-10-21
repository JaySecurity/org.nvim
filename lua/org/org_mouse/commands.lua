---@mod org.org_mouse.commands org-mouse commands
---
--- The commands of org-mouse's menus and gestures: headings, checkboxes,
--- plain lists to outlines, timestamps, yanking links, moving subtrees,
--- and org-open-at-point on stars, bullets and checkboxes.
--- Part of org.org_mouse, which loads it.

local utils = require("org.utils")
local shared = require("org.org_mouse.shared")

local get_line, set_line = shared.get_line, shared.set_line
local checkbox_range, bullet_end = shared.checkbox_range, shared.bullet_end

local M = require("org.org_mouse")

--- org-mouse-end-headline: to the end of the headline, before its tags.
function M.end_headline()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local line = get_line(0, lnum)
  local s = line:gsub("[ \t]+$", "")
  if s:match(":[A-Za-z]+:$") then
    -- (skip-chars-backward ":A-Za-z") then the spaces
    s = s:gsub("[:A-Za-z]+$", ""):gsub("[ \t]+$", "")
  end
  vim.api.nvim_win_set_cursor(0, { lnum, #s })
  return #s
end

--- Where the mouse is on the line: "beginning" when only spaces and stars
--- are before it, "end" at the end of the line, else "middle"
--- (org-mouse-line-position).
local function line_position(line, col)
  if col > #line then
    return "end"
  elseif line:sub(1, col - 1):match("^[ \t*]*$") then
    return "beginning"
  end
  return "middle"
end

--- org-mouse-insert-heading: a new heading before the line when the mouse
--- is at its beginning, else before the next heading (after the subtree).
---@param col? integer 1-based column (default: the cursor's)
function M.insert_heading(col)
  local lnum, ccol = utils.cursor()
  col = col or ccol
  local line = get_line(0, lnum)
  local parser = require("org.parser")
  if line_position(line, col) == "beginning" then
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  else
    -- org-mouse-next-heading
    local n = vim.api.nvim_buf_line_count(0)
    local target
    for l = lnum + 1, n do
      if parser.headline_level(get_line(0, l)) then
        target = l
        break
      end
    end
    if target then
      vim.api.nvim_win_set_cursor(0, { target, 0 })
    elseif get_line(0, n):match("^[ \t]*$") then
      vim.api.nvim_win_set_cursor(0, { n, 0 })
    else
      vim.api.nvim_buf_set_lines(0, n, n, false, { "" })
      vim.api.nvim_win_set_cursor(0, { n + 1, 0 })
    end
  end
  require("org.structure").meta_return_heading({})
  utils.start_insert()
  return true
end

--- org-mouse-insert-heading at `pos` ({ lnum, col } with a 1-based col).
function M.insert_heading_at(pos)
  local line = get_line(0, pos[1])
  vim.api.nvim_win_set_cursor(0, { pos[1], math.max(math.min(pos[2], #line) - 1, 0) })
  return M.insert_heading(pos[2])
end

--- org-mouse-insert-checkbox: a checkbox on the item at the cursor.
function M.insert_checkbox(lnum)
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  local line = get_line(0, lnum)
  local e = bullet_end(line)
  if not e or checkbox_range(line) or require("org.parser").headline_level(line) then
    return false
  end
  -- (goto-char (match-end 0)) (delete-horizontal-space) (insert " [ ] ")
  local head = line:sub(1, e):gsub("[ \t]+$", "")
  set_line(0, lnum, head .. " [ ] " .. line:sub(e + 1):gsub("^[ \t]+", ""))
  return true
end

--- org-mouse-transform-to-outline: the list items of the entry with the
--- smallest indentation become headlines one level below it.
function M.transform_to_outline()
  local parser = require("org.parser")
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local head = lnum
  while head >= 1 and not parser.headline_level(get_line(0, head)) do
    head = head - 1
  end
  if head < 1 then
    utils.error("Before first headline")
    return false
  end
  local level = parser.headline_level(get_line(0, head)) --[[@as integer]]
  local stars = string.rep("*", level) .. "* "
  local n = vim.api.nvim_buf_line_count(0)
  local re = "^([ \t]*)([-+*]) "
  local re2 = "^([ \t]*)(%d+[.)]) "
  local minlevel = 1000
  local l = head + 1
  while l <= n and not parser.headline_level(get_line(0, l)) do
    local ind = get_line(0, l):match(re) or get_line(0, l):match(re2)
    if ind then
      minlevel = math.min(minlevel, #ind)
    end
    l = l + 1
  end
  l = head + 1
  while l <= n and not parser.headline_level(get_line(0, l)) do
    local line = get_line(0, l)
    local ind, bullet = line:match(re)
    if not ind then
      ind, bullet = line:match(re2)
    end
    if ind and #ind == minlevel then
      set_line(0, l, stars .. line:sub(#ind + #bullet + 2))
    end
    l = l + 1
  end
  return true
end

--- org-mouse-timestamp-today: change the timestamp at the cursor with the
--- date prompt, then shift it by `shift` `unit`s (org-timestamp-change).
function M.timestamp_today(shift, unit)
  require("org.timestamps").insert_active({ edit = true })
  if shift then
    M.timestamp_change(shift, unit)
  end
end

--- (org-timestamp-change n 'day|'month) on the timestamp at the cursor.
function M.timestamp_change(n, unit)
  local ts = require("org.timestamps")
  local item = ts.at_cursor()
  if not item then
    return false
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  -- on the day (or month) field of the first date
  local raw = item.raw
  local ds = raw:find("%d%d%d%d%-%d%d%-%d%d")
  if not ds then
    return false
  end
  local col = item.start_col - 1 + ds - 1 + (unit == "month" and 5 or 8)
  vim.api.nvim_win_set_cursor(0, { cur[1], col })
  ts.increment(n, unit == "month" and "m" or "d")
  pcall(vim.api.nvim_win_set_cursor, 0, cur)
  return true
end

--- org-mouse-delete-timestamp: the timestamp at the cursor and the
--- keyword before it (SCHEDULED:, DEADLINE: ...).
function M.delete_timestamp()
  local item = require("org.timestamps").at_cursor()
  if not item then
    return false
  end
  local lnum = item.lnum
  local line = get_line(0, lnum)
  local s = item.start_col
  local head = line:sub(1, s - 1)
  local tail = line:sub(item.end_col + 1)
  -- (skip-chars-backward " :A-Z") then a keyword there is removed
  local k = #head
  while k > 0 and head:sub(k, k):match("[ :A-Z]") do
    k = k - 1
  end
  local rest = head:sub(k + 1)
  local kw = rest:match("^ *[A-Z][A-Z]+:")
  if kw then
    head = head:sub(1, k) .. rest:sub(#kw + 1)
  end
  set_line(0, lnum, head .. tail)
  return true
end

--- org-mouse-yank-link: " [[<last yank>]] " where the mouse is, with the
--- spaces there removed.
---@param lnum integer
---@param col integer 1-based byte column
function M.yank_link(lnum, col)
  local line = get_line(0, lnum)
  local a, b = col, col
  while a > 1 and line:sub(a - 1, a - 1):match("[ \t]") do
    a = a - 1
  end
  while b <= #line and line:sub(b, b):match("[ \t]") do
    b = b + 1
  end
  local kill = vim.fn.getreg('"'):gsub("\n$", "")
  local ins = " [[" .. kill .. "]] "
  set_line(0, lnum, line:sub(1, a - 1) .. ins .. line:sub(b))
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, a - 1 + #ins })
  return true
end

--- org-mouse-show-overview: first-level headlines only.
function M.show_overview()
  require("org.fold").overview()
end

--- org-mouse-show-headlines: all headlines (org-cycle twice from overview:
--- CONTENTS).
function M.show_headlines()
  require("org.fold").content()
end

--- org-mouse-move-tree: move the subtree of the headline at `from` to
--- `to` ({ lnum, col } with a 1-based byte col). On the same headline a
--- drag to the right demotes it, to the left promotes it; on another
--- headline's stars (and spaces) it goes before that one, at its level;
--- further right it becomes that headline's last child.
function M.move_tree(from, to)
  local parser = require("org.parser")
  local function heading_of(lnum)
    for l = lnum, 1, -1 do
      if parser.headline_level(get_line(0, l)) then
        return l
      end
    end
    return nil
  end
  local sh, eh = heading_of(from[1]), heading_of(to[1])
  if not (sh and eh) then
    utils.error("Before first headline")
    return false
  end
  if sh == eh then
    vim.api.nvim_win_set_cursor(0, { sh, 0 })
    local later = to[1] > from[1] or (to[1] == from[1] and to[2] >= from[2])
    if later then
      require("org.context").demote_subtree()
    else
      require("org.context").promote_subtree()
    end
    return true
  end
  local src = require("org.files").get_buffer(0):headline_on(sh)
  if eh > sh and eh <= src.end_line then
    utils.warn("Cannot move a subtree into itself")
    return false
  end
  -- a drop right of the stars (or on the text below) makes a child
  local tline = get_line(0, eh)
  local child = to[1] ~= eh or to[2] > #(tline:match("^%*+ ") or tline)
  -- the target headline as a mark that follows the text when the subtree
  -- is cut
  local ns = vim.api.nvim_create_namespace("org.org_mouse.move")
  local mark = vim.api.nvim_buf_set_extmark(0, ns, eh - 1, 0, {})
  local lines = vim.api.nvim_buf_get_lines(0, src.line - 1, src.end_line, false)
  local level = parser.headline_level(lines[1])
  vim.api.nvim_buf_set_lines(0, src.line - 1, src.end_line, false, {})
  local target = vim.api.nvim_buf_get_extmark_by_id(0, ns, mark, {})[1] + 1
  vim.api.nvim_buf_del_extmark(0, ns, mark)
  local tlevel = parser.headline_level(get_line(0, target))
  local insert_at, new_level = target, tlevel
  if child then
    local th = require("org.files").get_buffer(0):headline_on(target)
    insert_at, new_level = th.end_line + 1, tlevel + require("org.structure").level_increment(0)
  end
  local delta = new_level - level
  local out = {}
  for _, l in ipairs(lines) do
    local lv = parser.headline_level(l)
    if lv then
      l = string.rep("*", math.max(lv + delta, 1)) .. l:sub(lv + 1)
    end
    out[#out + 1] = l
  end
  vim.api.nvim_buf_set_lines(0, insert_at - 1, insert_at - 1, false, out)
  vim.api.nvim_win_set_cursor(0, { insert_at, 0 })
  return true
end

--- The message of C-down-mouse-1 (org-mouse-move-tree-start).
M.MOVE_TREE_HELP = "Same line: promote/demote, (***):move before, (text): make a child"

function M.move_tree_start()
  utils.notify(M.MOVE_TREE_HELP)
end

---------------------------------------------------------------------------
-- org-open-at-point with org-mouse (org--mouse-open-at-point)
---------------------------------------------------------------------------

--- What is under the cursor for org-mouse's org-open-at-point: "stars",
--- "checkbox", "bullet" or nil.
---@param line string
---@param col integer 1-based
function M.small_context(line, col)
  local level = require("org.parser").headline_level(line)
  if level then
    if col <= level then
      return "stars"
    end
    return nil
  end
  local cs, ce = checkbox_range(line)
  if cs and col >= cs and col <= ce then
    return "checkbox"
  end
  local b = line:match("^([ \t]*)[-+*][ \t]") or line:match("^([ \t]*)%d+[.)][ \t]")
  if b then
    local bullet = line:match("^[ \t]*([-+*])") or line:match("^[ \t]*(%d+[.)])")
    if col > #b and col <= #b + #bullet then
      return "bullet"
    end
  end
  return nil
end

--- With org-mouse, org-open-at-point on headline stars cycles the subtree,
--- on a checkbox toggles it and on a bullet cycles the item. `mouse`: only
--- where the matching activate-* feature makes the text clickable.
---@param mouse? boolean
---@return boolean handled
function M.open_at_point(mouse)
  if not M.enabled() then
    return false
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local what = M.small_context(line, col)
  if not what then
    return false
  end
  if mouse then
    local feature = ({ stars = "activate-stars", checkbox = "activate-checkboxes", bullet = "activate-bullets" })[what]
    if not M.feature(feature) then
      return false
    end
  end
  if what == "checkbox" then
    require("org.lists").toggle_checkbox()
  else
    require("org.fold").cycle()
  end
  return true
end

--- delete-blank-lines on line `lnum`: on a blank line among blank lines,
--- all but one go; on a lone blank line, it goes.
function M.delete_blank_lines(lnum)
  local n = vim.api.nvim_buf_line_count(0)
  local s, e = lnum, lnum
  while s > 1 and get_line(0, s - 1):match("^[ \t]*$") do
    s = s - 1
  end
  while e < n and get_line(0, e + 1):match("^[ \t]*$") do
    e = e + 1
  end
  if s == e then
    vim.api.nvim_buf_set_lines(0, s - 1, e, false, {})
  else
    vim.api.nvim_buf_set_lines(0, s - 1, e, false, { "" })
  end
end
