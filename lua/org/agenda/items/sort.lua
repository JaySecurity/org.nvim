---@mod org.agenda.items.sort Sorting agenda items (org-entries-lessp)
---
--- The sorting strategies of `agenda.sorting` (org-agenda-sorting-strategy)
--- as comparators, the timestamp list entries sort by
--- (org-agenda-entry-get-agenda-timestamp), item efforts and a stable sort.
--- Part of org.agenda.items, which loads it.

-- Not compiled by the JIT, like org.agenda.items (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")

local M = require("org.agenda.items")

local function todo_rank(item)
  -- org-cmp-todo-state: done states first, then by position in the sequence
  local cfg = item.headline and item.headline.file.settings.todo
  local kw = item.todo
  if not cfg or not kw then
    return 0, false
  end
  local names = cfg:names()
  local idx
  for i, n in ipairs(names) do
    if n == kw then
      idx = i
    end
  end
  -- (length (member ta kwds)) = #names - idx + 1; Emacs compares its negation
  return idx and -(#names - idx + 1) or 0, cfg:is_done(kw)
end

--- Effort of an item in minutes, or nil.
function M.effort(item)
  if item.effort_minutes ~= nil then
    return item.effort_minutes or nil
  end
  if not item.headline then
    return nil
  end
  local v = item.headline:get_property(config.opts.effort_property or "Effort")
  local m = v and date.parse_duration(v) or nil
  item.effort_minutes = m or false
  return m
end

--- Statistics cookie of the headline as a percentage (stats-up/-down).
local function stats(item)
  local t = item.title or ""
  local a, b = t:match("%[(%d+)/(%d+)%]")
  if a then
    b = tonumber(b)
    return b > 0 and math.floor(100 * tonumber(a) / b) or 0
  end
  local p = t:match("%[(%d+)%%%]")
  return p and tonumber(p) or 0
end

local function cmp_num(a, b)
  if a > b then
    return 1
  elseif a < b then
    return -1
  end
end

local function lower_title(item)
  -- Emacs strips the TODO keyword but not a "[#A]" cookie (org-cmp-alpha)
  local t = item.display_title or item.title or ""
  if item.priority then
    t = "[#" .. item.priority .. "] " .. t
  end
  return t:lower()
end

local function first_tag(item)
  -- Emacs compares the last tag of the list
  local tags = item.tags or {}
  return tags[#tags]
end

local function ts_value(item, typ)
  local late = config.opts.agenda.sort_notime_is_late ~= false
  local def = late and math.huge or -1
  if not item.ts_date or not item.ts_type then
    return def
  end
  if typ ~= "" and not item.ts_type:find(typ, 1, true) then
    return def
  end
  return item.ts_date
end

local function time_value(item)
  if item.time then
    return item.sort_time or item.time
  end
  return config.opts.agenda.sort_notime_is_late ~= false and 99 * 60 + 1 or -1
end

local function effort_value(item)
  local e = M.effort(item)
  if e then
    return e
  end
  return config.opts.agenda.sort_noeffort_is_high ~= false and math.huge or -1
end

local function cat(item)
  return item.category or ""
end

-- results of string_cmp during one M.sort: a list has few distinct
-- categories and tags, and collation is costly (a Vim call per comparison)
local cmp_memo

local function string_cmp(a, b)
  -- org-string< (org-sort-function)
  if a == b then
    return nil
  end
  local key = cmp_memo and a .. "\0" .. b
  local r = key and cmp_memo[key]
  if r == nil then
    local lessp = require("org.utils").string_lessp
    if lessp(a, b) then
      r = -1
    elseif lessp(b, a) then
      r = 1
    else
      r = false
    end
    if key then
      cmp_memo[key] = r
    end
  end
  return r or nil
end

local function todo_cmp(a, b)
  local la, da = todo_rank(a)
  local lb, db = todo_rank(b)
  if da and not db then
    return -1
  elseif db and not da then
    return 1
  end
  return cmp_num(la, lb)
end

local function alpha_cmp(a, b)
  local ta, tb = lower_title(a), lower_title(b)
  if not ta and not tb then
    return nil
  elseif not ta then
    return 1
  elseif not tb then
    return -1
  end
  return string_cmp(ta, tb)
end

local function tag_cmp(a, b)
  local ta, tb = first_tag(a), first_tag(b)
  if not ta and not tb then
    return nil
  elseif not ta then
    return 1
  elseif not tb then
    return -1
  end
  if config.opts.tags_sort_function then
    -- org-cmp-tag compares with org-tags-sort
    local tags = require("org.tags")
    if tags.sort_less(ta, tb) then
      return -1
    elseif tags.sort_less(tb, ta) then
      return 1
    end
    return nil
  end
  return string_cmp(ta:lower(), tb:lower())
end

local function habit_cmp(a, b)
  if a.habit and not b.habit then
    return -1
  elseif b.habit and not a.habit then
    return 1
  end
end

local function user_cmp(a, b)
  local f = config.opts.agenda.cmp_user_defined
  if type(f) ~= "function" then
    error("Please set `agenda.cmp_user_defined' to a function or remove `user-defined-up/down' from the sorting")
  end
  local r = f(a, b)
  if r == true then
    return -1
  elseif r == false then
    return nil
  end
  return r
end

--- Comparators returning -1 (a first), 1 (b first) or nil (undecided).
local strategies = {
  ["timestamp-up"] = function(a, b)
    return cmp_num(ts_value(a, ""), ts_value(b, ""))
  end,
  ["timestamp-down"] = function(a, b)
    return cmp_num(ts_value(b, ""), ts_value(a, ""))
  end,
  ["scheduled-up"] = function(a, b)
    return cmp_num(ts_value(a, "scheduled"), ts_value(b, "scheduled"))
  end,
  ["scheduled-down"] = function(a, b)
    return cmp_num(ts_value(b, "scheduled"), ts_value(a, "scheduled"))
  end,
  ["deadline-up"] = function(a, b)
    return cmp_num(ts_value(a, "deadline"), ts_value(b, "deadline"))
  end,
  ["deadline-down"] = function(a, b)
    return cmp_num(ts_value(b, "deadline"), ts_value(a, "deadline"))
  end,
  ["tsia-up"] = function(a, b)
    return cmp_num(ts_value(a, "timestamp_ia"), ts_value(b, "timestamp_ia"))
  end,
  ["tsia-down"] = function(a, b)
    return cmp_num(ts_value(b, "timestamp_ia"), ts_value(a, "timestamp_ia"))
  end,
  ["ts-up"] = function(a, b)
    return cmp_num(ts_value(a, "timestamp"), ts_value(b, "timestamp"))
  end,
  ["ts-down"] = function(a, b)
    return cmp_num(ts_value(b, "timestamp"), ts_value(a, "timestamp"))
  end,
  ["time-up"] = function(a, b)
    return cmp_num(time_value(a), time_value(b))
  end,
  ["time-down"] = function(a, b)
    return cmp_num(time_value(b), time_value(a))
  end,
  ["stats-up"] = function(a, b)
    return cmp_num(stats(a), stats(b))
  end,
  ["stats-down"] = function(a, b)
    return cmp_num(stats(b), stats(a))
  end,
  ["priority-up"] = function(a, b)
    return cmp_num(a.prio or 0, b.prio or 0)
  end,
  ["priority-down"] = function(a, b)
    return cmp_num(b.prio or 0, a.prio or 0)
  end,
  ["urgency-up"] = function(a, b)
    return cmp_num(a.urgency or 0, b.urgency or 0)
  end,
  ["urgency-down"] = function(a, b)
    return cmp_num(b.urgency or 0, a.urgency or 0)
  end,
  ["effort-up"] = function(a, b)
    return cmp_num(effort_value(a), effort_value(b))
  end,
  ["effort-down"] = function(a, b)
    return cmp_num(effort_value(b), effort_value(a))
  end,
  ["category-up"] = function(a, b)
    return string_cmp(cat(a), cat(b))
  end,
  ["category-down"] = function(a, b)
    return string_cmp(cat(b), cat(a))
  end,
  ["category-keep"] = function(a, b)
    return string_cmp(cat(a), cat(b)) and 1 or nil
  end,
  ["tag-up"] = tag_cmp,
  ["tag-down"] = function(a, b)
    return tag_cmp(b, a)
  end,
  ["todo-state-up"] = todo_cmp,
  ["todo-state-down"] = function(a, b)
    return todo_cmp(b, a)
  end,
  ["habit-up"] = habit_cmp,
  ["habit-down"] = function(a, b)
    return habit_cmp(b, a)
  end,
  ["alpha-up"] = alpha_cmp,
  ["alpha-down"] = function(a, b)
    return alpha_cmp(b, a)
  end,
  ["user-defined-up"] = user_cmp,
  ["user-defined-down"] = function(a, b)
    return user_cmp(b, a)
  end,
}
M.strategies = strategies

local function has_any(strategy, a, b)
  return vim.tbl_contains(strategy, a) or vim.tbl_contains(strategy, b)
end

--- Which timestamp `set_list_timestamp` takes for `strategy`.
---@return string|nil
function M.list_timestamp_kind(strategy)
  for _, k in ipairs({ "scheduled", "deadline", "ts", "tsia", "timestamp" }) do
    if has_any(strategy, k .. "-up", k .. "-down") then
      return k
    end
  end
end

--- The timestamp of a list entry (TODO, tags) used by the ts-* sorting
--- strategies (org-agenda-entry-get-agenda-timestamp). Callers setting it
--- on many items pass `kind` from `list_timestamp_kind(strategy)`.
---@param kind? string|false
function M.set_list_timestamp(item, strategy, kind)
  local hl = item.headline
  if not hl then
    return
  end
  if kind == nil then
    kind = M.list_timestamp_kind(strategy) or false
  end
  local function first(active)
    for _, t in ipairs(hl.timestamps) do
      if (t.date.active ~= false) == active then
        return t.date
      end
    end
    if not active then
      for i = hl.line, hl.body_end do
        for _, m in ipairs(date.parse_all(hl.file.lines[i] or "")) do
          if not m.date.active and i ~= hl.planning_line and not (hl.file.lines[i] or ""):match("^%s*CLOCK:") then
            return m.date
          end
        end
      end
    end
  end
  local ts, typ
  if kind == "scheduled" then
    ts, typ = hl.planning.scheduled, " scheduled"
  elseif kind == "deadline" then
    ts, typ = hl.planning.deadline, " deadline"
  elseif kind == "ts" then
    ts, typ = first(true), " timestamp"
  elseif kind == "tsia" then
    ts, typ = first(false), " timestamp_ia"
  elseif kind == "timestamp" then
    ts = hl.planning.scheduled or hl.planning.deadline or first(true) or first(false)
    typ = ""
  else
    typ = ""
  end
  item.ts_date = ts and ts:days() or nil
  item.ts_type = (item.ts_type or item.type) .. typ
end

--- Check a strategy list, erroring on unknown names like Emacs.
function M.check_strategy(strategy)
  for _, s in ipairs(strategy or {}) do
    if not strategies[s] then
      error(string.format("Invalid value %s in `agenda.sorting'", vim.inspect(s)), 0)
    end
  end
end

--- org-entries-lessp
local function lessp(a, b, strategy)
  for _, s in ipairs(strategy) do
    local r = strategies[s](a, b)
    if r == -1 then
      return true
    elseif r == 1 then
      return false
    end
  end
  return false
end
M.lessp = lessp

--- Stable merge sort (like Emacs `sort` on lists).
local function merge_sort(list, less)
  local n = #list
  if n < 2 then
    return list
  end
  local tmp = {}
  local width = 1
  while width < n do
    local i = 1
    while i <= n do
      local mid = math.min(i + width, n + 1)
      local hi = math.min(i + 2 * width, n + 1)
      local l, r, k = i, mid, i
      while l < mid and r < hi do
        if less(list[r], list[l]) then
          tmp[k] = list[r]
          r = r + 1
        else
          tmp[k] = list[l]
          l = l + 1
        end
        k = k + 1
      end
      while l < mid do
        tmp[k] = list[l]
        l, k = l + 1, k + 1
      end
      while r < hi do
        tmp[k] = list[r]
        r, k = r + 1, k + 1
      end
      i = i + 2 * width
    end
    for j = 1, n do
      list[j] = tmp[j]
    end
    width = width * 2
  end
  return list
end

--- Sort items in place according to a strategy list (org-entries-lessp).
--- Unknown strategies raise an error.
---@param items org.AgendaItem[]
---@param strategy string[]
function M.sort(items, strategy)
  strategy = strategy or {}
  M.check_strategy(strategy)
  cmp_memo = {}
  local ok, res = pcall(merge_sort, items, function(a, b)
    return lessp(a, b, strategy)
  end)
  cmp_memo = nil
  if not ok then
    error(res, 0)
  end
  return res
end
