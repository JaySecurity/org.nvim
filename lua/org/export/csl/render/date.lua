---@mod org.export.csl.render.date CSL dates
---
--- cs:date and date parts (port of citeproc-date.el): parsing CSL-JSON
--- dates, localized date forms and date ranges.
---
--- Part of org.export.csl.render, which loads it.

local U = require("org.export.csl.util")
local M = require("org.export.csl.render")
local shared = require("org.export.csl.render.shared")

local E = M.elements
local aget, acons = U.aget, U.acons
local nf, typed = shared.nf, M.typed

---------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------

--- citeproc-date-parse: CSL-JSON date to a list of date structs.
function M.date_parse(rep)
  local parts = rep and rep["date-parts"]
  if type(parts) ~= "table" then
    return nil
  end
  local out = {}
  for _, dp in ipairs(parts) do
    local nums = {}
    for i = 1, 3 do
      local x = dp[i]
      if type(x) == "string" then
        x = U.to_number(x)
      end
      nums[i] = x
    end
    out[#out + 1] = { year = nums[1], month = nums[2], day = nums[3], season = rep.season, circa = rep.circa }
  end
  if #out == 0 then
    return nil
  end
  return out
end

local function partattrs_for_sort(part_attrs)
  local has = {}
  for _, p in ipairs(part_attrs) do
    has[p[1]] = true
  end
  local out = {}
  if has.year then
    out[#out + 1] = { "year", { { "form", "long" } } }
  end
  if has.month then
    out[#out + 1] = { "month", { { "form", "numeric-leading-zeros" } } }
  end
  if has.day then
    out[#out + 1] = { "day", { { "form", "numeric-leading-zeros" } } }
  end
  return out
end

local function renders_with_attrs_p(date, part_attrs)
  local parts = {}
  for _, p in ipairs(part_attrs) do
    parts[p[1]] = true
  end
  return parts.year or (parts.month and date.month) or (parts.day and date.day)
end

local function localized_attrs(attrs, part_attrs, ctx)
  local form = aget(attrs, "form")
  local date_parts = aget(attrs, "date-parts")
  local loc = form == "text" and ctx.date_text or ctx.date_numeric
  local loc_attrs = loc and loc.attrs or {}
  local loc_parts = loc and loc.parts or {}
  if date_parts == "year" then
    loc_parts = U.afilter(loc_parts, function(p)
      return p[1] == "year"
    end)
  elseif date_parts == "year-month" then
    loc_parts = U.afilter(loc_parts, function(p)
      return p[1] == "year" or p[1] == "month"
    end)
  end
  local parts = {}
  for _, p in ipairs(loc_parts) do
    parts[#parts + 1] = { p[1], U.concat(aget(part_attrs, p[1]), p[2]) }
  end
  return U.concat(attrs, loc_attrs), parts
end

local function render_year(d, attrs, ctx)
  local form = aget(attrs, "form")
  local year = d.year or 0
  local s = U.num_str(math.abs(year))
  local era
  if year > 999 then
    era = ""
  elseif year > 0 then
    era = M.term_get_text("ad", ctx) or ""
  else
    era = M.term_get_text("bc", ctx) or ""
  end
  if form == "short" then
    s = U.substring(s, math.max(0, U.len(s) - 2))
  end
  return M.format_single(attrs, s .. era, ctx)
end

local function render_month(d, attrs, ctx)
  local month = d.month
  if not month then
    return nil
  end
  local form = aget(attrs, "form")
  local pref = d.season and "season-" or "month-"
  local text
  if form == "numeric" then
    text = U.num_str(month)
  elseif form == "numeric-leading-zeros" then
    text = string.format("%02d", month)
  elseif form == "short" then
    text = M.term_inflected_text(pref .. string.format("%02d", month), "short", nil, ctx)
  else
    text = M.term_inflected_text(pref .. string.format("%02d", month), "long", nil, ctx)
  end
  return M.format_single(attrs, text, ctx)
end

local function render_day(d, attrs, ctx)
  local day = d.day
  if not day then
    return nil
  end
  local form = aget(attrs, "form")
  local text
  if form == "numeric-leading-zeros" then
    text = string.format("%02d", day)
  elseif form == "ordinal" and (day == 1 or aget(ctx.locale_opts, "limit-day-ordinals-to-day-1") ~= "true") then
    text = shared.format_as_ordinal(U.num_str(day), "month-" .. string.format("%02d", d.month or 0), ctx)
  else
    text = U.num_str(day)
  end
  return M.format_single(attrs, text, ctx)
end

local function render_parts(d, part_attrs, ctx, no_last_suffix)
  local result = { n = 0 }
  for _, p in ipairs(part_attrs) do
    local v
    if p[1] == "year" then
      v = render_year(d, p[2], ctx)
    elseif p[1] == "month" then
      v = render_month(d, p[2], ctx)
    elseif p[1] == "day" then
      v = render_day(d, p[2], ctx)
    end
    result.n = result.n + 1
    result[result.n] = nf(v)
  end
  if no_last_suffix and result.n > 0 then
    local last = result[result.n]
    if type(last) == "table" then
      local n = { U.aremove(last[1], "suffix") }
      for i = 2, #last do
        n[i] = last[i]
      end
      result[result.n] = n
    end
  end
  return result
end

local function render_date(d, attrs, part_attrs, ctx)
  if M.var_value("suppress-date", ctx) then
    return M.format_single(attrs, "<suppressed-date>", ctx)
  end
  return M.join_formatted(attrs, render_parts(d, part_attrs, ctx), ctx)
end

local function date_gran(d)
  if d.day then
    return 2
  elseif d.month then
    return 1
  end
  return 0
end

local function attrs_gran(part_attrs)
  if U.assoc(part_attrs, "day") then
    return 2
  elseif U.assoc(part_attrs, "month") then
    return 1
  end
  return 0
end

local function render_range_parts(d1, d2, part_attrs, sep, ctx)
  local out = { n = 0 }
  local function add(v)
    out.n = out.n + 1
    out[out.n] = nf(v)
  end
  for _, it in ipairs(part_attrs) do
    if it.group then
      local a = render_parts(d1, it, ctx, true)
      for i = 1, a.n do
        add(a[i])
      end
      add(sep)
      local b = render_parts(d2, it, ctx)
      for i = 1, b.n do
        add(b[i])
      end
    elseif it[1] == "year" then
      add(render_year(d1, it[2], ctx))
    elseif it[1] == "month" then
      add(render_month(d1, it[2], ctx))
    elseif it[1] == "day" then
      add(render_day(d1, it[2], ctx))
    end
  end
  return out
end

local function group_of(list)
  local g = { group = true }
  for _, x in ipairs(list) do
    g[#g + 1] = x
  end
  return g
end

local function render_range(d1, d2, attrs, part_attrs, ctx)
  if M.var_value("suppress-date", ctx) then
    return M.format_single(attrs, "", ctx)
  end
  local gran = math.min(date_gran(d1), attrs_gran(part_attrs))
  local unit = ({ "year", "month", "day" })[gran + 1]
  local sep = aget(aget(part_attrs, unit), "range-delimiter") or "–"
  local groups
  if d1.year ~= d2.year then
    groups = { group_of(part_attrs) }
  elseif d1.month ~= d2.month then
    local year_part = U.assoc(part_attrs, "year")
    local wo_year = U.aremove(part_attrs, "year")
    if part_attrs[1] and part_attrs[1][1] == "year" then
      groups = { year_part, group_of(wo_year) }
    elseif part_attrs[#part_attrs] and part_attrs[#part_attrs][1] == "year" then
      groups = { group_of(wo_year), year_part }
    else
      groups = { group_of(wo_year) }
    end
  else
    groups = {}
    for _, it in ipairs(part_attrs) do
      if it[1] == "day" then
        groups[#groups + 1] = group_of({ it })
      else
        groups[#groups + 1] = it
      end
    end
  end
  return M.join_formatted(attrs, render_range_parts(d1, d2, groups, sep, ctx), ctx)
end

function E.date(attrs, ctx, body)
  local var = aget(attrs, "variable")
  local form = aget(attrs, "form")
  local dates = M.var_value(var, ctx)
  local d1 = type(dates) == "table" and dates[1] or nil
  local d2 = type(dates) == "table" and dates[2] or nil
  local parts = {}
  for i = 1, body.n or #body do
    if type(body[i]) == "table" then
      parts[#parts + 1] = body[i]
    end
  end
  local result
  if d1 then
    if form then
      attrs, parts = localized_attrs(attrs, parts, ctx)
    end
    if ctx.render_mode == "sort" then
      parts = partattrs_for_sort(parts)
    end
    if renders_with_attrs_p(d1, parts) then
      attrs = acons("rendered-var", var, attrs)
      if d2 then
        result = typed(render_range(d1, d2, attrs, parts, ctx), "present-var")
      else
        result = typed(render_date(d1, attrs, parts, ctx), "present-var")
      end
    else
      result = typed(nil, "empty-vars")
    end
  else
    result = typed(nil, "empty-vars")
  end
  return M.maybe_stop_rendering("issued", ctx, result, var)
end

E["date-part"] = function(attrs)
  return { aget(attrs, "name"), attrs }
end

return M
