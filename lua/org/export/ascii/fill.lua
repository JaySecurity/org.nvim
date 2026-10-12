---@mod org.export.ascii.fill Plain text filling
---
--- Justification, canonical spacing and fill-paragraph (fill.el),
--- M.fill_string and M.justify_lines.
---
--- Part of org.export.ascii, which loads it.

local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local CJK_END = shared.CJK_END
local CLOSERS = shared.CLOSERS
local HARD = shared.HARD
local NBSP = shared.NBSP
local SENTENCE_PUNCT = shared.SENTENCE_PUNCT
local SKIP_BACK = shared.SKIP_BACK
local adaptive_match = shared.adaptive_match
local bol = shared.bol
local breakable = shared.breakable
local chars = shared.chars
local column_between = shared.column_between
local context_prefix = shared.context_prefix
local cwidth = shared.cwidth
local delete_range = shared.delete_range
local eol = shared.eol
local fpre_match = shared.fpre_match
local indent_chars = shared.indent_chars
local insert_chars = shared.insert_chars
local is_sp = shared.is_sp
local move_to_break_point = shared.move_to_break_point
local nospace = shared.nospace
local trunc_div = shared.trunc_div

--- justify-current-line on the line starting at lstart. Returns the
--- number of chars inserted (negative when removed).
local function justify_line(B, lstart, how, fc, opts)
  if how ~= "right" and how ~= "center" then
    return 0
  end
  local e = eol(B, lstart)
  while e > lstart and is_sp(B[e - 1]) do
    e = e - 1
  end
  if e == lstart then
    return 0
  end
  if how == "right" and column_between(B, lstart, e) == fc then
    return 0
  end
  local p = lstart
  while p < e and is_sp(B[p]) do
    p = p + 1
  end
  local prefix = opts.prefix
  local pc = prefix and prefix ~= "" and chars(prefix) or nil
  local matched = false
  if pc then
    matched = true
    for k = 1, #pc do
      if B[p + k - 1] ~= pc[k] then
        matched = false
        break
      end
    end
  end
  if matched then
    p = p + #pc
  elseif opts.adaptive then
    p = p + adaptive_match(B, p, e)
  end
  local fp_end = p
  while p < e and is_sp(B[p]) do
    p = p + 1
  end
  local beg = p
  local indent = column_between(B, lstart, beg)
  local endcol = column_between(B, lstart, e)
  local ncols
  if how == "right" then
    ncols = fc - endcol
    if ncols < 0 then
      local target = indent + ncols
      local s = fp_end
      if column_between(B, lstart, s) < target then
        while s < beg and column_between(B, lstart, s) < target do
          s = s + 1
        end
      end
      return -delete_range(B, s, beg)
    end
    return insert_chars(B, beg, indent_chars(indent, indent + ncols, opts.tabs))
  end
  ncols = trunc_div(fc - (endcol - indent), 2)
  if ncols < indent then
    local s = fp_end
    if column_between(B, lstart, s) < ncols then
      while s < beg and column_between(B, lstart, s) < ncols do
        s = s + 1
      end
    end
    return -delete_range(B, s, beg)
  end
  return insert_chars(B, beg, indent_chars(indent, ncols, opts.tabs))
end

--- canonically-space-region on B[from, to); returns the new `to`.
local function canonically_space(B, from, to)
  for i = from, to - 1 do
    if B[i] == "\t" then
      B[i] = " "
    end
  end
  local pt = from
  while pt < to do
    -- leftmost match of sentence-end or "  +"
    local found
    local i = pt
    while i < to do
      local ch = B[i]
      if SENTENCE_PUNCT[ch] then
        local j = i + 1
        while j < to and CLOSERS[B[j]] do
          j = j + 1
        end
        local ok = false
        if j >= to then
          ok = true
        elseif (B[j] == " " or B[j] == NBSP) and j + 1 >= to then
          ok = true
        elseif B[j] == "\t" then
          ok = true
        elseif (B[j] == " " or B[j] == NBSP) and (B[j + 1] == " " or B[j + 1] == NBSP) then
          ok = true
        end
        if ok then
          local k = j
          while k < to and (B[k] == " " or B[k] == NBSP or B[k] == "\t" or B[k] == "\n") do
            k = k + 1
          end
          while k < to and B[k] == " " do
            k = k + 1
          end
          found = { kind = 1, mb = i, me = k }
          break
        end
      elseif CJK_END[ch] then
        local j = i
        while j < to and CJK_END[B[j]] do
          j = j + 1
        end
        local k = j
        while k < to and (B[k] == " " or B[k] == NBSP or B[k] == "\t" or B[k] == "\n") do
          k = k + 1
        end
        found = { kind = 1, mb = i, me = k }
        break
      end
      if ch == " " and B[i + 1] == " " and i + 1 < to then
        local k = i
        while k < to and B[k] == " " do
          k = k + 1
        end
        found = { kind = 2, mb = i, me = k }
        break
      end
      i = i + 1
    end
    if not found then
      break
    end
    local me = found.me
    local dstart
    if found.kind == 1 then
      local s = me
      while s > found.mb and B[s - 1] == " " do
        s = s - 1
      end
      dstart = math.min(me, s + 2)
    else
      local s = me
      while s > 1 and SKIP_BACK[B[s - 1]] do
        s = s - 1
      end
      local prev = B[s - 1]
      local keep
      if prev == "." or prev == "?" or prev == "!" then
        keep = 2
      elseif prev == "\n" then
        keep = 0
      else
        keep = 1
      end
      dstart = found.mb + keep
    end
    if dstart < me then
      local d = delete_range(B, dstart, me)
      to = to - d
      me = me - d
    end
    pt = me
  end
  return to
