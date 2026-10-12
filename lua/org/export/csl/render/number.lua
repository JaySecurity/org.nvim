---@mod org.export.csl.render.number CSL numbers and page ranges
---
--- cs:number, ordinals and roman numerals (port of citeproc-number.el)
--- and page-range formatting (citeproc-prange.el).
---
--- Part of org.export.csl.render, which loads it.

local U = require("org.export.csl.util")
local R = require("org.export.csl.regex")
local M = require("org.export.csl.render")
local shared = require("org.export.csl.render.shared")

local E = M.elements
local aget, acons = U.aget, U.acons
local typed = M.typed

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------

local SEP_ALT = "\\([,&-–—―]\\|--\\)"
local NUM_EXTRACT_RE = "\\`\\([[:alpha:]]?[[:digit:]]+[[:alpha:]]*\\)\\(?:\\(?: *"
  .. SEP_ALT
  .. " *\\)\\([[:alpha:]]?[[:digit:]]+[[:alpha:]]*\\)\\)?\\'"

--- citeproc-number-extract: the groups, or nil
function M.number_extract(val)
  local m = R.match(NUM_EXTRACT_RE, val)
  if not m then
    return nil
  end
  -- trailing unmatched groups are dropped (match-data)
  local out = {}
  local last = 0
  for k = 1, 3 do
    if m[k] ~= nil then
      last = k
    end
  end
  for k = 1, last do
    out[k] = m[k]
  end
  out.n = last
  return out
end

local NUMSEP = { ["&"] = " & ", [","] = ", ", ["-"] = "-", ["--"] = "-", ["—"] = "-", ["―"] = "-" }

