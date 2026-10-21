---@mod org.agenda.render.dates Day headers and agenda spans
---
--- ISO weeks, the day header (org-agenda-format-date), the day range of a
--- span (org-agenda-list, org-agenda-compute-starting-span), moving it
--- (org-agenda-later) and its name (org-agenda-span-name). Part of
--- org.agenda.render, which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

--- ISO 8601 week number for a day number.
function M.iso_week(days)
  local wd = (days + 3) % 7 + 1
  local thu = days - (wd - 1) + 3
  local y = date.civil_from_days(thu)
  local jan1 = date.days_from_civil(y, 1, 1)
  return math.floor((thu - jan1) / 7) + 1, y
end

--- "Wednesday  23 September 2026 W39" (org-agenda-format-date-aligned;
--- the week is shown on Mondays).
function M.date_header(days, show_week)
  local d = date.from_days(days)
  local wk = show_week and string.format(" W%02d", (M.iso_week(days))) or ""
  return string.format(
    "%-10s %2d %s %4d%s",
    date.DAY_NAMES_LONG[d:weekday()],
    d.day,
    date.MONTH_NAMES_LONG[d.month],
    d.year,
    wk
  )
end

--- Day header per `agenda.format_date` (org-agenda-format-date): nil for
--- the aligned default, a strftime format, or a function(date) -> string.
function M.format_date(days)
  local f = config.opts.agenda.format_date
  if type(f) == "function" then
    return tostring(f(date.from_days(days)))
  elseif type(f) == "string" and f ~= "" then
    return date.from_days(days):strftime(f)
  end
  local wd = date.from_days(days):weekday()
  return M.date_header(days, wd == 1)
end

local function span_days(span, anchor)
  if span == "day" then
    return 1
  elseif span == "week" then
    return 7
  elseif span == "fortnight" then
    return 14
  elseif span == "month" and anchor then
    local a = date.from_days(anchor)
    return date.days_in_month(a.year, a.month)
  elseif span == "year" and anchor then
    return date.is_leap(date.from_days(anchor).year) and 366 or 365
  end
  return tonumber(span)
end
M.span_days = span_days

--- Compute the [from, to] day range for a span starting on `anchor`
--- (org-agenda-list): a month or year span starts on the anchor and lasts
--- as many days as the anchor's month or year; 7 and 14 day spans start on
--- `start_on_weekday` when `align` is set.
---@param span string|integer
---@param anchor integer day number
---@param align boolean align weeks to start_on_weekday
function M.range(span, anchor, align)
  local acfg = config.opts.agenda
  local a = date.from_days(anchor)
  local n = span_days(span, anchor) or 7
  local start = anchor
  if align and (n == 7 or n == 14) and acfg.start_on_weekday then
    start = anchor - ((a:weekday() - acfg.start_on_weekday) % 7)
  end
  return start, start + n - 1
end

--- The first day of the span containing `day` when the view changes to
--- `span` (org-agenda-compute-starting-span).
function M.starting_day(span, day)
  local acfg = config.opts.agenda
  local d = date.from_days(day)
  if span == "week" or span == "fortnight" or span == 7 or span == 14 then
    if acfg.start_on_weekday then
      return day - ((d:weekday() - acfg.start_on_weekday) % 7)
    end
    return day
  elseif span == "month" then
    return date.days_from_civil(d.year, d.month, 1)
  elseif span == "year" then
    return date.days_from_civil(d.year, 1, 1)
  end
  return day
end

--- Move a starting day by `n` spans (org-agenda-later).
function M.shift_anchor(span, anchor, n)
  if span == "month" then
    return date.from_days(anchor):add(n, "m"):days()
  elseif span == "year" then
    return date.from_days(anchor):add(n, "y"):days()
  end
  return anchor + (span_days(span) or 7) * n
end

--- org-agenda-span-name
local function span_name(span)
  local names = { day = "Day", week = "Week", fortnight = "Fortnight", month = "Month", year = "Year" }
  if names[span] then
    return names[span]
  end
  local n = tonumber(span)
  if n == 1 then
    return "Day"
  elseif n == 7 then
    return "Week"
  elseif n == 14 then
    return "Fortnight"
  end
  return string.format("%d days", n or 0)
end
M.span_name = span_name

shared.span_name = span_name

return M