end

--- fill-region-as-paragraph on a chunk (array of chars). Returns the array.
local function fill_paragraph(B, fc, justify)
  local n = #B
  local p = 1
  while p <= n and (B[p] == " " or B[p] == "\t" or B[p] == "\n") do
    p = p + 1
  end
  local from_plus = p
  local from = bol(B, math.min(p, n + 1))
  -- delete all but one newline at the end
  local pt = #B + 1
  local oneleft = false
  while pt > from and B[pt - 1] == "\n" do
    if oneleft then
      table.remove(B, pt - 1)
      pt = pt - 1
    else
      pt = pt - 1
      oneleft = true
    end
  end
  local to = pt
  if not (to > from_plus) then
    return B
  end
  justify = justify or "left"
  local prefix = context_prefix(B, from, to, fc)
  local tabs = true
  if justify == "right" or justify == "center" then
    -- fill-indent-to-left-margin on the first line
    local k = from
    while k < to and is_sp(B[k]) do
      k = k + 1
    end
    to = to - delete_range(B, from, k)
  end
  -- fill-delete-prefix
  do
    local q = eol(B, from) + 1
    while q < to do
      local m = fpre_match(B, q, prefix, to)
      if m > 0 then
        to = to - delete_range(B, q, q + m)
      end
      q = eol(B, q) + 1
    end
    from = from + fpre_match(B, from, prefix, to)
  end
  -- fill-delete-newlines: sentences ending a line get an extra space
  do
    local k = from
    while k < to do
      if B[k] == "\n" then
        local c = B[k - 1]
        if k > from and not is_sp(c) then
          local j = k - 1
          while j >= from and CLOSERS[B[j]] do
            j = j - 1
          end
          if j >= from and SENTENCE_PUNCT[B[j]] then
            table.insert(B, k, " ")
            to = to + 1
            k = k + 1
          end
        end
      end
      k = k + 1
    end
    -- no space joins two words of a script written without spaces
    -- (fill-nospace-between-words-table)
    local k2 = from
    while k2 < to do
      if B[k2] == "\n" then
        local prev, nx = B[k2 - 1], B[k2 + 1]
        if (breakable(nx) or breakable(prev)) and (nospace(nx) or nospace(prev)) then
          table.remove(B, k2)
          to = to - 1
          k2 = k2 - 1
        end
      end
      k2 = k2 + 1
    end
    local s = from
    while s < to and is_sp(B[s]) do
      s = s + 1
    end
    for i = from, to - 1 do
      if B[i] == "\n" then
        B[i] = " "
      end
    end
    to = canonically_space(B, s, to)
    local t = to
    while t > from and is_sp(B[t - 1]) do
      t = t - 1
    end
    if t < to then
      to = to - delete_range(B, t, to)
    end
  end
  -- filling loop
  pt = from
  local opts = { prefix = prefix, adaptive = true, tabs = tabs }
  while pt < to do
    local linebeg = pt
    local lb = bol(B, pt)
    local le = eol(B, pt)
    -- move-to-column
    local q = lb
    local c = 0
    while q < le and c < fc do
      local ch = B[q]
      if ch == "\t" then
        c = c + 8 - (c % 8)
      else
        c = c + cwidth(ch)
      end
      q = q + 1
    end
    local cut = false
    if q < to and linebeg < to then
      if c <= fc then
        q = q + 1
      end
      q = move_to_break_point(B, q, linebeg, fc)
      while q < to and is_sp(B[q]) do
        q = q + 1
      end
      cut = q < to
    end
    if cut then
      local r = q
      while r > 1 and is_sp(B[r - 1]) do
        r = r - 1
      end
      table.insert(B, r, "\n")
      to = to + 1
      local nl = r + 1
      local k = nl
      while k < to and is_sp(B[k]) do
        k = k + 1
      end
      to = to - delete_range(B, nl, k)
      local after = nl
      if prefix and prefix ~= "" then
        local ins = insert_chars(B, nl, chars(prefix))
        to = to + ins
        after = nl + ins
      end
      if justify ~= "left" then
        local d = justify_line(B, bol(B, r), justify, fc, opts)
        to = to + d
        after = after + d
      end
      pt = after
    else
      if justify ~= "left" then
        local d = justify_line(B, bol(B, to), justify, fc, opts)
        to = to + d
      end
      break
    end
  end
  return B
end

--- org-ascii--fill-string: fill S to TEXT-WIDTH (fill-region with hard
--- newlines).
function M.fill_string(s, text_width, info, justify)
  if type(s) ~= "string" then
    return nil
  end
  if info and info.preserve_breaks then
    -- lint: allow gsub: HARD is "\1", defined in org.export.ascii
    s = s:gsub("\n", HARD)
  end
  local out = {}
  local start = 1
  while start <= #s do
    local h = s:find(HARD, start, true)
    local chunk
    if h then
      chunk = s:sub(start, h - 1) .. "\n"
      start = h + 1
    else
      chunk = s:sub(start)
      start = #s + 1
    end
    local B = fill_paragraph(chars(chunk), text_width, justify)
    out[#out + 1] = table.concat(B)
  end
  return table.concat(out)
end

--- org-ascii--justify-lines
function M.justify_lines(s, text_width, how)
  if how ~= "right" and how ~= "center" then
    return s
  end
  local B = chars(s)
  local pos = 1
  local opts = { tabs = false, adaptive = false }
  while pos <= #B do
    justify_line(B, pos, how, text_width, opts)
    pos = eol(B, pos) + 1
  end
  return table.concat(B)
end
