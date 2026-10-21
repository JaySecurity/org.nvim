---@mod org.agenda.render.day The agenda (date range) block
---
--- The days of an agenda block with their headers, the time grid
--- (org-agenda-add-time-grid-maybe) and the clock report. Part of
--- org.agenda.render, which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")
local items_mod = require("org.agenda.items")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

local clock_issue = shared.clock_issue
local filter_list = shared.filter_list
local insert_header = shared.insert_header
local sorting_for = shared.sorting_for
local span_name = shared.span_name

local function grid_minutes(t)
  return math.floor(t / 100) * 60 + t % 100
end

--- org-agenda-add-time-grid-maybe: should the grid be shown, and should
--- it drop the grid times that an entry has (remove-match)?
---@return boolean shown
---@return boolean? remove
local function show_grid(grid, d, today, ndays, has_timed)
  if not grid or grid.enabled == false or grid.hidden then
    return false
  end
  local set = {}
  for _, t in ipairs(grid.type or { "daily", "today", "require-timed" }) do
    set[t] = true
  end
  if not ((d == today and set.today) or (ndays == 1 and set.daily) or set.weekly) then
    return false
  end
  if set["require-timed"] and not has_timed then
    return false
  end
  return true, set["remove-match"] == true
end

--- A time grid line or the current-time line as a pseudo item.
local function grid_item(minutes, text, group)
  return {
    grid = true,
    time = minutes,
    category = "",
    urgency = 0,
    prio = 0,
    title = text,
    face = group,
    tags = {},
    order = 0,
  }
end

--- Render the item list of one day, with time grid.
local function render_day(b, list, d, ctx, sorting)
  local acfg = config.opts.agenda
  local grid = acfg.time_grid or {}
  local have = {}
  local has_timed = false
  for _, it in ipairs(list) do
    if it.time then
      has_timed = true
      have[it.sort_time or it.time] = true
    end
  end
  local rows = list
  local shown, remove = false, nil ---@type boolean, boolean?
  if not ctx.time_grid_off then
    shown, remove = show_grid(grid, d, ctx.today, ctx.ndays, has_timed)
  end
  if shown then
    local new = {}
    local sep = grid.separator or " ┄┄┄┄┄ "
    local _ = sep
    for _, t in ipairs(grid.times or {}) do
      local m = grid_minutes(t)
      if not (remove and have[m]) then
        table.insert(new, 1, grid_item(m, grid.time_string or "", "OrgAgendaTimeGrid"))
      end
    end
    if d == ctx.today and ctx.now and acfg.show_current_time_in_grid ~= false then
      table.insert(new, 1, grid_item(ctx.now, acfg.current_time_string or "now", "OrgAgendaCurrentTime"))
    end
    rows = {}
    if vim.tbl_contains(sorting, "time-up") then
      vim.list_extend(rows, new)
      vim.list_extend(rows, list)
    else
      vim.list_extend(rows, list)
      vim.list_extend(rows, new)
    end
  else
    rows = vim.list_slice(list)
  end
  items_mod.sort(rows, sorting)
  rows = M.apply_limits(rows, "agenda", ctx)
  local function add(it)
    if it.grid then
      local prefix = M.prefix(it, "agenda")
      local ps = #prefix:match("^%s*")
      b:add({ { prefix:sub(1, math.min(ps, 2)) }, { prefix:sub(math.min(ps, 2) + 1) .. it.title, it.face } })
    else
      if ctx.log_mode == "clockcheck" and it.clock then
        local issue = clock_issue(it, ctx.clockcheck)
        if issue then
          b:add({ { string.format("%-43s", " " .. issue), "OrgAgendaClockIssue" } })
        end
      end
      M.add_item(b, it, ctx)
    end
  end
  if M.grouper and M.grouper(b, rows, ctx.block or {}, ctx, add, d) then
    return
  end
  for _, it in ipairs(rows) do
    add(it)
  end
end

--- Is `d` (day number) a weekend day (org-agenda-weekend-days, 0 = Sunday)?
local function is_weekend(d)
  local wd = date.from_days(d):weekday() % 7
  for _, w in ipairs(config.opts.agenda.weekend_days or { 6, 0 }) do
    if w == wd then
      return true
    end
  end
  return false
end
M.is_weekend = is_weekend

--- Render an agenda (date range) block.
---@param block table
---@param ctx table { files, span, anchor, align, today, now, width, log_mode, clockreport, restrict, filter, is_clocking }
function M.agenda_block(b, block, ctx)
  local acfg = config.opts.agenda
  local span = ctx.span or block.span or acfg.span or "week"
  local from, to = M.range(span, ctx.anchor, ctx.align)
  local ndays = to - from + 1
  local by_day = items_mod.agenda(ctx.files, from, to, {
    today = ctx.today,
    log_mode = ctx.log_mode,
    inactive = ctx.inactive,
    no_deadlines = ctx.no_deadlines,
    include_diary = ctx.include_diary,
    archives = ctx.archives,
    restrict = ctx.restrict,
    skip = block.skip,
    block = block,
  })
  if not acfg.compact_blocks then
    local w1, w2 = M.iso_week(from), M.iso_week(to)
    local wk
    if to - from >= 350 then
      wk = ""
    elseif w1 == w2 then
      wk = string.format(" (W%02d)", w1)
    else
      wk = string.format(" (W%02d-W%02d)", w1, w2)
    end
    insert_header(b, block, span_name(span) .. "-agenda" .. wk .. ":")
  end
  local sorting = sorting_for(block, "agenda")
  local dctx = vim.tbl_extend(
    "force",
    ctx,
    { agenda = true, kind = "agenda", span = span, ndays = ndays, clockcheck = {}, block = block }
  )
  for d = from, to do
    local list = filter_list(by_day[d] or {}, ctx)
    if #list > 0 or acfg.show_all_dates ~= false then
      local group = "OrgAgendaDate"
      local dff = acfg.day_face_function
      local custom = type(dff) == "function" and dff(date.from_days(d)) or nil
      if type(custom) == "string" and custom ~= "" then
        -- org-agenda-day-face-function
        group = custom
      elseif d == ctx.today then
        group = "OrgAgendaDateToday"
      elseif is_weekend(d) then
        group = "OrgAgendaDateWeekend"
      end
      b:add({ { M.format_date(d), group } }, nil)
      b.day_lines = b.day_lines or {}
      b.day_lines[#b.lines] = d
      render_day(b, list, d, dctx, sorting)
    end
  end
  if ctx.clockreport then
    M.clock_report(b, ctx.files, from, to)
  end
  return { from = from, to = to, span = span }
end

return M
