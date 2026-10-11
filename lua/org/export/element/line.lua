---@mod org.export.element.line Line classification for the export parser
---
--- Predicates on single lines (headlines, comments, clocks, drawers,
--- blocks, tables, list items) and affiliated keywords.
---
--- Part of org.export.element, which loads it.

local shared = require("org.export.element.shared")

local indentation = shared.indentation

---------------------------------------------------------------------------
-- Line classification
---------------------------------------------------------------------------

local function headline_stars(l)
  local stars = l:match("^(%*+) ")
  return stars and #stars or nil
end

local function is_comment_line(l)
  return l:match("^[ \t]*#$") ~= nil or l:match("^[ \t]*# ") ~= nil
end

local function is_clock_line(l)
  return l:match("^[ \t]*CLOCK:") ~= nil
end

local function is_planning_line(l)
  return l:match("^[ \t]*CLOSED:") ~= nil or l:match("^[ \t]*DEADLINE:") ~= nil or l:match("^[ \t]*SCHEDULED:") ~= nil
end

local function drawer_name(l)
  return l:match("^[ \t]*:([%w%-_]+):[ \t]*$")
end

local function is_end_line(l)
  return l:match("^[ \t]*:[Ee][Nn][Dd]:[ \t]*$") ~= nil
end

--- A node property line (org-property-re): the key's closing colon is
--- followed by a blank or the end of the line. Returns key and value.
---@return string|nil key, string|nil value
local function property_line(l)
  local key, value = l:match("^[ \t]*:(%S+):[ \t]+(.-)[ \t]*$")
  if not key then
    key = l:match("^[ \t]*:(%S+):$")
    value = key and ""
  end
  return key, value
end

--- When L[i] opens a property drawer (org-property-drawer-re: only
--- property lines up to an :END: line, at most line `e`), that line.
---@return integer|nil
local function property_drawer_end(L, i, e)
  if not (L[i] and L[i]:match("^[ \t]*:[Pp][Rr][Oo][Pp][Ee][Rr][Tt][Ii][Ee][Ss]:[ \t]*$")) then
    return nil
  end
  for j = i + 1, e do
    if is_end_line(L[j]) then
      return j
    elseif not property_line(L[j]) then
      return nil
    end
  end
  return nil
end

local function is_fixed_width(l)
  return l:match("^[ \t]*:$") ~= nil or l:match("^[ \t]*: ") ~= nil
end

local function is_footnote_def(l)
  return l:match("^%[fn:[%w%-_]+%]") ~= nil
end

local function is_hr(l)
  return l:match("^[ \t]*%-%-%-%-%-+[ \t]*$") ~= nil
end

local function latex_env_begin(l)
  return l:match("^[ \t]*\\begin{([%w%*]+)}")
end

local function block_type(l)
  return l:match("^[ \t]*#%+[Bb][Ee][Gg][Ii][Nn]_(%S+)")
end

local function is_dynamic_block(l)
  return l:match("^[ \t]*#%+[Bb][Ee][Gg][Ii][Nn]:[ \t]*%S") ~= nil
end

local function is_table_line(l)
  return l:match("^[ \t]*|") ~= nil
end

local function is_tableel_rule(l)
  return require("org.table.el").is_rule(l)
end

--- Item bullet of a line (org-item-re, alphabetical bullets when allowed).
local function item_match(l, alpha, term)
  term = term or "[%.%)]"
  local ind, bullet = l:match("^([ \t]*)([%-%+])[ \t]")
  if not ind then
    ind, bullet = l:match("^([ \t]*)([%-%+])$")
  end
  if not ind then
    ind, bullet = l:match("^([ \t]+)(%*)[ \t]")
    if not ind then
      ind, bullet = l:match("^([ \t]+)(%*)$")
    end
  end
  if not ind then
    ind, bullet = l:match("^([ \t]*)(%d+" .. term .. ")[ \t]")
    if not ind then
      ind, bullet = l:match("^([ \t]*)(%d+" .. term .. ")$")
    end
  end
  if not ind and alpha then
    ind, bullet = l:match("^([ \t]*)(%a" .. term .. ")[ \t]")
    if not ind then
      ind, bullet = l:match("^([ \t]*)(%a" .. term .. ")$")
    end
  end
  if ind then
    return indentation(ind), bullet
  end
end

local AFFILIATED = {
  CAPTION = "CAPTION",
  DATA = "NAME",
  HEADER = "HEADER",
  HEADERS = "HEADER",
  LABEL = "NAME",
  NAME = "NAME",
  PLOT = "PLOT",
  RESNAME = "NAME",
  RESULT = "RESULTS",
  RESULTS = "RESULTS",
  SOURCE = "NAME",
  SRCNAME = "NAME",
  TBLNAME = "NAME",
}
local DUAL = { CAPTION = true, RESULTS = true }
local MULTIPLE = { CAPTION = true, HEADER = true }
local PARSED = { CAPTION = true }

--- Match an affiliated keyword line. Returns official key, value, dual value.
local function affiliated_match(l)
  local key, rest = l:match("^[ \t]*#%+([%w_%-]+)(.*)$")
  if not key then
    return nil
  end
  local up = key:upper()
  local official = AFFILIATED[up]
  local dual
  if official and DUAL[official] then
    local d, r = rest:match("^%[(.*)%](:.*)$")
    if d then
      dual, rest = d, r
    end
  end
  if not rest:match("^:") then
    return nil
  end
  if not official then
    if up:match("^ATTR_[%w_%-]+$") then
      official = up
    else
      return nil
    end
  end
  local value = rest:sub(2):gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
  return official, value, dual
end

-- Locals the later parts share
shared.headline_stars = headline_stars
shared.is_comment_line = is_comment_line
shared.is_clock_line = is_clock_line
shared.is_planning_line = is_planning_line
shared.drawer_name = drawer_name
shared.is_end_line = is_end_line
shared.property_line = property_line
shared.property_drawer_end = property_drawer_end
shared.is_fixed_width = is_fixed_width
shared.is_footnote_def = is_footnote_def
shared.is_hr = is_hr
shared.latex_env_begin = latex_env_begin
shared.block_type = block_type
shared.is_dynamic_block = is_dynamic_block
shared.is_table_line = is_table_line
shared.is_tableel_rule = is_tableel_rule
shared.item_match = item_match
shared.DUAL = DUAL
shared.MULTIPLE = MULTIPLE
shared.PARSED = PARSED
shared.affiliated_match = affiliated_match
