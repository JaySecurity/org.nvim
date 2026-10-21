---@mod org.org_mouse.context org-mouse context menus
---
--- What is under the mouse and its menu (org-mouse-context-menu): the
--- region, #+STARTUP options, checkboxes, TODO keywords, planning
--- keywords, priorities, links, tags, timestamps, tables and headlines,
--- else the general menu; and showing it.
--- Part of org.org_mouse, which loads it.

local utils = require("org.utils")
local shared = require("org.org_mouse.shared")

local get_line, set_line = shared.get_line, shared.set_line
local checkbox_range, for_each_item = shared.checkbox_range, shared.for_each_item
-- the menu builders of org.org_mouse.menus (loaded before this part)
local toggle, todo_keywords, todo_menu = shared.toggle, shared.todo_keywords, shared.todo_menu
local replace_menu, priority_list, tag_menu = shared.replace_menu, shared.priority_list, shared.tag_menu
local grep, agenda, sparse_tags, word_at = shared.grep, shared.agenda, shared.sparse_tags, shared.word_at
local global_menu, headline_menu, table_menu = shared.global_menu, shared.headline_menu, shared.table_menu
local TABLE_MARKS, TABLE_MARK_LABELS = shared.TABLE_MARKS, shared.TABLE_MARK_LABELS

local M = require("org.org_mouse")