local function arabic_to_roman(n)
  local vals = {
    { 1000, "M" },
    { 900, "CM" },
    { 500, "D" },
    { 400, "CD" },
    { 100, "C" },
    { 90, "XC" },
    { 50, "L" },
    { 40, "XL" },
    { 10, "X" },
    { 9, "IX" },
    { 5, "V" },
    { 4, "IV" },
    { 1, "I" },
  }
  local out = {}
  for _, v in ipairs(vals) do
    while n >= v[1] do
      out[#out + 1] = v[2]
      n = n - v[1]
    end
  end
  return table.concat(out)
end

local function tail(s, len)
  local l = U.len(s)
  if len and len < l then
    return U.substring(s, l - len)
  end
  return s
end

local ORD_MATCH = { ["last-two-digits"] = 2, ["last-digit"] = 1 }

local function ordinal_matches_p(s, gender, term)
  if gender ~= term.gender_form then
    return false
  end
  local match = term.match
  local name = term.name
  if not match then
    match = name:sub(9, 9) == "0" and "last-digit" or "last-two-digits"
  end
  local num = tail(name, 2)
  local l = ORD_MATCH[match]
  return tail(s, l) == tail(num, l)
end

local function format_as_ordinal(s, term, ctx)
  local terms = ctx.terms or {}
  local padded = U.len(s) == 1 and ("0" .. s) or s
  local gender = M.term_get_gender(term, ctx)
  local matches = {}
  for _, t in ipairs(terms) do
    if t.name and t.name:sub(1, 8) == "ordinal-" and ordinal_matches_p(padded, gender, t) then
      matches[#matches + 1] = t
    end
  end
  local chosen
  if #matches == 0 then
    local ords = {}
    for _, t in ipairs(terms) do
      if t.name == "ordinal" then
        ords[#ords + 1] = t
      end
    end
    for _, t in ipairs(ords) do
      if t.gender_form == gender then
        chosen = t
        break
      end
    end
    chosen = chosen or ords[1]
  else
    local first, second = matches[1], matches[2]
    if second then
      chosen = first.name:sub(9, 9) == "0" and second or first
    else
      chosen = first
    end
  end
  return s .. (chosen and chosen.text or "")
end
shared.format_as_ordinal = format_as_ordinal

local function format_as_long_ordinal(s, term, ctx)
  local num = U.to_number(s)
  if num > 10 then
    return format_as_ordinal(s, term, ctx)
  end
  if U.len(s) == 1 then
    s = "0" .. s
  end
  local name = "long-ordinal-" .. s
  local gender = M.term_get_gender(term, ctx)
  for _, t in ipairs(ctx.terms or {}) do
    if t.name == name and t.gender_form == gender then
      return t.text
    end
  end
  return M.term_get_text(name, ctx)
end

local function number_format(s, form, term, ctx)
  if R.test("[[:alpha:]]", s) then
    return s
  end
  if form == "roman" then
    return U.downcase(arabic_to_roman(U.to_number(s)))
  elseif form == "ordinal" then
    return format_as_ordinal(s, term, ctx)
  elseif form == "long-ordinal" then
    return format_as_long_ordinal(s, term, ctx)
  end
  return s
end

--- citeproc-number-var-value
function M.number_var_value(value, variable, form, ctx)
  if value == nil or value == false then
    return nil
  end
  if type(value) == "number" then
    return U.num_str(value)
  end
  if type(value) ~= "string" then
    return value
  end
  local it = M.number_extract(value)
  if not it then
    return value
  end
  local first = number_format(it[1], form, variable, ctx)
  if it.n > 1 then
    return first .. (NUMSEP[it[2]] or "") .. (number_format(it[3], form, variable, ctx) or "")
  end
  return first
end

function E.number(attrs, ctx)
  local var = aget(attrs, "variable")
  local form = aget(attrs, "form")
  local value = M.var_value(var, ctx)
  if not value then
    return typed(nil, "empty-var")
  end
  return typed(
    M.format_single(acons("rendered-var", var, attrs), M.number_var_value(value, var, form, ctx), ctx),
    "present-var"
  )
end

---------------------------------------------------------------------------
-- Page ranges (citeproc-prange.el)
---------------------------------------------------------------------------

local function compare_strings(a, b)
  local ca, cb = U.codepoints(a), U.codepoints(b)
  local n = math.max(#ca, #cb)
  for i = 1, n do
    if ca[i] ~= cb[i] then
      return i
    end
  end
  return n + 1
end

local function fill_copy(s1, s2)
  local l1, l2 = U.len(s1), U.len(s2)
  if l1 >= l2 then
    return s1
  end
  return U.substring(s2, 0, l2 - l1) .. s1
end

local function end_significant(start, e, len)
  local first = math.min(math.max(1, 1 + U.len(e) - len), compare_strings(start, e))
  return U.substring(e, first - 1)
end

local function end_chicago(start, e, _, ed15)
  local len = U.len(start)
  if len < 3 or U.substring(start, -2) == "00" then
    return e
  elseif U.substring(start, -2, -1) == "0" then
    return end_significant(start, e, 1)
  elseif ed15 and len == 4 then
    local min_two = end_significant(start, e, 2)
    if U.len(min_two) > 2 then
      return e
    end
    return min_two
  end
  return end_significant(start, e, 2)
end

local PRANGE_FORMATTERS = {
  chicago = function(s, e, p)
    return end_chicago(s, e, p, true)
  end,
  ["chicago-15"] = function(s, e, p)
    return end_chicago(s, e, p, true)
  end,
  ["chicago-16"] = function(s, e, p)
    return end_chicago(s, e, p)
  end,
  minimal = function(s, e)
    return end_significant(s, e, 1)
  end,
  ["minimal-two"] = function(s, e)
    return end_significant(s, e, 2)
  end,
  expanded = function(_, e, p)
    return (p or "") .. e
  end,
}

local PRANGE_RE =
  "\\([[:digit:]]*[[:alpha:]]\\)?\\([[:digit:]]+\\)\\( ?\\)\\([-–—]+\\)\\( ?\\)\\([[:digit:]]*[[:alpha:]]\\)?\\([[:digit:]]+\\)"

--- citeproc-prange-render
function M.prange_render(p, format, sep)
  if type(p) ~= "string" then
    return p
  end
  local cps = U.codepoints(p)
  local pos = 0
  while true do
    local b, md = R.search(PRANGE_RE, cps, pos)
    if not b then
      break
    end
    local start_pref, start_num = md:str(1), md:str(2)
    local orig_dash = md:str(4)
    local orig_sep = (md:str(3) or "") .. orig_dash .. (md:str(5) or "")
    local end_pref, end_num = md:str(6), md:str(7)
    local e = (end_pref or "") .. end_num
    local old = orig_sep .. e
    local new
    if start_pref ~= end_pref then
      new = orig_dash .. e
    elseif start_num == end_num then
      new = ""
    elseif not format or U.len(end_num) > U.len(start_num) then
      new = sep .. e
    else
      local f = PRANGE_FORMATTERS[format]
      if not f then
        error(string.format("Unknown page range format: %s", tostring(format)), 0)
      end
      new = sep .. f(start_num, fill_copy(end_num, start_num), end_pref)
    end
    local match_end = md:e(0)
    if new ~= old then
      local old_len = U.len(old)
      local head = U.from_codepoints(cps, 1, match_end - old_len)
      local rest = U.from_codepoints(cps, match_end + 1, #cps)
      local new_cps = U.codepoints(head .. new)
      pos = #new_cps
      cps = U.codepoints(head .. new .. rest)
    else
      pos = match_end
    end
  end
  return U.from_codepoints(cps)
end

return M
