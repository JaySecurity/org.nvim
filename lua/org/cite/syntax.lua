---@mod org.cite.syntax Citation syntax
---
--- Parsing citations and citation references in a string
--- (org-element-citation-parser, org-element-citation-reference-parser)
--- and finding the one at a point (org-element-context). Part of org.cite,
--- which loads it.

local M = require("org.cite")

--- org-element-citation-key-re: "@" then word characters or any of
--- -.:?!`'/*@+|(){}<>&_^$#%~.
local KEY_CHARS = "[%w\128-\255%-%.:%?!`'/%*@%+|%(%){}<>&_%^%$#%%~]"

--- First key in [from, limit): key start ("@"), key, key end.
local function find_key(s, from, limit)
  local i = from
  while true do
    local a = s:find("@", i, true)
    if not a or a >= limit then
      return nil
    end
    local run = s:match("^" .. KEY_CHARS .. "+", a + 1)
    if run then
      local e = math.min(a + 1 + #run, limit)
      if e > a + 1 then
        return a, s:sub(a + 1, e - 1), e
      end
    end
    i = a + 1
  end
end
M.find_key = find_key

--- Last `c` at an index in [from, to].
local function rfind(s, c, from, to)
  for i = to, from, -1 do
    if s:sub(i, i) == c then
      return i
    end
  end
end

--- Index of the "]" closing the "[" at p (square brackets only, like
--- org-element--pair-square-table).
local function closing_bracket(s, p)
  local depth = 0
  for k = p, #s do
    local c = s:byte(k)
    if c == 91 then
      depth = depth + 1
    elseif c == 93 then
      depth = depth - 1
      if depth == 0 then
        return k
      end
    end
  end
end

---@class org.cite.Reference
---@field begin integer
---@field stop integer end (after the ";" separator, if any)
---@field key string
---@field key_begin integer the "@"
---@field key_end integer
---@field prefix boolean
---@field suffix boolean

---@class org.cite.Citation
---@field begin integer the "["
---@field stop integer after "]" (org-cite-boundaries)
---@field end_ integer after the blanks following "]"
---@field style? string
---@field style_end integer the ":" after the style
---@field contents_begin integer
---@field contents_end integer
---@field prefix boolean global prefix
---@field suffix boolean global suffix
---@field references org.cite.Reference[]

--- Parse the citation starting at `p` in `s`, or nil.
---@return org.cite.Citation|nil
function M.parse(s, p)
  local style, after = s:match("^%[cite/([/_%w%-]+):()", p)
  if not style then
    after = s:match("^%[cite:()", p)
    if not after then
      return nil
    end
  end
  local start = s:match("^[\t\n ]*()", after)
  local close = closing_bracket(s, p)
  if not close then
    return nil
  end
  local _, _, first_key_end = find_key(s, start, close)
  if not first_key_end then
    return nil
  end
  local cite = {
    begin = p,
    stop = close + 1,
    end_ = s:match("^[ \t]*()", close + 1),
    style = style,
    style_end = after - 1,
    prefix = false,
    suffix = false,
  }
  -- :contents-begin depends on a non-empty common prefix
  local semi = rfind(s, ";", start, first_key_end - 1)
  if not semi then
    cite.contents_begin = start
  else
    cite.prefix = start < semi
    cite.contents_begin = semi + 1
  end
  -- :contents-end depends on a non-empty common suffix
  local e = close
  while e > first_key_end and s:sub(e - 1, e - 1):match("[ \r\t\n]") do
    e = e - 1
  end
  semi = rfind(s, ";", first_key_end, e - 1)
  if not semi or find_key(s, semi, e) then
    cite.contents_end = e
  else
    cite.suffix = semi + 1 < e
    cite.contents_end = semi + 1
  end
  -- references
  local refs = {}
  local pos = cite.contents_begin
  while pos < cite.contents_end do
    local kb, key, ke = find_key(s, pos, cite.contents_end)
    if not kb then
      break
    end
    local sep = s:find(";", ke, true)
    if sep and sep >= cite.contents_end then
      sep = nil
    end
    local stop = sep and sep + 1 or cite.contents_end
    local suffix_end = sep or cite.contents_end
    refs[#refs + 1] = {
      begin = pos,
      stop = stop,
      key = key,
      key_begin = kb,
      key_end = ke,
      prefix = pos < kb,
      suffix = ke < suffix_end,
    }
    pos = stop
  end
  cite.references = refs
  return cite
end

--- Citations in `s`, in order.
---@return org.cite.Citation[]
function M.citations(s)
  local out = {}
  local i = 1
  while true do
    local a = s:find("[cite", i, true)
    if not a then
      break
    end
    local c = M.parse(s, a)
    if c then
      out[#out + 1] = c
      i = c.stop
    else
      i = a + 1
    end
  end
  return out
end

local function blank_before(s, pos)
  local c = s:sub(pos - 1, pos - 1)
  return c == " " or c == "\t"
end

--- The citation or citation reference at point `pos` in `s`, following
--- org-element-context. Returns type, citation, reference.
---@return "citation"|"citation-reference"|nil, org.cite.Citation|nil, org.cite.Reference|nil
function M.context_in(s, pos)
  local last
  for _, c in ipairs(M.citations(s)) do
    if c.begin > pos then
      break
    end
    if c.end_ <= pos and c.end_ ~= #s + 1 then
      if c.end_ == pos and not blank_before(s, pos) then
        last = c
      end
    else
      local cb, ce = c.contents_begin, c.contents_end
      if pos >= cb and (pos < ce or (pos == ce and (pos == #s + 1 or not blank_before(s, pos)))) then
        local last_ref
        for _, r in ipairs(c.references) do
          if r.begin > pos then
            break
          end
          if r.stop <= pos and r.stop ~= ce then
            if r.stop == pos and not blank_before(s, pos) then
              last_ref = r
            end
          else
            return "citation-reference", c, r
          end
        end
        if last_ref then
          return "citation-reference", c, last_ref
        end
      end
      return "citation", c
    end
  end
  if last then
    return "citation", last
  end
  return nil
end
