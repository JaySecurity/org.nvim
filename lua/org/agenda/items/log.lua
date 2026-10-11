---@mod org.agenda.items.log Log mode lines in the day agenda
---
--- The closed, clocked and state change lines of an entry in log mode
--- (org-agenda-get-progress). Part of org.agenda.items, which loads it.

-- Not compiled by the JIT, like org.agenda.items (see the comment there).
if jit then
  jit.off(true, true)
end

local date = require("org.date")
local shared = require("org.agenda.items.shared")

local new_item = shared.new_item
local set_time = shared.set_time

--- The log mode lines of `hl` (org-agenda-get-progress), with
--- `opts.log_mode`: closed, clock and state items as `log_items` and
--- `agenda.log_mode_items` select.
---@param ctx org.agenda.items.DayContext
---@param hl org.Headline
function shared.log_entries(ctx, hl)
  local acfg, add, opts, log_items = ctx.acfg, ctx.add, ctx.opts, ctx.log_items
  if opts.log_mode then
    local all = opts.log_mode == "all"
    local no_hl_time = vim.tbl_extend("force", acfg, { search_headline_for_time = false })
    local closed = hl.planning.closed
    if (log_items.closed or all) and closed then
      local item = new_item(hl, {
        type = "closed",
        ts_type = "closed",
        date = closed,
        extra = "Closed:    ",
        face = "OrgAgendaDone",
        log = true,
        urgency = 100000,
        prio = 100000,
      })
      set_time(item, closed, no_hl_time)
      add(closed:days(), item)
    end
    if log_items.clock or all then
      for _, c in ipairs(hl.clocks) do
        local title = hl.title
        -- a clock-out note right below the CLOCK line (org-agenda-log-mode-add-notes)
        local note = acfg.log_mode_add_notes ~= false
          and (hl.file.lines[c.line + 1] or ""):match("^%s*%-%s+([^%-%s].-)%s*$")
        if note then
          title = title .. " - " .. note
        end
        local stamp = c.start
        if c["end"] and c["end"].hour then
          stamp = c.start:clone({ end_hour = c["end"].hour, end_min = c["end"].min })
        end
        local item = new_item(hl, {
          type = "clock",
          ts_type = "clock",
          date = c.start,
          extra = string.format("Clocked:   (%s)", c.minutes and date.format_duration(c.minutes) or "-"),
          face = "OrgAgendaLog",
          log = true,
          clock_line = c.line,
          clock = { start = c.start:minutes(), stop = c["end"] and c["end"]:minutes() or nil },
          title = title,
          urgency = 100000,
          prio = 100000,
        })
        set_time(item, stamp, no_hl_time)
        item.display_title = nil
        add(c.start:days(), item)
      end
    end
    if log_items.state or all then
      for i = hl.line + 1, hl.body_end do
        local line = hl.file.lines[i]
        local kw, ts = line:match('^%s*%-%s+State%s+"([^"]+)".-(%[%d%d%d%d%-%d%d%-%d%d[^%]]*%])')
        local d = kw and date.parse(ts)
        if d then
          local item = new_item(hl, {
            type = "state",
            ts_type = "state",
            date = d,
            extra = string.format("State:     (%s)", kw),
            face = "OrgAgendaLog",
            log = true,
            urgency = 100000,
            prio = 100000,
          })
          set_time(item, d, no_hl_time)
          add(d:days(), item)
        end
      end
    end
  end
end