--- The context of a click at `ctx.col` (1-based, past the end = #line + 1)
--- of line `ctx.lnum`, and its menu items; the cursor is on the click.
---@param ctx { lnum: integer, col: integer, line: string, visual?: { text: string, s: integer[], e: integer[] } }
---@param direct? boolean false for a menu from the agenda
---@return string kind, (org.MenuEntry|string)[] items
function M.context_items(ctx, direct)
  if direct == nil then
    direct = true
  end
  local line, col, lnum = ctx.line, ctx.col, ctx.lnum
  local parser = require("org.parser")
  if ctx.visual then
    local text = ctx.visual.text
    local vs, ve = ctx.visual.s, ctx.visual.e
    return "region",
      {
        {
          "Sparse Tree",
          fn = function()
            require("org.agenda.sparse").regexp("\\V" .. text:gsub("\\", "\\\\"))
          end,
        },
        {
          "Find in Buffer",
          fn = function()
            vim.cmd("lvimgrep /\\V" .. vim.fn.escape(text, "/\\") .. "/j %")
            vim.cmd("lopen")
          end,
        },
        {
          "Grep in Current Dir",
          fn = function()
            grep("-rnH -e " .. vim.fn.shellescape(text) .. " ./*")
          end,
        },
        {
          "Grep in Parent Dir",
          fn = function()
            grep("-rnH -e " .. vim.fn.shellescape(text) .. " ../*")
          end,
        },
        "--",
        {
          "Convert to Link",
          fn = function()
            -- the end first, so the start stays put
            vim.api.nvim_buf_set_text(0, ve[1] - 1, ve[2], ve[1] - 1, ve[2], { "]]" })
            vim.api.nvim_buf_set_text(0, vs[1] - 1, vs[2] - 1, vs[1] - 1, vs[2] - 1, { "[[" })
          end,
        },
        {
          "Insert Link Here",
          fn = function()
            M.yank_link(lnum, col)
          end,
        },
      }
  end
  local startup = line:match("^[ \t]*#%+[Ss][Tt][Aa][Rr][Tt][Uu][Pp]: (.*)$")
  if startup then
    local opts = vim.split(startup, "%s+", { trimempty = true })
    local items = {}
    for _, name in ipairs(M.STARTUP_OPTIONS) do
      local on = vim.tbl_contains(opts, name)
      items[#items + 1] = {
        toggle(name, on),
        hint = false,
        fn = function()
          local new = vim.tbl_filter(function(o)
            return o ~= name
          end, opts)
          if not on then
            new[#new + 1] = name
          end
          table.sort(new, function(a, b)
            return utils.string_lessp(a, b)
          end)
          local l = get_line(0, lnum)
          local prefix = l:match("^([ \t]*#%+[Ss][Tt][Aa][Rr][Tt][Uu][Pp]: )")
          set_line(0, lnum, prefix .. table.concat(new, " "))
          -- org-mode-restart
          local buf = vim.api.nvim_get_current_buf()
          vim.b[buf].org_attached = nil
          vim.b[buf].did_ftplugin = nil
          vim.bo[buf].filetype = "org"
        end,
      }
    end
    return "startup", items
  end
  -- at the end of the line, or in the white space ending it
  local rest = line:sub(col)
  if col > #line or (#rest >= 2 and rest:match("^[ \t]+$") and line:sub(col - 1, col - 1):match("[ \t]")) then
    return "global", global_menu(ctx)
  end
  local cs, ce = checkbox_range(line)
  if cs and col >= cs and col <= ce and not parser.headline_level(line) then
    local function set_all(mark)
      return function()
        for_each_item(function(l)
          local text = get_line(0, l)
          local a, b = checkbox_range(text)
          if a then
            if mark == false then
              M.remove_match_and_spaces(l, a, b)
            else
              set_line(0, l, text:sub(1, a - 1) .. mark .. text:sub(b + 1))
            end
          end
        end)
      end
    end
    return "checkbox",
      {
        { "Toggle", action = "toggle_checkbox" },
        {
          "Remove",
          fn = function()
            M.remove_match_and_spaces(lnum, cs, ce)
          end,
        },
        "--",
        { "All Clear", fn = set_all("[ ]") },
        { "All Set", fn = set_all("[X]") },
        {
          "All Toggle",
          fn = function()
            for_each_item(function(l)
              vim.api.nvim_win_set_cursor(0, { l, 0 })
              if checkbox_range(get_line(0, l)) then
                require("org.lists").toggle_checkbox()
              end
            end)
          end,
        },
        { "All Remove", fn = set_all(false) },
      }
  end
  local _, _, word = word_at(line, col, "[%w_]", "%f[%w_][%w_]+")
  if word and vim.tbl_contains(todo_keywords(), word) then
    local items = todo_menu(lnum, word)
    vim.list_extend(items, {
      "--",
      {
        "Check TODOs",
        fn = function()
          require("org.agenda.sparse").headlines(function(hl)
            return hl:is_todo()
          end, "TODO entries")
        end,
      },
      { "List all TODO keywords", fn = agenda("t") },
      { "List only " .. word, fn = agenda("T " .. word) },
    })
    return "todo", items
  end
  local ks, ke, kw = word_at(line, col, "[A-Z]", "%f[%w_][A-Z]+:")
  if kw and (kw == "DEADLINE:" or kw == "SCHEDULED:") then
    local items = replace_menu(lnum, ks, ke, { "DEADLINE:", "SCHEDULED:" }, kw)
    vim.list_extend(items, {
      "--",
      {
        "Check Deadlines",
        fn = function()
          require("org.agenda.sparse").deadlines()
        end,
      },
    })
    return "planning", items
  end
  local ps, pe = word_at(line, col, "[%[%]A-Z#]", "%[#[A-Z]%]")
  if ps then
    local cur = line:sub(ps + 2, ps + 2)
    return "priority", replace_menu(lnum, ps + 2, ps + 2, priority_list(), cur, "Priority %s", true, ps, pe)
  end
  vim.api.nvim_win_set_cursor(0, { lnum, math.max(math.min(col, #line) - 1, 0) })
  local link = require("org.links").link_at_cursor()
  if link and link.lnum == lnum then
    local s, e = link.start_col, link.end_col
    return "link",
      {
        { "Open", action = "open_at_point" },
        {
          "Open in Neovim",
          fn = function()
            require("org.links").open_at_point(4)
          end,
        },
        "--",
        {
          "Copy link",
          fn = function()
            vim.fn.setreg('"', line:sub(s, e))
          end,
        },
        {
          "Cut link",
          fn = function()
            vim.fn.setreg('"', line:sub(s, e))
            M.remove_match_and_spaces(lnum, s, e)
          end,
        },
        "--",
        {
          "Grep for TODOs",
          fn = function()
            local path = (link.path or link.target or ""):gsub("::.*$", "")
            grep("-nH -i " .. vim.fn.shellescape("todo\\|fixme") .. " " .. vim.fn.fnameescape(path) .. "*")
          end,
        },
      }
  end
  local _, _, tag = word_at(line, col, "[%w_]", ":[%w_]+:", -1)
  if tag then
    tag = tag:sub(2, -2)
    local items = {
      { string.format("Display ‘%s’", tag), fn = agenda("m " .. tag), hint = false },
      { string.format("Sparse Tree ‘%s’", tag), fn = sparse_tags(tag), hint = false },
      "--",
    }
    vim.list_extend(items, tag_menu(lnum))
    return "tags", items
  end
  if require("org.timestamps").at_cursor() then
    local ts = require("org.timestamps")
    local function change(n, unit)
      return function()
        M.timestamp_change(n, unit)
      end
    end
    local function today(n, unit)
      return function()
        M.timestamp_today(n, unit)
      end
    end
    return "timestamp",
      {
        { "Show Day", action = "open_at_point" },
        {
          "Change Timestamp",
          fn = function()
            ts.insert_active({ edit = true })
          end,
        },
        { "Delete Timestamp", fn = M.delete_timestamp },
        {
          "Compute Time Range",
          action = "evaluate_time_range",
          active = function()
            local it = ts.at_cursor()
            return it ~= nil and it.date.range_end ~= nil
          end,
        },
        "--",
        { "Set for Today", fn = today() },
        { "Set for Tomorrow", fn = today(1, "day") },
        { "Set in 1 Week", fn = today(7, "day") },
        { "Set in 2 Weeks", fn = today(14, "day") },
        { "Set in a Month", fn = today(1, "month") },
        "--",
        { "+ 1 Day", fn = change(1, "day") },
        { "+ 1 Week", fn = change(7, "day") },
        { "+ 1 Month", fn = change(1, "month") },
        "--",
        { "- 1 Day", fn = change(-1, "day") },
        { "- 1 Week", fn = change(-7, "day") },
        { "- 1 Month", fn = change(-1, "month") },
      }
  end
  local tbl = require("org.table").find(0, lnum)
  if tbl then
    local ms, mark = line:match("^[ \t]*|() *([#*$!_^/']) *|")
    local mcol = ms and line:find("[#*$!_^/']", ms)
    if mark and mcol and col >= ms and col <= line:find("|", mcol, true) then
      return "table-special",
        replace_menu(lnum, mcol, mcol, TABLE_MARKS, mark, function(m)
          return TABLE_MARK_LABELS[m]
        end, true)
    end
    return "table", table_menu()
  end
  if parser.headline_level(line) and col <= #line then
    return "headline", headline_menu(ctx, direct)
  end
  return "global", global_menu(ctx)
end

--- Emacs's org-startup-options, in its order.
M.STARTUP_OPTIONS = vim.split(
  table.concat({
    "fold overview nofold showall show2levels show3levels show4levels show5levels",
    "showeverything content indent noindent num nonum hidestars showstars odd oddeven align",
    "noalign shrink descriptivelinks literallinks inlineimages noinlineimages linkpreviews",
    "nolinkpreviews latexpreview nolatexpreview customtime logdone lognotedone nologdone",
    "lognoteclock-out nolognoteclock-out logrepeat lognoterepeat logdrawer nologdrawer",
    "logstatesreversed nologstatesreversed nologrepeat logreschedule lognotereschedule",
    "nologreschedule logredeadline lognoteredeadline nologredeadline logrefile lognoterefile",
    "nologrefile fninline nofninline fnlocal fnauto fnprompt fnconfirm fnplain fnadjust",
    "nofnadjust fnanon constcgs constSI noptag hideblocks nohideblocks hidedrawers",
    "nohidedrawers beamer entitiespretty entitiesplain",
  }, " "),
  " "
)

--- The context menu for the cursor position, or the Visual selection.
function M.context_menu_at_cursor()
  local visual = M.visual_region()
  local lnum, col = utils.cursor()
  M.show_context_menu({ lnum = lnum, col = col, line = vim.api.nvim_get_current_line(), visual = visual })
  return true
end

--- Show the context menu for `ctx` (org-mouse-show-context-menu).
function M.show_context_menu(ctx, direct)
  local kind, items = M.context_items(ctx, direct)
  local menu = require("org.menu")
  menu.define("]OrgMouse", items)
  M.last_kind = kind
  menu.popup("]OrgMouse")
  return kind
end
