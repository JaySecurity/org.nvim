---@mod org.agenda.items.planning Deadlines and scheduled entries
---
--- The deadline (org-agenda-get-deadlines) and scheduled
--- (org-agenda-get-scheduled) lines of an entry in a day agenda: warning
--- periods, delays, reminders of past and coming dates, repeats and
--- habits. Part of org.agenda.items, which loads it.

-- Not compiled by the JIT, like org.agenda.items (see the comment there).
if jit then
  jit.off(true, true)
end

local date = require("org.date")
local habits = require("org.agenda.habits")
local shared = require("org.agenda.items.shared")

local M = require("org.agenda.items")

local at_day = shared.at_day
local deadline_wdays = shared.deadline_wdays
local future_repeats = shared.future_repeats
local int = shared.int
local new_item = shared.new_item
local planning_dotime = shared.planning_dotime
local prefers_last = shared.prefers_last
local set_time = shared.set_time

local last_occ = M.last_occ

--- The deadline lines of `hl` (org-agenda-get-deadlines); the days they
--- show on are set in `dl_shown`.
---@param ctx org.agenda.items.DayContext
---@param hl org.Headline
---@param done boolean
---@param dl_shown table<integer, boolean>
function shared.deadlines(ctx, hl, done, dl_shown)
  local cfg, acfg, types, today, from, to, add = ctx.cfg, ctx.acfg, ctx.types, ctx.today, ctx.from, ctx.to, ctx.add
  local leaders_d, dl_past_days = ctx.leaders_d, ctx.dl_past_days
  local dl = hl.planning.deadline
  local dl_type = types.deadline or (types["deadline*"] and dl and dl.hour)
  if dl and dl.active ~= false and dl_type then
    local base = prefers_last(acfg, hl.todo) and last_occ(dl, today) or dl:days()
    local wdays = acfg.deadline_warning_days or cfg.deadline_warning_days
    local warn = deadline_wdays(dl, wdays)
    local skip_pre = acfg.skip_deadline_prewarning_if_scheduled
    local sched = hl.planning.scheduled
    if skip_pre and sched then
      local max
      if int(skip_pre) then
        max = skip_pre
      elseif skip_pre == "pre-scheduled" then
        max = math.min(base - sched:days(), wdays or 14)
      else
        max = 0
      end
      warn = math.min(warn, max)
    end
    local days = { [base] = true }
    for _, d in ipairs(future_repeats(dl, acfg, today, from, to)) do
      days[d] = "repeat"
    end
    if today >= from and today <= to then
      days[today] = days[today] or "today"
    end
    for c, kind in pairs(days) do
      -- days outside the range are dropped by add(): don't build them
      local show = c >= from and c <= to
      local diff = base - c
      if show and c ~= base and kind ~= "repeat" then
        -- reminder in today's agenda
        if base > c then
          show = diff <= warn
        else
          show = -diff <= dl_past_days
        end
      end
      if show and done and (acfg.skip_deadline_if_done or base ~= c) then
        show = false
      end
      if show then
        local leader
        if c == today and base < today then
          leader = string.format(leaders_d[3], -diff)
        elseif c == today and base > today then
          leader = string.format(leaders_d[2], diff)
        else
          leader = leaders_d[1]
        end
        local upcoming = c == today and base > today
        local item = new_item(hl, {
          type = "deadline",
          ts_type = upcoming and "upcoming-deadline" or "deadline",
          date = (c == base or kind == "repeat") and at_day(dl, c) or dl,
          ts_date = base,
          extra = leader,
          face = done and "OrgAgendaDone" or M.deadline_face(1 - diff / math.max(warn, 1)),
          undone_face = M.deadline_face(1 - diff / math.max(warn, 1)),
          fixface = true,
          reminder = c ~= base and kind ~= "repeat" or nil,
          overdue = c == today and base < today or nil,
          upcoming = upcoming and diff or nil,
          repeat_occurrence = kind == "repeat" or nil,
        })
        item.urgency = item.prio + (c == today and (today - base) or 0)
        if c == base or kind == "repeat" then
          local dotime = planning_dotime(hl, "DEADLINE")
          set_time(item, dotime == nil and dl or nil, acfg, nil, nil, dotime or nil)
        end
        add(c, item)
        dl_shown[c] = true
      end
    end
  end
end

