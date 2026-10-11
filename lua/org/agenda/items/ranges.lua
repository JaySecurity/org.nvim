---@mod org.agenda.items.ranges Date ranges as org-tr-regexp reads them
---
--- The date ranges of an entry for org-agenda-get-blocks and
--- org-agenda-get-timestamps, read like Emacs' org-tr-regexp (whose start
--- runs over a `>`), on its planning line too, and the DOTIME strings
--- org-agenda-get-scheduled, -deadlines and -blocks pass. Part of
--- org.agenda.items, which loads it.

-- Not compiled by the JIT, like org.agenda.items (see the comment there).
if jit then
  jit.off(true, true)
end

local date = require("org.date")
local shared = require("org.agenda.items.shared")

--- The timestamp `text` (without its brackets) as Emacs reads the start or
--- the end of an org-tr-regexp match: the date, and the first time of day
--- (or time range) in it for the agenda line, even past a `>` the match
--- ran over.
---@return org.Date|nil
local function tr_stamp(text)
  local whole = date.parse_all("<" .. text .. ">")[1]
  if whole and whole.start_col == 1 and whole.end_col == #text + 2 then
    return whole.date
  end
  local y, m, d = text:match("^(%d+)%-(%d+)%-(%d+)")
  if not y then
    return nil
  end
  local hour, min, rest = text:match("(%d%d?):(%d%d)()", 11)
  local end_hour, end_min
  if rest then
    end_hour, end_min = text:match("^%-(%d%d?):(%d%d)", rest)
  end
  return date.from_days(date.days_from_civil(tonumber(y), tonumber(m), tonumber(d)), {
    active = true,
    hour = tonumber(hour),
    min = tonumber(min),
    end_hour = tonumber(end_hour),
    end_min = tonumber(end_min),
  })
end

