---@mod org.export.ascii.prefix Plain text fill prefixes
---
--- Adaptive fill prefixes and the no-break predicates of fill.el.
---
--- Part of org.export.ascii, which loads it.

local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local bol = shared.bol
local chars = shared.chars
local eol = shared.eol
local swidth = shared.swidth

---------------------------------------------------------------------------
-- Filling (fill.el)
---------------------------------------------------------------------------

local ADAPTIVE = {
  ["-"] = true,
  ["–"] = true,
  ["!"] = true,
  ["|"] = true,
  ["#"] = true,
  ["%"] = true,
  [";"] = true,
  [">"] = true,
  ["*"] = true,
  ["·"] = true,
  ["•"] = true,
  ["‣"] = true,
  ["⁃"] = true,
  ["◦"] = true,
  [" "] = true,
  ["\t"] = true,
}

local SENTENCE_PUNCT = { ["."] = true, ["?"] = true, ["!"] = true, ["…"] = true, ["‽"] = true }
local CLOSERS = {
  ["]"] = true,
  ['"'] = true,
  ["'"] = true,
  ["”"] = true,
  ["’"] = true,
  [")"] = true,
  ["}"] = true,
  ["»"] = true,
  ["›"] = true,
}
-- characters skipped backward by canonically-space-region
local SKIP_BACK = { [" "] = true, ["]"] = true, ["}"] = true, [")"] = true, ['"'] = true, ["'"] = true }
local NBSP = "\194\160"
local CJK_END = { ["。"] = true, ["．"] = true, ["？"] = true, ["！"] = true }

local function is_sp(ch)
  return ch == " " or ch == "\t"
end

--- Length (chars) of the adaptive-fill-regexp match at pos.
local function adaptive_match(B, pos, limit)
  local p = pos
  limit = limit or #B + 1
  while p < limit and ADAPTIVE[B[p]] do
    p = p + 1
  end
  return p - pos
end

--- fill-match-adaptive-prefix at line start pos.
local function match_adaptive_prefix(B, pos, fc)
  local e = eol(B, pos)
  local n = adaptive_match(B, pos, e)
  if n >= fc then
    return nil
  end
  return table.concat(B, "", pos, pos + n - 1)
end

--- fill-context-prefix
local function context_prefix(B, from, to, fc)
  local p = from
  if B[p] == "\n" then
    p = p + 1
  end
  local first = match_adaptive_prefix(B, p, fc)
  local e = eol(B, p)
  local q = e + 1
  if q < to then
    local line = table.concat(B, "", q, eol(B, q) - 1)
    local second
    if line:match("^\f") or line:match("^[ \t]*$") then
      second = nil
    else
      second = match_adaptive_prefix(B, q, fc)
    end
    if second then
      first = first or ""
      -- the non-blank runs of the second prefix must appear in the first
      local pos = 1
      local ok = true
      for run in second:gmatch("[^ \t]+") do
        local a, b = first:find(run, pos, true)
        if not a then
          ok = false
          break
        end
        pos = b + 1
      end
      if ok then
        return second
      end
      local fc_ = chars(first)
      local sc = chars(second)
      local i = 1
      while i <= #fc_ and i <= #sc and fc_[i] == sc[i] do
        i = i + 1
      end
      if i == 1 then
        return nil
      end
      return table.concat(fc_, "", 1, i - 1)
    end
    return nil
  end
  if first then
    local result
    if first:match("^[ \t]*$") then
      result = first
    else
      result = string.rep(" ", swidth(first))
    end
    if (result .. "a"):match("^\f") then
      return nil
    end
    return result
  end
  return nil
end

--- Length (chars) of the fill-delete-prefix pattern match at pos.
local function fpre_match(B, pos, prefix, limit)
  local p = pos
  while p < limit and is_sp(B[p]) do
    p = p + 1
  end
  if prefix and not prefix:match("^[ \t]*$") then
    -- prefix with flexible blanks
    local pc = chars(prefix)
    local k = 1
    local q = p
    local ok = true
    while k <= #pc do
      if is_sp(pc[k]) then
        while k <= #pc and is_sp(pc[k]) do
          k = k + 1
        end
        while q < limit and is_sp(B[q]) do
          q = q + 1
        end
      else
        if B[q] ~= pc[k] then
          ok = false
          break
        end
        k = k + 1
        q = q + 1
      end
    end
    if ok then
      p = q
      while p < limit and is_sp(B[p]) do
        p = p + 1
      end
    end
  end
  return p - pos
end

--- fill-nobreak-p at pos (point before B[pos]).
local function nobreak_p(B, pos)
  if pos == bol(B, pos) then
    return false
  end
  local r = pos
  while r > 1 and B[r - 1] == " " do
    r = r - 1
  end
  if B[r - 1] == "." and B[r] == " " then
    local nx = B[r + 1]
    if nx ~= nil and nx ~= " " and nx ~= "\n" then
      return true
    end
  end
  return false
end

-- Locals the later parts share
shared.SENTENCE_PUNCT = SENTENCE_PUNCT
shared.CLOSERS = CLOSERS
shared.SKIP_BACK = SKIP_BACK
shared.NBSP = NBSP
shared.CJK_END = CJK_END
shared.is_sp = is_sp
shared.adaptive_match = adaptive_match
shared.context_prefix = context_prefix
shared.fpre_match = fpre_match
shared.nobreak_p = nobreak_p