--- The scheduled lines of `hl` (org-agenda-get-scheduled), habits
--- included; one on a day in `dl_shown` may be skipped
--- (agenda.skip_scheduled_if_deadline_is_shown).
---@param ctx org.agenda.items.DayContext
---@param hl org.Headline
---@param done boolean
---@param dl_shown table<integer, boolean>
function shared.scheduled(ctx, hl, done, dl_shown)
  local cfg, acfg, types, today, from, to, add = ctx.cfg, ctx.acfg, ctx.types, ctx.today, ctx.from, ctx.to, ctx.add
  local habit_cfg, leaders_s, sc_past_days = ctx.habit_cfg, ctx.leaders_s, ctx.sc_past_days
  local s = hl.planning.scheduled
  local s_type = types.scheduled or (types["scheduled*"] and s and s.hour)
  if s and s.active ~= false and s_type then
    local is_habit = habits.is_habit(hl)
    local habit = is_habit and habits.parse(hl) or nil
    local base = prefers_last(acfg, hl.todo) and last_occ(s, today) or s:days()
    -- org-get-wdays with DELAY: a negative org-scheduled-delay-days is
    -- enforced, else the -Nd cookie, else org-scheduled-delay-days
    local tv = acfg.scheduled_delay_days or cfg.scheduled_delay_days or 0
    local wd
    if tv < 0 then
      wd = -tv
    elseif s.warning then
      wd = date.warning_days(s, 0)
    else
      wd = tv
    end
    local max = math.huge
    local sdd = acfg.skip_scheduled_delay_if_deadline
    if sdd and hl.planning.deadline then
      if int(sdd) then
        max = -sdd
      elseif sdd == "post-deadline" then
        max = math.min(base - hl.planning.deadline:days(), tv)
      else
        max = 0
      end
    end
    local delay = math.min(max, wd)
    if s.warning and s.warning.type == "--" and base > s:days() then
      -- a --Xd delay only applies to the first occurrence
      delay = 0
    end
    local past_days = (is_habit and habit_cfg.scheduled_past_days) or sc_past_days
    local days = { [base] = true }
    for _, d in ipairs(future_repeats(s, acfg, today, from, to)) do
      days[d] = "repeat"
    end
    if today >= from and today <= to then
      days[today] = days[today] or "today"
    end
    local show_all = is_habit and habit_cfg.show_all_today
    for c, kind in pairs(days) do
      local diff = c - base
      local show = c >= from and c <= to
      if show and not (c == today and show_all) then
        if (delay > 0 and diff < delay) or diff > past_days or base > c then
          show = false
        elseif c ~= base and c ~= today and kind ~= "repeat" then
          show = false
        end
      end
      if show and done and (acfg.skip_scheduled_if_done or base ~= c) then
        show = false
      end
      if show and acfg.skip_scheduled_repeats_after_deadline and hl.planning.deadline then
        local dld = hl.planning.deadline:days()
        if (s:days() <= dld or base ~= c) and c > dld then
          show = false
        end
      end
      local sid = acfg.skip_scheduled_if_deadline_is_shown
      if show and sid and not is_habit and dl_shown[c] then
        if sid == "not-today" then
          show = not (base < today)
        else
          show = false
        end
      end
      if show and is_habit then
        if done or habit_cfg.show_habits == false or not habit then
          show = false
        elseif c ~= today and habit_cfg.show_habits_only_for_today ~= false then
          show = false
        end
      end
      if show then
        local past = base < today
        local leader = (c == today and past) and string.format(leaders_s[2], diff) or leaders_s[1]
        local face
        if not is_habit and past then
          face = "OrgAgendaScheduledPast"
        elseif is_habit and base > today then
          face = "OrgAgendaDone"
        elseif c == today then
          face = "OrgAgendaScheduled"
        else
          face = "OrgAgendaScheduled"
        end
        local item = new_item(hl, {
          type = "scheduled",
          ts_type = past and "past-scheduled" or "scheduled",
          date = (c == base or kind == "repeat") and at_day(s, c) or s,
          ts_date = base,
          extra = leader,
          face = done and "OrgAgendaDone" or face,
          undone_face = face,
          fixface = true,
          habit = habit,
          reminder = (c ~= base and kind ~= "repeat") or nil,
          past = (c == today and past) and diff or nil,
          repeat_occurrence = kind == "repeat" or nil,
        })
        if habit then
          item.urgency = habits.urgency(habit, today)
        else
          item.urgency = 99 + diff + item.prio
        end
        if is_habit or c == base or kind == "repeat" then
          local dotime = planning_dotime(hl, "SCHEDULED")
          set_time(item, dotime == nil and s or nil, acfg, nil, nil, dotime or nil)
        end
        add(c, item)
      end
    end
  end
end