--- The active date ranges of `line` as Emacs' org-tr-regexp finds them:
--- `<date .*?>--<date .*?>`, whose start runs over a `>` until one is
--- followed by `--<date`. `mid` is the column of the end's `<`.
---@return { date: org.Date, start_col: integer, end_col: integer, mid: integer }[]
local function tr_ranges(line)
  local out, pos = {}, 1
  -- (a range has a ">-": most planning lines have none, and the pattern
  -- below goes over the line from each date)
  if not line:find(">-", 1, true) then
    return out
  end
  while true do
    local s, e, a, mid, b = line:find("<(%d%d%d%d%-%d%d%-%d%d.-)>%-%-?%-?()<(%d%d%d%d%-%d%d%-%d%d.-)>", pos)
    if not s then
      break
    end
    local start, stop = tr_stamp(a), tr_stamp(b)
    if start and stop and (#a == 10 or a:sub(11, 11) == " ") and (#b == 10 or b:sub(11, 11) == " ") then
      out[#out + 1] = { date = start:clone({ range_end = stop }), start_col = s, end_col = e, mid = mid }
      pos = e + 1
    else
      pos = s + 1
    end
  end
  return out
end

--- Does an org-tr-regexp-both match start at column `p` of `line`
--- (`<date .*?>--<date .*?>`, either bracket)?
local function tr_at(line, p)
  if not line:find("^[<%[]%d%d%d%d%-%d%d%-%d%d[ >%]]", p) then
    return false
  end
  local spaced = line:sub(p + 11, p + 11) == " "
  local init = p + 11
  while true do
    local s, e = line:find("[>%]]%-%-?%-?[<%[]%d%d%d%d%-%d%d%-%d%d", init)
    if not s then
      return false
    end
    if s == p + 11 or spaced then
      local nxt = line:sub(e + 1, e + 1)
      if nxt == ">" or nxt == "]" or (nxt == " " and line:find("[>%]]", e + 2)) then
        return true
      end
    end
    init = s + 1
  end
end

--- org-at-date-range-p with INACTIVE-OK, for the timestamp at column
--- `col`: a date range starts at it or at the `<` or `[` before it on the
--- line ("<a> x <b>--<c>" is one range for Emacs, from a to c). Such a
--- timestamp is no plain timestamp entry (org-agenda-get-timestamps).
local function at_date_range(line, col)
  if tr_at(line, col) then
    return true
  end
  local q = line:sub(1, col - 1):match(".*()[<%[]")
  return q ~= nil and tr_at(line, q)
end

--- The DOTIME org-agenda-get-scheduled and org-agenda-get-deadlines pass
--- for the SCHEDULED or DEADLINE (`key`) of `hl`: its value from the first
--- " H:MM" on, or false when it has none (the headline is searched); nil
--- when the planning line can't be read.
local function planning_dotime(hl, key)
  local line = hl.planning_line and hl.file.lines[hl.planning_line]
  local p = line and line:find(key .. ":", 1, true)
  local first = p and date.parse_all(line:sub(p + #key + 1))[1]
  if not first then
    return nil
  end
  local inner = first.raw:sub(2, -2)
  local t = inner:find(" [012]?%d:%d%d")
  return t and (inner:sub(t + 1) .. " ") or false
end

--- org-agenda-get-blocks' DOTIME on a day of the range written `raw` (from
--- the `<` org-tr-regexp starts at): "<a>--<b>" when the range starts and
--- ends that day (`which` "both"), "<a>" on its first day ("start"), "<b>"
--- on its last ("end"), with a and b as org-tr-regexp matches them (a runs
--- to the first `>--<date`), in angle brackets even when inactive.
local function range_dotime(raw, which)
  local s, e = raw:find("[>%]]%-%-?%-?[<%[]%d%d%d%d%-%d%d%-%d%d")
  if not s then
    return nil
  end
  local a = raw:sub(2, s - 1)
  local b = raw:sub(e - 9):match("^(.-)[>%]]") or raw:sub(e - 9)
  if which == "both" then
    return "<" .. a .. ">--<" .. b .. ">"
  end
  return "<" .. (which == "start" and a or b) .. ">"
end

-- Timestamps in buffer order.
local function by_position(a, b)
  if a.line ~= b.line then
    return a.line < b.line
  end
  return (a.start_col or 0) < (b.start_col or 0)
end

--- The active timestamps of an entry for org-agenda-get-timestamps and
--- org-agenda-get-blocks, in buffer order: its plain ones (`index` into
--- `hl.timestamps`), the date ranges that are no timestamp objects
--- (`hl.block_ranges`: in a comment or example block, ...), and the date
--- ranges on its planning line (`planning` the SCHEDULED or DEADLINE they
--- belong to), which Emacs' org-tr-regexp matches like any other range.
---
--- The start of org-tr-regexp (`<date .*?>`) runs over a `>`, so a range
--- starts at the first `<YYYY-MM-DD` before it on its line (after the
--- range before it): in "SCHEDULED: <a> DEADLINE: <b>--<c>", the block
--- goes from a to c, and there is none when a is after c.
local function block_sources(hl)
  local out = {}
  for i, t in ipairs(hl.timestamps) do
    out[#out + 1] = { date = t.date, line = t.line, start_col = t.start_col, end_col = t.end_col, index = i }
  end
  for _, t in ipairs(hl.block_ranges or {}) do
    out[#out + 1] = { date = t.date, line = t.line, start_col = t.start_col, end_col = t.end_col }
  end
  local pline = hl.planning_line and hl.file.lines[hl.planning_line]
  if pline then
    for _, r in ipairs(tr_ranges(pline)) do
      -- the SCHEDULED or DEADLINE the range's end follows
      local before = pline:sub(1, r.mid - 1)
      local key
      for k in before:gmatch("(%u+):%s*<") do
        key = k
      end
      local kind = key == "SCHEDULED" and "scheduled" or key == "DEADLINE" and "deadline" or nil
      if kind then
        r.line, r.planning = hl.planning_line, kind
        out[#out + 1] = r
      end
    end
  end
  -- ranges org-tr-regexp finds in the text where the timestamps parse
  -- as two ("<a 06:00> x>--<b>"), as on the planning line
  local seen_line = {}
  for _, ts in ipairs(hl.timestamps) do
    local text = not seen_line[ts.line] and hl.file.lines[ts.line]
    seen_line[ts.line] = true
    if text and text:find(">-", 1, true) then
      for _, r in ipairs(tr_ranges(text)) do
        local covered = false
        for _, o in ipairs(out) do
          if o.line == ts.line and o.date.range_end and o.start_col and o.start_col < r.mid and o.end_col >= r.mid then
            covered = true
            break
          end
        end
        if not covered then
          r.line = ts.line
          out[#out + 1] = r
        end
      end
    end
  end
  table.sort(out, by_position)
  local floor = {}
  for _, t in ipairs(out) do
    local text = t.start_col and t.date.range_end and hl.file.lines[t.line]
    if text then
      local s = text:find("<%d%d%d%d%-%d%d%-%d%d", floor[t.line] or 1)
      if s and s < t.start_col then
        local first = date.parse_all(text:sub(s, t.start_col - 1))[1]
        local start = first and first.start_col == 1 and first.date
        if not start then
          local y, m, d = text:match("^<(%d+)%-(%d+)%-(%d+)", s)
          start = date.from_days(date.days_from_civil(tonumber(y), tonumber(m), tonumber(d)))
        end
        t.date = start:clone({ range_end = t.date.range_end })
        t.raw_col = s
      end
      floor[t.line] = (t.end_col or t.start_col) + 1
    end
  end
  return out
end

shared.at_date_range = at_date_range
shared.planning_dotime = planning_dotime
shared.range_dotime = range_dotime
shared.block_sources = block_sources
