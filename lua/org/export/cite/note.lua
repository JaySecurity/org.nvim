---@mod org.export.cite.note Citations in footnotes
---
--- org-cite-adjust-note: moving punctuation and quotes around a citation
--- exported as a footnote (`export.cite.note_rules`).
---
--- Part of org.export.cite, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local M = require("org.export.cite")
local shared = require("org.export.cite.shared")

local fmt = string.format
local nw = ox.nw
local opt, text, adopt, insert_before = shared.opt, shared.text, shared.adopt, shared.insert_before
local set_previous_post_blank = M.set_previous_post_blank

local function note_rule(info)
  local lang = info.language or "en"
  local parts = vim.split(lang, "[-_]")
  local language, region
  if #parts == 1 then
    language = parts[1]
    region = M.DEFAULT_REGION[language] or language
  elseif #parts == 2 then
    language, region = parts[1], parts[2]
  else
    error(fmt("Invalid language identifier: %s", lang), 0)
  end
  local rules = opt("note_rules", M.DEFAULT_NOTE_RULES)
  return rules[(language .. "-" .. region):lower()] or rules[language:lower()] or { "adaptive", "outside", "after" }
end

--- Match org-cite-adjust-note's previous-punct-re at the end of S.
--- Returns { m0, g1 = {s, e}, g2 = {s, e}, g3 = {s, e} } (1-based, inclusive).
local function previous_punct_match(s, punct)
  local n = #s
  local pos = n
  local r = {}
  local k = pos
  while k >= 1 and s:sub(k, k):match("[ \t\n]") do
    k = k - 1
  end
  if k < pos then
    r.g3 = { k + 1, pos }
  end
  pos = k
  local start = pos + 1
  if pos >= 1 and s:sub(pos, pos) == '"' then
    r.g2 = { pos, pos }
    local q = pos - 1
    while q >= 1 and s:sub(q, q):match("[ \t\n]") do
      q = q - 1
    end
    start = q + 1
    pos = q
  end
  if pos >= 1 and punct[s:sub(pos, pos)] then
    local b = pos - 1
    while b >= 1 and s:sub(b, b):match("[ \t\n]") do
      b = b - 1
    end
    -- blanks before the punctuation belong to group 1 only when the
    -- quote group does not already own them
    r.g1 = { b + 1, pos }
    start = b + 1
  end
  r.m0 = start
  return r
end

local function substr(s, g)
  return s:sub(g[1], g[2])
end

--- org-cite--insert-at-split
local function insert_at_split(s, citation, split)
  local pb = citation.post_blank or 0
  if pb > 0 then
    insert_before(text(string.rep(" ", pb)), citation)
  end
  element.extract(citation)
  citation.post_blank = 0
  insert_before(citation, s)
  local first = s.value:sub(1, split - 1)
  local last = s.value:sub(split):gsub("[ \t\n]+$", "")
  if nw(first) then
    insert_before(text(first), citation)
  end
  s.value = last
end

--- org-cite--move-punct-before
local function move_punct_before(punct, citation, s, info)
  if s.value == punct then
    element.extract(s)
  else
    s.value = s.value:sub(#punct + 1)
  end
  set_previous_post_blank(citation, 0, info)
  insert_before(text(string.rep(" ", citation.post_blank or 0) .. punct), citation)
end

local TERMINALS = {
  citation = true,
  code = true,
  entity = true,
  ["export-snippet"] = true,
  ["footnote-reference"] = true,
  ["line-break"] = true,
  ["latex-fragment"] = true,
  link = true,
  ["plain-text"] = true,
  ["radio-target"] = true,
  ["statistics-cookie"] = true,
  timestamp = true,
  verbatim = true,
}

--- Move the note number and punctuation around a citation (org-cite-adjust-note).
function M.adjust_note(citation, info, rule, punct_list)
  if not opt("adjust_note_numbers", true) then
    return
  end
  rule = rule or note_rule(info)
  local marks = {}
  for _, m in ipairs(punct_list or opt("punctuation_marks", { ".", ",", ";", ":", "!", "?" })) do
    marks[m] = true
  end
  local next_ = ox.get_next_element(citation, info)
  local final_punct
  if next_ and next_.type == "plain-text" then
    local ws, p = next_.value:match("^([ \t\n]*)(.)")
    if p and marks[p] then
      final_punct = ws .. p
    end
  end
  local prev_el = ox.get_previous_element(citation, info)
  local previous
  if prev_el then
    local found = element.map(prev_el, TERMINALS, function(x)
      return x
    end, { ignore = info.ignore, no_recursion = { citation = true, subscript = true, superscript = true } })
    previous = found[#found]
  end
  local punct, quote, spacing
  local m
  if previous and previous.type == "plain-text" then
    m = previous_punct_match(previous.value, marks)
    punct = m.g1 and substr(previous.value, m.g1) or nil
    quote = m.g2 and '"' or nil
    spacing = m.g3 and substr(previous.value, m.g3) or nil
  end
  if not (quote or ((punct ~= nil) ~= (final_punct ~= nil))) then
    return
  end
  -- phase 1: punctuation rule
  if quote then
    local p1 = rule[1]
    if p1 == "inside" or (p1 == "adaptive" and not spacing) then
      if not punct and final_punct then
        local s = previous.value
        previous.value = s:sub(1, m.g2[1] - 1) .. final_punct .. '"' .. s:sub(m.g2[2] + 1)
        next_.value = next_.value:sub(#final_punct + 1)
        punct = final_punct
        final_punct = nil
        m = previous_punct_match(previous.value, marks)
      end
    elseif p1 == "outside" or (p1 == "adaptive" and spacing) then
      if punct and not final_punct then
        local s = previous.value
        previous.value = s:sub(1, m.g1[1] - 1) .. s:sub(m.g1[2] + 1)
        if next_ and next_.type == "plain-text" then
          next_.value = punct .. next_.value
        elseif next_ then
          insert_before(text(punct), next_)
        else
          adopt(citation.parent, text(punct))
        end
        next_ = ox.get_next_element(citation, info)
        final_punct = punct
        punct = nil
        m = previous_punct_match(previous.value, marks)
      end
    else
      error("Invalid punctuation rule", 0)
    end
  end
  -- phase 2: citation location
  local number, order = rule[2], rule[3]
  if number == "same" then
    if punct and final_punct then
      number = "outside"
    elseif punct then
      number = "inside"
    elseif final_punct then
      number = "outside"
    else
      number = nil
    end
  end
  if number == nil then
    return
  elseif number == "inside" and order == "after" then
    if quote then
      insert_at_split(previous, citation, m.g2[1])
    elseif final_punct then
      move_punct_before(final_punct, citation, next_, info)
    end
  elseif number == "inside" and order == "before" then
    if punct or quote then
      insert_at_split(previous, citation, m.m0)
    end
  elseif number == "outside" and order == "after" then
    if final_punct then
      move_punct_before(final_punct, citation, next_, info)
    end
  elseif number == "outside" and order == "before" then
    if punct and not quote then
      insert_at_split(previous, citation, m.m0)
    end
  else
    error("Invalid punctuation rule", 0)
  end
end

return M
