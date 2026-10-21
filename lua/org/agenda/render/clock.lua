---@mod org.agenda.render.clock Clock checks and the clock report
---
--- The clocking issues of log mode's clock check
--- (org-agenda-show-clocking-issues) and the clock report
--- (org-agenda-clockreport-mode). Part of org.agenda.render, which loads
--- it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

--- Minutes of an org-duration value ("10:00", 30, "1d 2:00").
local function duration_minutes(v)
  if type(v) == "number" then
    return v
  end
  return v and date.parse_duration(tostring(v)) or nil
end

--- Convert agenda clock bounds (civil minutes) to Unix minutes.
local function clock_time(minutes)
  return date.from_days(math.floor(minutes / 1440)):add(minutes % 1440, "min"):to_time() / 60
end

--- Does the gap [t1, t2] (Unix minutes) contain one of the `ok` times of day?
--- (org-agenda-check-clock-gap)
local function gap_ok(t1, t2, ok)
  if not ok or #ok == 0 then
    return false
  end
  -- Emacs compares (t / 36000) seconds here, so "more than 24" is 10 days
  if (t2 - t1) / 600 > 24 then
    return true
  end
  local d1, d2 = date.from_time(t1 * 60, true), date.from_time(t2 * 60, true)
  local min1, min2 = d1.hour * 60 + d1.min, d2.hour * 60 + d2.min
  if min2 < min1 then
    min2 = min2 + 1440
  end
  for _, x in ipairs(ok) do
    x = duration_minutes(x) or 0
    if x < min1 then
      x = x + 1440
    end
    if min1 <= x and x <= min2 then
      return true
    end
  end
  return false
end

--- The clocking issue of a clock item for the clock check
--- (org-agenda-show-clocking-issues), or nil. `state.tlend` carries the
--- end of the previous clock across the agenda.
local function clock_issue(it, state)
  local checks = config.opts.agenda.clock_consistency_checks or {}
  local c = it.clock
  local start = clock_time(c.start)
  if not c.stop then
    return string.format("No end time: (%s)", date.duration_to_string(date.now():to_time() / 60 - start))
  end
  local maxtime = duration_minutes(checks.max_duration or "24:00") or 1440
  local mintime = duration_minutes(checks.min_duration or 0) or 0
  local maxgap = duration_minutes(checks.max_gap or "30:00") or 1800
  local stop = clock_time(c.stop)
  local dt = stop - start
  local tlend = state.tlend or 0
  local issue
  if dt > maxtime then
    issue = "Clocking interval is very long: " .. date.duration_to_string(dt)
  elseif dt < mintime then
    issue = "Clocking interval is very short: " .. date.duration_to_string(dt)
  elseif tlend > 0 and start < tlend then
    issue = string.format("Clocking overlap: %d minutes", tlend - start)
  elseif tlend > 0 and start > tlend + maxgap and not gap_ok(tlend, start, checks.gap_ok_around) then
    issue = string.format("Clocking gap: %d minutes", start - tlend)
  end
  state.tlend = stop
  return issue
end

--- Clock table for the span (org-agenda-clockreport-mode): a clocktable
--- over the agenda files with `agenda.clockreport_parameters`, from the
--- first day of the span to the end of the last.
function M.clock_report(b, files, from, to)
  local acfg = config.opts.agenda
  local params = vim.deepcopy(acfg.clockreport_parameters or { link = true, maxlevel = 2 })
  params.block, params.step = nil, nil
  params.scope = files
  params.tstart = "[" .. date.from_days(from):to_date_string() .. "]"
  params.tend = "[" .. date.from_days(to + 1):to_date_string() .. "]"
  params.header = ""
  local ok, lines = pcall(require("org.clock").clocktable, params, vim.api.nvim_get_current_buf())
  if acfg.clock_report_header then
    for _, l in ipairs(vim.split(acfg.clock_report_header, "\n", { plain = true, trimempty = true })) do
      b:text(l, "OrgAgendaHeader")
    end
  end
  if not ok then
    b:text("Clock report: " .. tostring(lines), "ErrorMsg")
    return
  end
  for _, l in ipairs(lines) do
    b:add_line(M.clock_report_line(l))
  end
end

--- A clock report line as the agenda shows it (org-clock-get-clocktable
--- returns the table fontified as in an Org buffer): bracket links reduced
--- to their description, the table in OrgTable, its rules and bars in
--- OrgTableSeparator, links in OrgLink and `*bold*` in OrgBold.
---@param l string
---@return string text, table[] hls
function M.clock_report_line(l)
  local found = require("org.links").parse_links(l, { bracket_only = true })
  local out, hls, init = {}, {}, 1
  local len = 0
  local function put(s, group)
    if group and #s > 0 then
      hls[#hls + 1] = { len, len + #s, group }
    end
    out[#out + 1] = s
    len = len + #s
  end
  for _, lk in ipairs(found) do
    put(l:sub(init, lk.start_col - 1))
    put(lk.desc or lk.raw_target, "OrgLink")
    init = lk.end_col + 1
  end
  put(l:sub(init))
  local text = table.concat(out)
  if not text:match("^%s*|") then
    return text, hls
  end
  local table_hls = { { 0, #text, "OrgTable" } }
  if text:match("^%s*|[-+]") then
    table_hls[2] = { 0, #text, "OrgTableSeparator" }
  else
    for col in text:gmatch("()|") do
      table_hls[#table_hls + 1] = { col - 1, col, "OrgTableSeparator" }
    end
  end
  for s, e in text:gmatch("()%*[^%s*][^*]-%*()") do
    local before = s > 1 and text:sub(s - 1, s - 1) or " "
    local after = text:sub(e, e)
    if before:match("[%s|(]") and (after == "" or after:match("[%s|.,;:!?)]")) then
      table_hls[#table_hls + 1] = { s - 1, e - 1, "OrgBold" }
    end
  end
  return text, vim.list_extend(table_hls, hls)
end

shared.clock_issue = clock_issue

return M
