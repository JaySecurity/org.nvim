---@mod org.export.ascii.breaks Plain text line breaking
---
--- CJK line breaking (characters.el, kinsoku.el) and the break point
--- search of fill.el.
---
--- Part of org.export.ascii, which loads it.

local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local CHAR_PAT = shared.CHAR_PAT
local bol = shared.bol
local column_between = shared.column_between
local eol = shared.eol
local is_sp = shared.is_sp
local nobreak_p = shared.nobreak_p

-- CJK line breaking (characters.el, fill.el, kinsoku.el)

--- Code point of the UTF-8 character `ch`.
local function codepoint(ch)
  local b1 = ch:byte(1) or 0
  if b1 < 0x80 then
    return b1
  end
  local n = b1 >= 0xF0 and 3 or b1 >= 0xE0 and 2 or 1
  local c = b1 % (2 ^ (6 - n))
  for i = 2, n + 1 do
    c = c * 64 + ((ch:byte(i) or 0x80) % 64)
  end
  return c
end

local function in_ranges(ch, ranges)
  if ch == nil or #ch < 2 then
    return false
  end
  local c = codepoint(ch)
  for _, r in ipairs(ranges) do
    if c >= r[1] and c <= r[2] then
      return true
    end
  end
  return false
end

-- Category `|`, a line can be broken before or after the character.
local BREAKABLE = {
  { 0x2E80, 0x312F },
  { 0x3190, 0x33FF },
  { 0x3400, 0x9FFF },
  { 0xF900, 0xFAFF },
  { 0x20000, 0x2FFFF },
  { 0x30000, 0x323AF },
}
-- fill-nospace-between-words-table (and the kinsoku table): the han,
-- kana, bopomofo and cjk-misc scripts, and full width characters.
local NOSPACE = {
  { 0x2E80, 0x2FDF },
  { 0x3000, 0x33FF },
  { 0x3400, 0x4DBF },
  { 0x4E00, 0x9FFF },
  { 0xF900, 0xFAFF },
  { 0xFE30, 0xFE4F },
  { 0xFF01, 0xFFE6 },
  { 0x1B000, 0x1B16F },
  { 0x20000, 0x323AF },
}

local function breakable(ch)
  return in_ranges(ch, BREAKABLE)
end
local function nospace(ch)
  return in_ranges(ch, NOSPACE)
end

local function char_set(s)
  local t = {}
  for ch in s:gmatch(CHAR_PAT) do
    t[ch] = true
  end
  return t
end
-- kinsoku-bol (category `>`): not at the beginning of a line
local KINSOKU_BOL = char_set(
  "!)-_~}]:;',.?｡｣ｧｨｩｪｫｬｭｮｯｰﾞﾟ"
    .. "、。，．・：；？！゛゜´｀¨＾￣＿ヽヾゝゞ〃仝々〆〇ー—‐／＼〜‖｜…‥’”）〕］｝〉》」』】°′″℃"
    .. "ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ"
    .. "ˉˇ―～〗±×÷∶＂ㄥ‧︰﹐﹑﹒·﹔﹕﹖﹗–︱︳╴︴﹏︶︸︺︼︾﹀﹂﹄﹚﹜﹞〞¯ˍ﹉﹊﹍﹎﹋﹌℉﹩"
)
-- kinsoku-eol (category `<`): not at the end of a line
local KINSOKU_EOL = char_set(
  "({[`｢‘“（〔［｛〈《「『【°′″℃＠§＂〖ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙㄨ"
    .. "︵｛︷︹︻︽︿﹁﹃﹙﹛﹝〝‵〃℉﹫"
)

-- kinsoku-limit: how many columns a line may grow by
local KINSOKU_LIMIT = 4

--- Not a word boundary for kinsoku: the previous char is no space and
--- not breakable ("protect non-kinsoku words").
local function inside_word(B, p)
  return not (B[p - 1] == " " or breakable(B[p - 1]))
end

--- kinsoku-longer: move the break after the characters that can't begin
--- a line, when the line stays within the limit. Returns the new point.
local function kinsoku_longer(B, pt, fc)
  local p = pt + 1
  local e = eol(B, pt)
  while p < e and (KINSOKU_BOL[B[p]] or inside_word(B, p)) do
    p = p + 1
  end
  if KINSOKU_LIMIT <= 0 or column_between(B, bol(B, pt), p) < fc + KINSOKU_LIMIT then
    return p
  end
end

--- kinsoku-shorter: move the break back before them.
local function kinsoku_shorter(B, pt, linebeg)
  local p = pt - 1
  while linebeg < p and (KINSOKU_EOL[B[p - 1]] or KINSOKU_BOL[B[p]] or inside_word(B, p)) do
    p = p - 1
  end
  return linebeg < p and p or pt
end

--- fill-find-break-point (kinsoku) at pt.
local function find_break_point(B, pt, linebeg, fc)
  if not (nospace(B[pt]) or nospace(B[pt - 1])) then
    return pt
  end
  if KINSOKU_BOL[B[pt]] then
    local longer = kinsoku_longer(B, pt, fc)
    if longer then
      return longer
    end
    return kinsoku_shorter(B, pt, linebeg)
  elseif KINSOKU_EOL[B[pt - 1]] then
    return kinsoku_shorter(B, pt, linebeg)
  end
  return pt
end

--- fill-move-to-break-point; returns the new point. A line breaks after a
--- space, or before or after a breakable (CJK) character.
local function move_to_break_point(B, pt, linebeg, fc)
  if linebeg > pt then
    pt = linebeg
  end
  while true do
    -- re-search-backward "[ \t]\\|\\c|.\\|.\\c|": the last match ending
    -- by pt, then point after its first character
    local q = pt - 1
    while q >= linebeg do
      local ch, nx = B[q], B[q + 1]
      if is_sp(ch) then
        break
      elseif q + 1 < pt and nx ~= "\n" and ch ~= "\n" and (breakable(ch) or breakable(nx)) then
        break
      end
      q = q - 1
    end
    if q < linebeg then
      pt = linebeg
      break
    end
    pt = q + 1
    if nobreak_p(B, pt) then
      while pt > linebeg and is_sp(B[pt - 1]) do
        pt = pt - 1
      end
    else
      break
    end
  end
  while pt > 1 and is_sp(B[pt - 1]) do
    pt = pt - 1
  end
  if linebeg >= pt then
    -- keep at least one word or one breakable character
    local to2 = eol(B, linebeg)
    pt = linebeg
    local first = true
    while pt < to2 and (first or nobreak_p(B, pt)) do
      while pt < to2 and is_sp(B[pt]) do
        pt = pt + 1
      end
      if breakable(B[pt]) then
        pt = pt + 1
      else
        local pos = pt
        while pos < to2 and not (is_sp(B[pos]) or B[pos] == "\n") do
          pos = pos + 1
        end
        local r = pt
        while r < pos and not breakable(B[r]) do
          r = r + 1
        end
        pt = r < pos and r or pos
      end
      first = false
    end
  elseif #(B[pt - 1] or "") > 1 or #(B[pt] or "") ~= 1 then
    -- breaking after or before a non-ASCII character
    pt = find_break_point(B, pt, linebeg, fc)
  end
  return pt
end

-- Locals the later parts share
shared.breakable = breakable
shared.nospace = nospace
shared.move_to_break_point = move_to_break_point
