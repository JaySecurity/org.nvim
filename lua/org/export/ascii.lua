---@mod org.export.ascii Plain text back-end (port of Emacs ox-ascii.el)
---
--- Text is written with the `ascii`, `latin1` or `utf-8` charset
--- (`export.ascii.charset`, Emacs `org-ascii-charset`). Paragraphs are
--- filled like Emacs `fill-region` (two spaces after sentences, adaptive
--- fill prefixes, centered/right justification with tabs).
---
--- This file holds the configuration and the character and column helpers
--- of the fill buffer; the rest loads from org/export/ascii/: prefix (fill
--- prefixes), breaks (line breaking, CJK included), fill (justification
--- and fill-paragraph), layout (indentation, boxes, widths, titles, tables
--- of contents, link descriptions), template, transcode (markup, blocks,
--- headlines), text (links, paragraphs, lists, plain text), table (tables
--- and the last transcoders) and backend (filters, options, back-end).

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")

local M = {}
-- The parts in org/export/ascii/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.export.ascii"] = M

M.extension = "txt"

local fmt = string.format
local nw = ox.nw

--- Marker for a hard newline (line breaks, preserved breaks). Filling
--- never joins lines across it; it becomes "\n" once filled.
local HARD = "\1"
M.HARD = HARD

local function acfg()
  return (require("org.config").opts.export or {}).ascii or {}
end

local function charset(info)
  local c = info.ascii_charset or "ascii"
  if c == "utf8" then
    c = "utf-8"
  end
  return c
end

local function utf8p(info)
  return charset(info) == "utf-8"
end

---------------------------------------------------------------------------
-- Characters and columns
---------------------------------------------------------------------------

local CHAR_PAT = "[%z\1-\127\194-\244][\128-\191]*"

local function chars(s)
  local out = {}
  for ch in s:gmatch(CHAR_PAT) do
    out[#out + 1] = ch
  end
  return out
end

local width_cache = {}
local function cwidth(ch)
  local w = width_cache[ch]
  if not w then
    if ch == "\n" then
      w = 0
    elseif #ch == 1 and ch:byte() < 32 then
      w = ch == HARD and 0 or 2
    else
      w = vim.api.nvim_strwidth(ch)
    end
    width_cache[ch] = w
  end
  return w
end

--- string-width (no tabs expected).
local function swidth(s)
  if s == nil or s == "" then
    return 0
  end
  local w = 0
  for ch in s:gmatch(CHAR_PAT) do
    w = w + cwidth(ch)
  end
  return w
end
M.string_width = swidth

local function trim(s)
  return (s:gsub("^[ \t\n\r]+", ""):gsub("[ \t\n\r]+$", ""))
end

--- Column reached after the chars of B from `from` (a line start) up to `to` (exclusive).
local function column_between(B, from, to)
  local c = 0
  for i = from, to - 1 do
    local ch = B[i]
    if ch == "\t" then
      c = c + 8 - (c % 8)
    else
      c = c + cwidth(ch)
    end
  end
  return c
end

local function bol(B, pos)
  local p = pos
  while p > 1 and B[p - 1] ~= "\n" do
    p = p - 1
  end
  return p
end

local function eol(B, pos)
  local p = pos
  local n = #B
  while p <= n and B[p] ~= "\n" do
    p = p + 1
  end
  return p
end

local function insert_chars(B, pos, list)
  for i = #list, 1, -1 do
    table.insert(B, pos, list[i])
  end
  return #list
end

local function delete_range(B, a, b)
  -- delete chars in [a, b)
  for _ = a, b - 1 do
    table.remove(B, a)
  end
  return b - a
end

--- Whitespace inserted by `indent-to` from column FROMCOL to TOCOL.
local function indent_chars(fromcol, tocol, tabs)
  local out = {}
  if tocol <= fromcol then
    return out
  end
  local c = fromcol
  if tabs then
    local n = math.floor(tocol / 8) - math.floor(fromcol / 8)
    for _ = 1, n do
      out[#out + 1] = "\t"
    end
    if n > 0 then
      c = math.floor(tocol / 8) * 8
    end
  end
  for _ = c + 1, tocol do
    out[#out + 1] = " "
  end
  return out
end

local function trunc_div(a, b)
  local q = a / b
  if q >= 0 then
    return math.floor(q)
  end
  return math.ceil(q)
end

-- Locals the parts below share
local shared = require("org.export.ascii.shared")
shared.HARD = HARD
shared.acfg = acfg
shared.charset = charset
shared.utf8p = utf8p
shared.CHAR_PAT = CHAR_PAT
shared.chars = chars
shared.cwidth = cwidth
shared.swidth = swidth
shared.trim = trim
shared.column_between = column_between
shared.bol = bol
shared.eol = eol
shared.insert_chars = insert_chars
shared.delete_range = delete_range
shared.indent_chars = indent_chars
shared.trunc_div = trunc_div

require("org.export.ascii.prefix")
require("org.export.ascii.breaks")
require("org.export.ascii.fill")
require("org.export.ascii.layout")
require("org.export.ascii.template")
require("org.export.ascii.transcode")
require("org.export.ascii.text")
require("org.export.ascii.table")
require("org.export.ascii.backend")

return M
