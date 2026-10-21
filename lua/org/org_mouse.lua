---@mod org.org_mouse Better mouse support (org-mouse)
---
--- A port of org-mouse.el, off by default like the Emacs module (which is
--- loaded with (require 'org-mouse)); turn it on with
--- `mouse.org_mouse = true`. `mouse.features` (org-mouse-features) picks
--- the parts:
---   "context-menu"   <RightMouse> shows a menu for what is under the
---                    mouse: headline, TODO keyword, priority, tags,
---                    timestamp, checkbox, link, table, #+STARTUP line,
---                    the Visual selection, else a general menu; and
---                    <C-LeftMouse> dragged moves a subtree
---   "move-tree"      a drag with <RightMouse> moves a subtree
---   "yank-link"      <S-MiddleMouse>, or a drag with <RightMouse>, inserts
---                    the last yank as a link where the mouse is
---   "activate-stars", "activate-bullets", "activate-checkboxes"
---                    clicking headline stars cycles the subtree, a
---                    bullet cycles the item, a checkbox toggles it
--- Moving a subtree: drop it on the same headline to promote (drag left)
--- or demote (drag right) it, on another headline's stars to put it before
--- that one, on its text to make it that one's last child.

local config = require("org.config")

local M = {}
-- The parts in org/org_mouse/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.org_mouse"] = M

---@return boolean
function M.enabled()
  local m = config.opts.mouse or {}
  return m.org_mouse == true
end

--- Is feature `name` of `mouse.features` on (and org_mouse)?
---@param name string
---@return boolean
function M.feature(name)
  if not M.enabled() then
    return false
  end
  return vim.tbl_contains((config.opts.mouse or {}).features or {}, name)
end

local function get_line(bufnr, lnum)
  return vim.api.nvim_buf_get_lines(bufnr or 0, lnum - 1, lnum, false)[1] or ""
end

local function set_line(bufnr, lnum, text)
  vim.api.nvim_buf_set_lines(bufnr or 0, lnum - 1, lnum, false, { text })
end

--- just-one-space at byte `pos` (1-based: the gap before character `pos`)
--- of `s`: the spaces and tabs around it become one space. Returns the new
--- string and the position after that space.
---@param s string
---@param pos integer
---@return string, integer
function M.just_one_space(s, pos)
  local a, b = pos, pos
  while a > 1 and s:sub(a - 1, a - 1):match("[ \t]") do
    a = a - 1
  end
  while b <= #s and s:sub(b, b):match("[ \t]") do
    b = b + 1
  end
  return s:sub(1, a - 1) .. " " .. s:sub(b), a + 1
end

--- Replace bytes [s, e] of line `lnum` by `text`; unless `nosurround`,
--- make one space on both sides (org-mouse-replace-match-and-surround).
function M.replace(lnum, s, e, text, nosurround)
  local line = get_line(0, lnum)
  local new = line:sub(1, s - 1) .. text .. line:sub(e + 1)
  if not nosurround then
    -- the end first: the start stays where it is
    new = M.just_one_space(new, s + #text)
    new = M.just_one_space(new, s)
  end
  set_line(0, lnum, new)
end

--- org-mouse-remove-match-and-spaces: delete bytes [s, e] and make one
--- space there.
function M.remove_match_and_spaces(lnum, s, e)
  local line = get_line(0, lnum)
  local new = M.just_one_space(line:sub(1, s - 1) .. line:sub(e + 1), s)
  set_line(0, lnum, new)
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max(s - 1, 0) })
end

--- The checkbox of the item on `line`: its byte range, or nil.
local function checkbox_range(line)
  local pre = line:match("^([ \t]*[-+*][ \t]+)%[[ Xx-]%]")
    or line:match("^([ \t]*%d+[.)][ \t]+)%[[ Xx-]%]")
    or line:match("^([ \t]*[-+*][ \t]+%[@[%w:]+%][ \t]*)%[[ Xx-]%]")
    or line:match("^([ \t]*%d+[.)][ \t]+%[@[%w:]+%][ \t]*)%[[ Xx-]%]")
  if not pre then
    return nil
  end
  return #pre + 1, #pre + 3
end
M.checkbox_range = checkbox_range

--- The bullet of the item on `line` (org-list-full-item-re group 1,
--- with the spaces after it).
local function bullet_end(line)
  local pre = line:match("^[ \t]*[-+*][ \t]+") or line:match("^[ \t]*%d+[.)][ \t]+")
  if line:match("^[ \t]*[-+*][ \t]*$") then
    pre = line
  end
  return pre and #pre or nil
end

--- The lines of the items of the list at the cursor: the item there and
--- its siblings (org-apply-on-list).
local function list_item_lines()
  local lists = require("org.lists")
  local item = lists.item_at(0, vim.api.nvim_win_get_cursor(0)[1])
  local out = {}
  for _, it in ipairs(item and lists.siblings(item) or {}) do
    out[#out + 1] = it.lnum
  end
  table.sort(out)
  return out
end

--- org-mouse-for-each-item
local function for_each_item(fn)
  for _, l in ipairs(list_item_lines()) do
    fn(l)
  end
end
M.for_each_item = for_each_item

-- Local functions the parts below share
local shared = require("org.org_mouse.shared")
shared.bullet_end = bullet_end
shared.checkbox_range = checkbox_range
shared.for_each_item = for_each_item
shared.get_line = get_line
shared.set_line = set_line

require("org.org_mouse.commands")
require("org.org_mouse.menus")
require("org.org_mouse.context")
require("org.org_mouse.agenda")
require("org.org_mouse.keys")

return M
