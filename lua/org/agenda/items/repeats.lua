---@mod org.agenda.items.repeats Repeating timestamps (org-closest-date)
---
--- The occurrences of a repeating timestamp around a day, the future
--- repeats a view shows (org-agenda-show-future-repeats) and
--- org-agenda-prefer-last-repeat. Part of org.agenda.items, which loads
--- it.

-- Not compiled by the JIT, like org.agenda.items (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")
local shared = require("org.agenda.items.shared")

local M = require("org.agenda.items")

local function repeating(ts)
  return ts.repeater and ts.repeater.value and ts.repeater.value > 0
end

--- The k-th occurrence day of a repeating timestamp (k = 0 is the base).
local function nth_occ(ts, k)
  local r = ts.repeater
  if r.unit == "d" then
    return ts:days() + k * r.value
  elseif r.unit == "w" then
    return ts:days() + k * r.value * 7
  elseif r.unit == "h" then
    return ts:days() + math.floor(((ts.hour or 0) + k * r.value) / 24)
  end
  return ts:add(k * r.value, r.unit):days()
end

--- Neighboring repeat days. Calendar units use actual month/year offsets;
--- estimating months as 28 days can overshoot years-old repeaters.
local function neighboring_occurrences(ts, day)
  local r = ts.repeater
  if r.unit == "h" then
    -- org-closest-date evaluates hourly repeats at the effective start of
    -- the agenda day, including org-extend-today-until.
    local missing = (24 * (day - ts:days()) - (ts.hour or 0) + (config.opts.extend_today_until or 0)) % r.value
    local before = missing == 0 and day or day - (1 + math.floor(missing / 24))
    local after = day + math.floor((r.value - missing) / 24)
    return before, after
  end
  local y, m = date.civil_from_days(day)
  local elapsed = r.unit == "y" and (y - ts.year) or ((y - ts.year) * 12 + m - ts.month)
  local k = math.max(0, math.floor(elapsed / r.value))
  while k > 0 and nth_occ(ts, k) > day do
    k = k - 1
  end
  while nth_occ(ts, k + 1) <= day do
    k = k + 1
  end
  return nth_occ(ts, k), nth_occ(ts, k + 1)
end

--- Smallest occurrence day >= `day` (the base when it is later).
local function next_occ(ts, day)
  local base = ts:days()
  if not repeating(ts) or base >= day then
    return base
  end
  local r = ts.repeater
  if r.unit == "d" or r.unit == "w" then
    local step = r.value * (r.unit == "w" and 7 or 1)
    return base + math.ceil((day - base) / step) * step
  end
  local before, after = neighboring_occurrences(ts, day)
  return before == day and day or after
end

--- Largest occurrence day <= `day` (the base when it is later).
local function last_occ(ts, day)
  local base = ts:days()
  if not repeating(ts) or base >= day then
    return base
  end
  local r = ts.repeater
  if r.unit == "d" or r.unit == "w" then
    local step = r.value * (r.unit == "w" and 7 or 1)
    return base + math.floor((day - base) / step) * step
  end
  local before, after = neighboring_occurrences(ts, day)
  return after == day and day or before
end
M.next_occ, M.last_occ = next_occ, last_occ

--- A copy of `ts` moved to `day` (keeping the time).
local function at_day(ts, day)
  if ts:days() == day then
    return ts
  end
  local y, m, d = date.civil_from_days(day)
  return ts:clone({ year = y, month = m, day = d })
end

--- Is `kw` in the prefer-last-repeat setting (true or a list of keywords)?
local function prefers_last(acfg, todo)
  local p = acfg.prefer_last_repeat
  if p == true then
    return true
  elseif type(p) == "table" then
    return todo ~= nil and vim.tbl_contains(p, todo)
  elseif type(p) == "string" then
    return p == todo
  end
  return false
end

--- Days with a future repeat shown (org-agenda-show-future-repeats) in
--- [from, to]: every occurrence after today, or only the first one.
local function future_repeats(ts, acfg, today, from, to)
  local out = {}
  local fr = acfg.show_future_repeats
  if not repeating(ts) or fr == false or to <= today then
    return out
  end
  if fr == "next" then
    local d = next_occ(ts, today + 1)
    if d >= from and d <= to then
      out[1] = d
    end
    return out
  end
  local d = next_occ(ts, math.max(from, today + 1))
  local guard = 0
  while d <= to and guard < 2000 do
    out[#out + 1] = d
    local nd = next_occ(ts, d + 1)
    if nd <= d then
      break
    end
    d = nd
    guard = guard + 1
  end
  return out
end

shared.repeating = repeating
shared.at_day = at_day
shared.prefers_last = prefers_last
shared.future_repeats = future_repeats
