---@mod org.agenda.render.limits Agenda limits
---
--- org-agenda-max-entries, -todos, -tags and -effort over a sorted list
--- (org-agenda-limit-entries). Part of org.agenda.render, which loads
--- it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local items_mod = require("org.agenda.items")

local M = require("org.agenda.render")

local function limit_value(v, kind)
  if type(v) == "number" then
    return v
  elseif type(v) == "table" then
    return v[kind]
  end
  return nil
end

--- org-agenda-limit-entries
local function limit_entries(list, prop, limit, fn)
  if not limit then
    return list
  end
  fn = fn or function(p)
    return p and 1 or nil
  end
  local include = limit < 0
  local lim = 0
  local out = {}
  for _, e in ipairs(list) do
    local pval = fn(prop(e))
    if pval then
      lim = lim + pval
    end
    if (pval and lim <= math.abs(limit)) or (include and not pval) then
      out[#out + 1] = e
    end
  end
  return out
end

--- Apply the max_* limits of a view type to a sorted list.
function M.apply_limits(list, kind, ctx)
  local acfg = config.opts.agenda
  local limits = (ctx and ctx.limits) or {}
  local function get(name)
    local v = limits[name]
    if v == nil then
      v = acfg[name]
    end
    return limit_value(v, kind)
  end
  local max_effort = get("max_effort")
  if max_effort then
    list = limit_entries(
      list,
      function(e)
        return e.grid and nil or items_mod.effort(e)
      end,
      max_effort,
      function(e)
        return e or (acfg.sort_noeffort_is_high ~= false and math.huge or -1)
      end
    )
  end
  local max_todos = get("max_todos")
  if max_todos then
    list = limit_entries(list, function(e)
      return e.todo
    end, max_todos)
  end
  local max_tags = get("max_tags")
  if max_tags then
    list = limit_entries(list, function(e)
      return e.tags and #e.tags > 0 and e.tags or nil
    end, max_tags)
  end
  local max_entries = get("max_entries")
  if max_entries then
    list = limit_entries(list, function(e)
      -- a %%(sexp) line before the first heading counts too
      return e.headline or e.lnum_sexp
    end, max_entries)
  end
  return list
end

return M
