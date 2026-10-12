---@mod org.export.csl.render.sort CSL sort keys
---
--- cs:key and cs:sort (the sort-key part of citeproc-sort.el).
---
--- Part of org.export.csl.render, which loads it.

local U = require("org.export.csl.util")
local rt = require("org.export.csl.rt")
local M = require("org.export.csl.render")
local shared = require("org.export.csl.render.shared")

local E = M.elements
local aget = U.aget

---------------------------------------------------------------------------
-- Sort keys
---------------------------------------------------------------------------

local function fill_left(s, len)
  s = s or ""
  local l = U.len(s)
  if l >= len then
    return s
  end
  return string.rep("0", len - l) .. s
end

local function date_as_key(d)
  if not d then
    return ""
  end
  return U.num_str(5000 + (d.year or 0)) .. fill_left(U.num_str(d.month or 0), 2) .. fill_left(U.num_str(d.day or 0), 2)
end

local function name_var_key(var, ctx)
  return rt.to_plain(rt.render_affixes(M.name_render_var(var, {
    { "form", "long" },
    { "name-as-sort-order", "all" },
    { "et-al-min", nil },
    { "et-al-use-first", "0" },
    { "delimiter", "; " },
  }, nil, nil, false, false, nil, ctx)))
end

function E.key(attrs, ctx)
  local macro = aget(attrs, "macro")
  local var = aget(attrs, "variable")
  local global = U.afilter(attrs, function(p)
    return p[1] == "names-min" or p[1] == "names-use-first" or p[1] == "names-use-last"
  end)
  if var then
    if rt.NUMBER_VAR_SET[var] then
      return fill_left(M.number_var_value(M.var_value(var, ctx), var, "numeric", ctx), 5)
    elseif rt.DATE_VAR_SET[var] then
      local dates = M.var_value(var, ctx) or {}
      local key = date_as_key(dates[1])
      if dates[2] then
        key = key .. "–" .. date_as_key(dates[2])
      end
      return key
    elseif rt.NAME_VAR_SET[var] then
      return name_var_key(var, ctx)
    end
    return rt.to_plain(M.var_value(var, ctx))
  end
  local new_ctx = {
    vars = ctx.vars,
    macros = ctx.macros,
    terms = ctx.terms,
    date_text = ctx.date_text,
    date_numeric = ctx.date_numeric,
    opts = U.concat(global, ctx.opts),
    mode = ctx.mode,
    render_mode = "sort",
    render_year_suffix = nil,
  }
  return M.macro_output_as_text(macro, new_ctx)
end

function E.sort(_, _, body)
  local out = {}
  for i = 1, body.n or #body do
    out[i] = body[i]
  end
  return out
end

--- citeproc-sort--compare-keys
function M.compare_keys(k1, k2, desc)
  if k1 == k2 then
    return 0
  elseif U.blank(k1) then
    return -1
  elseif U.blank(k2) then
    return 1
  end
  return (k1 < k2 and 1 or -1) * (desc and -1 or 1)
end

--- citeproc-lib-lex-compare with citeproc-sort--compare-keys
function M.compare_keylists(l1, l2, orders)
  local result
  local i = 1
  local has_orders = orders ~= nil and #orders > 0
  while i <= #(l1 or {}) and not result do
    local desc = has_orders and not orders[i] or false
    local c = M.compare_keys(l1[i], l2 and l2[i], desc)
    if c ~= 0 then
      result = c
    end
    i = i + 1
  end
  return result == 1
end

--- citeproc-sort--render-keys
function M.render_keys(style, vars, mode)
  local ctx = M.context_create(vars, style, mode, "sort")
  local sort = mode == "cite" and style.cite_sort or style.bib_sort
  if sort then
    return sort(ctx)
  end
  return nil
end

return M
