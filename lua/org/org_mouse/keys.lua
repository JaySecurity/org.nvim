---@mod org.org_mouse.keys org-mouse mouse keys
---
--- Mouse positions, the Visual selection, the right-button press and
--- release (context menu, drags), C-mouse-1 drags, S-mouse-2 and the
--- buffer-local keys of an org buffer.
--- Part of org.org_mouse, which loads it.

local utils = require("org.utils")
local shared = require("org.org_mouse.shared")

local get_line = shared.get_line

local M = require("org.org_mouse")

--- The mouse position as { lnum, col } in the current window (col is
--- 1-based and #line + 1 past the end of the line), or nil.
function M.mouse_pos()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return nil
  end
  if pos.winid ~= vim.api.nvim_get_current_win() then
    pcall(vim.api.nvim_set_current_win, pos.winid)
  end
  return { pos.line, pos.column, screen = { pos.screenrow, pos.screencol }, win = pos.winid }
end

--- The mouse position at the release of a drag that started at `p` (from
--- `mouse_pos`), without changing windows: nil outside any window, and
--- `other` set when the drag ended in another window (whose line numbers
--- must not be used on the buffer of the press).
---@param p table
---@return table|nil
function M.release_pos(p)
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or pos.line == 0 then
    return nil
  end
  local other = p.win ~= nil and pos.winid ~= p.win
  return { pos.line, pos.column, screen = { pos.screenrow, pos.screencol }, win = pos.winid, other = other }
end

--- The Visual selection as the region of a context menu.
function M.visual_region()
  local m = vim.fn.mode()
  if not (m == "v" or m == "V" or m == "\22") then
    return nil
  end
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then
    s, e = e, s
  end
  local lines = vim.fn.getregion(s, e, { type = m })
  utils.exit_visual()
  return { text = table.concat(lines, "\n"), s = { s[2], s[3] }, e = { e[2], e[3] } }
end

M._press = nil

--- <RightMouse>: remember the press; without a feature using right drags,
--- show the context menu now.
function M.right_press()
  local visual = M.visual_region()
  local p = M.mouse_pos()
  if not p then
    return
  end
  M._press = { p = p, visual = visual }
  if not (M.feature("yank-link") or M.feature("move-tree")) then
    M.right_release(true)
  end
end

--- <RightRelease>: a click shows the context menu, a drag moves a subtree
--- (move-tree) or inserts the last yank as a link there (yank-link).
function M.right_release(now)
  local press = M._press
  M._press = nil
  if not press then
    return
  end
  local p = press.p
  local r = not now and M.release_pos(p) or p
  if r.other then
    -- a drag into another window: nothing to do in this buffer
    return
  end
  local dragged = r[1] ~= p[1] or r[2] ~= p[2]
  if dragged and M.feature("move-tree") then
    M.move_tree({ p[1], p[2] }, { r[1], r[2] })
    return
  elseif dragged and M.feature("yank-link") then
    M.yank_link(r[1], math.min(r[2], #get_line(0, r[1]) + 1))
    return
  end
  if not M.feature("context-menu") then
    return
  end
  if vim.bo.filetype == "orgagenda" then
    M.agenda_context_menu(p[1], p[2])
    return
  end
  local line = get_line(0, p[1])
  if not press.visual then
    pcall(vim.api.nvim_win_set_cursor, 0, { p[1], math.max(math.min(p[2], #line) - 1, 0) })
  end
  M.show_context_menu({ lnum = p[1], col = p[2], line = line, visual = press.visual })
end

--- <C-LeftMouse> / <C-LeftRelease>: drag a subtree.
function M.ctrl_press()
  M._ctrl_press = M.mouse_pos()
  M.move_tree_start()
end

function M.ctrl_release()
  local p = M._ctrl_press
  M._ctrl_press = nil
  local r = p and M.release_pos(p)
  if p and r and not r.other and (p[1] ~= r[1] or p[2] ~= r[2]) then
    M.move_tree({ p[1], p[2] }, { r[1], r[2] })
  end
end

--- <S-MiddleMouse>: insert the last yank as a link where clicked.
function M.shift_middle()
  local p = M.mouse_pos()
  if p then
    M.yank_link(p[1], math.min(p[2], #get_line(0, p[1]) + 1))
  end
end

--- Is the mouse inside the Visual selection (org-mouse-in-region-p)?
function M.click_in_selection()
  local pos = vim.fn.getmousepos()
  if pos.winid ~= vim.api.nvim_get_current_win() or pos.line == 0 then
    return false
  end
  local m = vim.fn.mode()
  local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then
    s, e = e, s
  end
  local l, c = pos.line, pos.column
  if m == "V" then
    return l >= s[2] and l <= e[2]
  elseif m == "\22" then
    local c1, c2 = math.min(s[3], e[3]), math.max(s[3], e[3])
    return l >= s[2] and l <= e[2] and c >= c1 and c <= c2
  end
  -- characterwise, its last character included
  if l < s[2] or l > e[2] then
    return false
  end
  return not ((l == s[2] and c < s[3]) or (l == e[2] and c > e[3]))
end

--- Buffer-local mouse keys of org-mouse in an org buffer.
function M.attach(bufnr)
  if not M.enabled() then
    return
  end
  local function map(modes, lhs, fn, desc)
    vim.keymap.set(modes, lhs, fn, { buffer = bufnr, desc = "org-mouse: " .. desc })
  end
  -- org-mouse-down-mouse: a click inside the selection keeps it
  vim.keymap.set("x", "<LeftMouse>", function()
    return M.click_in_selection() and "" or "<LeftMouse>"
  end, { buffer = bufnr, expr = true, desc = "org-mouse: keep the selection on a click in it" })
  if M.feature("context-menu") or M.feature("move-tree") or M.feature("yank-link") then
    map({ "n", "x" }, "<RightMouse>", M.right_press, "context menu")
    map({ "n", "x" }, "<RightDrag>", "<Nop>", "drag")
    map({ "n", "x" }, "<RightRelease>", function()
      M.right_release()
    end, "context menu / drag")
  end
  if M.feature("context-menu") then
    map("n", "<C-LeftMouse>", M.ctrl_press, "move tree start")
    map("n", "<C-LeftDrag>", "<Nop>", "move tree")
    map("n", "<C-LeftRelease>", M.ctrl_release, "move tree")
  end
  if M.feature("yank-link") then
    map("n", "<S-MiddleMouse>", M.shift_middle, "yank link")
  end
end
