---@mod org.extensions.transclusion.protect Keeping materialized text read-only
---
--- Text edited in place is put back, text whose keyword went is removed
--- with it, and text that lost its marks (deleted and put back, or a whole
--- buffer rewritten by a formatter) is found again by its keyword and
--- lines. Part of org.extensions.transclusion, which loads it.

local keyword = require("org.extensions.transclusion.keyword")
local shared = require("org.extensions.transclusion.shared")
local utils = require("org.utils")

local M = require("org.extensions.transclusion")

local api = vim.api
local ns_region, ns_line = M.ns_region, M.ns_line
local opts = shared.opts
local valid = shared.valid
local touch = shared.touch
local keep_modified = shared.keep_modified
local undojoin = shared.undojoin
local at_tip = shared.at_tip
local mark_lines = shared.mark_lines
local collect = shared.collect
local delete_rows = shared.delete_rows

-- Put a region's text back where it was edited in place: its marked lines
-- become the inserted text again, lines typed or pasted among them are
-- kept below it, and text joined to its last line (J) goes below too.
local function restore(buf, r)
  local data = r.data
  local n = #data.lines
  local cur = api.nvim_buf_get_lines(buf, r.s, r.e + 1, false)
  local keep = {}
  local last_own
  for i, l in ipairs(cur) do
    if r.own[r.s + i - 1] then
      last_own = i
    elseif data.lines[i] ~= l then
      keep[#keep + 1] = l
    end
  end
  local lo, expect = last_own and cur[last_own], data.lines[n]
  if lo and expect and #lo > #expect and lo:sub(1, #expect) == expect then
    local extra = lo:sub(#expect + 1):gsub("^%s+", "")
    if extra ~= "" then
      table.insert(keep, 1, extra)
    end
  end
  local new = vim.list_extend(vim.deepcopy(data.lines), keep)
  api.nvim_buf_set_lines(buf, r.s, r.e + 1, false, new)
  mark_lines(buf, r.id, r.s, n)
end

--- Check the materialized text. It is read-only, like in Emacs: text
--- edited in place is put back. Text whose keyword was deleted is
--- removed with it; text deleted as a whole leaves the keyword without
--- it. While undo or redo walk the history, the text they bring back is
--- kept as it is.
local function protect(buf)
  local st = M.buffers[buf]
  if not st or st.saving or not next(st.regions) or not valid(buf) then
    return
  end
  local list, dormant = collect(buf)
  local todo = {}
  for _, r in ipairs(list) do
    if not r.intact then
      todo[#todo + 1] = r
    end
  end
  -- text whose marks were lost (deleted and put back without undo) is
  -- taken back when it is exactly the text under its unchanged keyword
  local adopt = {}
  for _, r in ipairs(dormant) do
    if not r.gone and not r.data.removed and #r.data.lines > 0 then
      local n = #r.data.lines
      local got = api.nvim_buf_get_lines(buf, r.s - 1, r.s + n, false)
      if got[1] == r.data.kw and vim.deep_equal(vim.list_slice(got, 2), r.data.lines) then
        adopt[#adopt + 1] = r
      end
    end
  end
  if #todo == 0 and #adopt == 0 then
    return
  end
  for _, r in ipairs(adopt) do
    local marks = api.nvim_buf_get_extmarks(buf, ns_line, { r.s, 0 }, { r.s + #r.data.lines - 1, -1 }, {})
    local free = true
    for _, mk in ipairs(marks) do
      local o = st.owner[mk[1]]
      if o and o ~= r.id then
        local m = api.nvim_buf_get_extmark_by_id(buf, ns_line, mk[1], { details = true })
        free = free and (m[3] and m[3].invalid) or false
      end
    end
    if free then
      mark_lines(buf, r.id, r.s, #r.data.lines)
    end
  end
  if #todo == 0 then
    return
  end
  local tip = at_tip(buf)
  table.sort(todo, function(x, y)
    return x.s > y.s
  end)
  local restored = false
  keep_modified(buf, function()
    local joined = false
    local function join()
      if not joined and tip then
        undojoin(buf)
        joined = true
      end
    end
    for _, r in ipairs(todo) do
      local kw = not r.gone and api.nvim_buf_get_lines(buf, r.s - 1, r.s, false)[1]
      if not kw or not keyword.match(kw) then
        -- the keyword went: its text goes too
        local rows = {}
        for _, row in ipairs(r.rows) do
          if not st.cache or not st.cache.anchors[row] then
            rows[#rows + 1] = row
          end
        end
        if tip then
          join()
          delete_rows(buf, rows)
          r.data.removed = true
        end
      elseif not tip then
        -- undo brought this text back: it is the region's text now
        local lines = {}
        for _, row in ipairs(r.rows) do
          if r.own[row] then
            lines[#lines + 1] = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
          end
        end
        if #lines > 0 then
          r.data.lines = lines
        end
        r.data.kw = kw
      else
        join()
        local below, above = {}, {}
        for _, row in ipairs(r.stray) do
          if row > r.e then
            below[#below + 1] = row
          elseif row ~= r.s - 1 then
            above[#above + 1] = row
          end
        end
        delete_rows(buf, below)
        if kw ~= r.data.kw and kw:sub(1, #r.data.kw) == r.data.kw then
          -- the first line was joined to the keyword (J)
          api.nvim_buf_set_text(buf, r.s - 1, #r.data.kw, r.s - 1, #kw, {})
        end
        if r.e >= r.s then
          restore(buf, r)
          restored = true
        end
        delete_rows(buf, above)
      end
    end
  end)
  touch(st)
  if restored then
    utils.warn(
      "Transcluded text is read-only: edit its source with transclusion_edit (" .. (opts().edit_key or "") .. ")"
    )
  end
end

-- Text whose keyword and lines were all replaced (a formatter rewrote the
-- whole buffer) lost its marks: find it again by its keyword line and
-- text, and mark it.
local function adopt_gone(buf)
  local st = M.buffers[buf]
  local _, dormant = collect(buf)
  local anchors = st.cache and st.cache.anchors or {}
  local lines
  for _, r in ipairs(dormant) do
    local d = r.data
    if r.gone and not d.removed and #d.lines > 0 then
      lines = lines or api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l == d.kw and not anchors[i - 1] and vim.deep_equal(vim.list_slice(lines, i + 1, i + #d.lines), d.lines) then
          pcall(api.nvim_buf_del_extmark, buf, ns_region, r.id)
          local aid = api.nvim_buf_set_extmark(buf, ns_region, i - 1, 0, { invalidate = true })
          st.regions[aid], st.regions[r.id] = d, nil
          for _, id in ipairs(d.marks) do
            st.owner[id] = aid
          end
          mark_lines(buf, aid, i, #d.lines)
          anchors[i - 1] = aid
          break
        end
      end
    end
  end
end

shared.protect = protect
shared.adopt_gone = adopt_gone
