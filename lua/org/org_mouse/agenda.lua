---@mod org.org_mouse.agenda org-mouse in the agenda
---
--- The agenda menu, the context menu of an entry's headline run remotely
--- (org-mouse-agenda-context-menu) and the agenda's mouse keys.
--- Part of org.org_mouse, which loads it.

local utils = require("org.utils")
local shared = require("org.org_mouse.shared")

local get_line = shared.get_line

local M = require("org.org_mouse")

--- The agenda menu of org-mouse (away from an entry).
function M.agenda_items()
  local defs = require("org.menu_defs")
  local P = defs.predicates
  local function A(label, name, active)
    return { label, agenda = name, active = active }
  end
  local view = require("org.agenda.view")
  return {
    {
      "Agenda Files",
      items = vim.tbl_map(function(f)
        return {
          utils.abbreviate(f),
          hint = false,
          fn = function()
            utils.open_file(f)
          end,
        }
      end, require("org.files").agenda_file_paths()),
    },
    "--",
    A("Undo", "undo", function()
      return #view.undo_list > 0
    end),
    A("Rebuild Buffer", "redo"),
    A("New Diary Entry", "diary_entry", P.agenda_view),
    "--",
    A("Goto Today", "today", P.agenda_view),
    A("Display Calendar", "calendar", P.agenda_view),
    {
      "Calendar Commands",
      items = {
        A("Phases of the Moon", "phases_of_moon", P.agenda_view),
        A("Sunrise/Sunset", "sunrise_sunset", P.agenda_view),
        A("Holidays", "holidays", P.agenda_view),
        A("Convert", "convert_date", P.agenda_view),
        "--",
        {
          "Create iCalendar file",
          fn = function()
            require("org.export.icalendar").combine_agenda_files({})
          end,
        },
      },
    },
    "--",
    A("Day View", "day_view", P.agenda_view),
    A("Week View", "week_view", P.agenda_view),
    "--",
    A("Show Logbook entries", "log_mode", P.agenda_view),
    A("Include Diary", "toggle_diary", P.agenda_view),
    A("Use Time Grid", "time_grid", P.agenda_view),
    A("Follow Mode", "follow_mode"),
    "--",
    A("Quit", "quit"),
    A("Exit and Release Buffers", "exit"),
  }
end

--- <RightMouse> in the agenda: on an entry, the context menu of its
--- headline at the same distance from the end of the line
--- (org-mouse-do-remotely), else the agenda menu.
---@param lnum integer
---@param col integer 1-based column of the click
function M.agenda_context_menu(lnum, col)
  local view = require("org.agenda.view")
  local menu = require("org.menu")
  pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max(col - 1, 0) })
  local item = view.item_at_cursor()
  local target = item and item.headline and item.type ~= "diary" and view.resolve_target(item)
  if not target then
    menu.define("]OrgMouse", M.agenda_items())
    M.last_kind = "agenda"
    menu.popup("]OrgMouse")
    return "agenda"
  end
  local anticol = #vim.api.nvim_get_current_line() - (col - 1)
  local bufnr = target.bufnr
  local hlnum = target.lnum
  local agenda_win = vim.api.nvim_get_current_win()
  local items
  local kind
  vim.api.nvim_buf_call(bufnr, function()
    local line = get_line(bufnr, hlnum)
    local c = math.max(#line - anticol, 0) + 1
    kind, items = M.context_items({ lnum = hlnum, col = c, line = line }, false)
  end)
  -- every entry runs in the entry's buffer, at its headline; the agenda
  -- is rebuilt afterwards
  local function remote(list)
    local out = {}
    for _, e in ipairs(list) do
      if type(e) == "table" and e.items then
        out[#out + 1] = vim.tbl_extend("force", e, { items = remote(e.items) })
      elseif type(e) == "table" and not e.title then
        local run = e
        out[#out + 1] = {
          e[1],
          hint = false,
          active = e.active,
          fn = function()
            vim.api.nvim_buf_call(bufnr, function()
              local win = vim.fn.bufwinid(bufnr)
              if win ~= -1 then
                vim.api.nvim_win_set_cursor(win, { hlnum, 0 })
              end
              local saved = vim.api.nvim_win_get_cursor(0)
              pcall(vim.api.nvim_win_set_cursor, 0, { hlnum, 0 })
              if run.action then
                require("org.actions").run(run.action)
              elseif run.fn then
                run.fn()
              end
              pcall(vim.api.nvim_win_set_cursor, 0, saved)
            end)
            if vim.api.nvim_win_is_valid(agenda_win) then
              vim.api.nvim_win_call(agenda_win, function()
                view.redo()
              end)
            end
          end,
        }
      else
        out[#out + 1] = e
      end
    end
    return out
  end
  menu.define("]OrgMouse", remote(items))
  M.last_kind = kind
  menu.popup("]OrgMouse")
  return kind
end

--- Mouse keys of org-mouse in the agenda: <RightMouse> context menu,
--- <C-ScrollWheelUp/Down> earlier / later, a horizontal right drag earlier
--- (left) or later (right).
function M.attach_agenda(bufnr)
  if not M.enabled() then
    return
  end
  local view = require("org.agenda.view")
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = bufnr, desc = "org-mouse: " .. desc })
  end
  map("<RightMouse>", function()
    M._press = { p = M.mouse_pos() }
    M.move_tree_start()
  end, "context menu")
  map("<RightDrag>", "<Nop>", "drag")
  map("<RightRelease>", function()
    local press = M._press
    M._press = nil
    local r = press and press.p and M.release_pos(press.p)
    if not r then
      return
    end
    local p = press.p
    -- in another window only the screen positions mean something here
    if p.screen[2] ~= r.screen[2] and p.screen[1] == r.screen[1] or (not r.other and p[2] ~= r[2]) then
      -- org-mouse-get-gesture
      view.run_action(r.screen[2] < p.screen[2] and "earlier" or "later")
      return
    end
    M.agenda_context_menu(p[1], p[2])
  end, "context menu / earlier-later gesture")
  map("<C-ScrollWheelUp>", function()
    view.run_action("earlier")
  end, "earlier")
  map("<C-ScrollWheelDown>", function()
    view.run_action("later")
  end, "later")
end
