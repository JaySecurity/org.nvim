---@mod org.extensions.cli.clock The clock commands
---
--- `org clock` status (with `--format`), in, out and cancel, and the
--- running clock as data. Part of org.extensions.cli.run, which loads it.

local data = require("org.extensions.cli.data")

local shared = require("org.extensions.cli.shared")

local M = require("org.extensions.cli.run")

local fail = M.fail
local state = shared.state
local cli_opts = shared.cli_opts
local short_path = M.short_path
local touch_stamp = shared.touch_stamp

--- The running clock as data, or nil.
function M.clock_data()
  local clock = require("org.clock")
  local date = require("org.date")
  local st = clock.restore()
  if not st then
    return nil
  end
  local start = date.parse(st.start) or date.parse("[" .. tostring(st.start) .. "]")
  local minutes = start and date.elapsed_minutes(start, date.now()) or 0
  local title = st.title or ""
  local line, id = vim.NIL, vim.NIL
  local ok, bufnr, lnum = pcall(clock.find_open_clock)
  if ok and bufnr and lnum then
    local hl = M.headline_at(bufnr, lnum)
    if hl then
      line, id = hl.line, data.nn(hl.properties.ID)
    end
  end
  return {
    active = true,
    title = title,
    file = data.path(st.path),
    line = line,
    id = id,
    start = st.start,
    start_iso = start and data.iso(start) or vim.NIL,
    minutes = minutes,
    elapsed = date.duration_to_string(minutes),
    total = (st.total or 0) + minutes,
    effort = data.nn(st.effort),
  }
end

local NO_CLOCK = {
  active = false,
  title = vim.NIL,
  file = vim.NIL,
  line = vim.NIL,
  id = vim.NIL,
  start = vim.NIL,
  start_iso = vim.NIL,
  minutes = vim.NIL,
  elapsed = vim.NIL,
  total = vim.NIL,
  effort = vim.NIL,
}

--- Expand a `--format` string: %t title, %e elapsed, %T total (with past
--- clocks), %E effort, %f file, %s start, %% a percent sign.
function M.format_clock(fmt, c)
  local date = require("org.date")
  local effort = c.effort ~= vim.NIL and c.effort or nil
  local map = {
    t = c.title,
    e = c.elapsed,
    T = date.duration_to_string(c.total or c.minutes),
    E = effort and date.duration_to_string(effort) or "",
    f = c.file ~= vim.NIL and short_path(c.file) or "",
    s = c.start or "",
    ["%"] = "%",
  }
  return (fmt:gsub("%%(.)", function(k)
    return map[k] or ("%" .. k)
  end))
end

function M.cmd_clock_status(_, flags)
  local c = M.clock_data()
  local text
  if flags.format or flags.short then
    text = c and { M.format_clock(flags.format or cli_opts().status_format, c) } or {}
  elseif c then
    text = { string.format("%s  %s  (%s)", c.elapsed, c.title, short_path(c.file)) }
  else
    text = { "No running clock" }
  end
  return { data = c or NO_CLOCK, text = text }
end

function M.cmd_clock_in(words, flags)
  local clock = require("org.clock")
  local query = table.concat(words, " ")
  if query == "" then
    fail("clock in needs a heading: org clock in TARGET", "usage")
  end
  local hl = M.resolve_target(query, flags)
  -- clocking in clocks out of the running clock, in its file: that file
  -- is checked too before anything changes
  local running = clock.restore()
  if running and running.path and running.path ~= "" then
    M.guard(running.path, flags)
  end
  local bufnr, lnum = M.open_target(hl, flags)
  M.mark_messages()
  local st = clock.clock_in({ bufnr = bufnr, lnum = lnum }, { no_count = true })
  if not st then
    M.fail_with_messages("could not clock in")
  end
  M.save_all(flags)
  touch_stamp()
  return { data = M.clock_data() or NO_CLOCK, text = { "Clocked in: " .. hl:plain_title() } }
end

local function clock_stop(cancel, flags)
  local clock = require("org.clock")
  local c = M.clock_data()
  if not c then
    if state.machine then
      fail("no running clock", "no_clock")
    end
    return { text = { "No running clock" }, code = 1 }
  end
  if c.file ~= vim.NIL then
    M.guard(c.file, flags)
  end
  local minutes
  if cancel then
    clock.clock_cancel()
  else
    minutes = clock.clock_out({ note = false })
  end
  M.save_all(flags)
  touch_stamp()
  local text
  if cancel then
    text = { "Clock canceled: " .. c.title }
  else
    text = { string.format("Clocked out: %s (%s)", c.title, data.duration(minutes)) }
  end
  return {
    data = {
      active = false,
      title = c.title,
      file = c.file,
      minutes = data.nn(minutes),
      duration = minutes and data.duration(minutes) or vim.NIL,
      canceled = cancel,
    },
    text = text,
  }
end

function M.cmd_clock_out(_, flags)
  return clock_stop(false, flags)
end

function M.cmd_clock_cancel(_, flags)
  return clock_stop(true, flags)
end
