---@mod org.cite.activate Highlighting citations
---
--- The activate capability (org-cite-activate, org-cite-basic-activate):
--- the highlights of the citations in view, which the decoration provider
--- in org.cite.attach draws. Part of org.cite, which loads it.

local shared = require("org.cite.shared")

local M = require("org.cite")
local basic = M.basic
local opt = shared.opt

local MAX_SPAN = require("org.cite.attach").MAX_SPAN

--- Highlights of the citations in `s`: list of { begin, stop, group, priority }.
--- `known` is nil for the default fontification (org-cite-fontify-default).
local function default_marks(s)
  local out = {}
  for _, c in ipairs(M.citations(s)) do
    out[#out + 1] = { c.begin, c.stop, "OrgCite", 100 }
    for _, r in ipairs(c.references) do
      out[#out + 1] = { r.key_begin, r.key_end, "OrgCiteKey", 101 }
    end
  end
  return out
end

--- org-cite-basic-activate: keys not in the bibliography get the
--- OrgCiteKeyUnknown group (Emacs `error` face).
function basic.activate(s, bufnr)
  local keys = {}
  for _, k in ipairs(basic.all_keys(M.parse_bibliography(bufnr))) do
    keys[k] = true
  end
  local out = {}
  for _, c in ipairs(M.citations(s)) do
    out[#out + 1] = { c.begin, c.stop, "OrgCite", 100 }
    for _, r in ipairs(c.references) do
      out[#out + 1] = { r.key_begin, r.key_end, keys[r.key] and "OrgCiteKey" or "OrgCiteKeyUnknown", 101 }
    end
  end
  return out
end

--- Citation highlights for rows [top, bot] (0-based): { [row] = { {col, end_col, group, prio}... } }.
function M.marks(bufnr, top, bot)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local first = math.max(0, top - MAX_SPAN)
  local last = math.min(count - 1, bot + MAX_SPAN)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)
  local text = table.concat(lines, "\n")
  if not text:find("[cite", 1, true) then
    return {}
  end
  local starts, off = {}, 0
  for i, l in ipairs(lines) do
    starts[i] = off
    off = off + #l + 1
  end
  local function pos_of(p)
    local o = p - 1
    for i = #starts, 1, -1 do
      if o >= starts[i] then
        return first + i - 1, o - starts[i]
      end
    end
    return first, 0
  end
  local name = opt("activate_processor", "basic")
  local p = name and M.processors[name]
  local list
  if p and p.activate then
    local ok, res = pcall(p.activate, text, bufnr)
    list = ok and res or default_marks(text)
  else
    list = default_marks(text)
  end
  local rows = {}
  for _, m in ipairs(list) do
    local r1, c1 = pos_of(m[1])
    local r2, c2 = pos_of(m[2])
    for r = r1, r2 do
      if r >= top and r <= bot then
        local cs = r == r1 and c1 or 0
        local ce = r == r2 and c2 or #lines[r - first + 1]
        if ce > cs then
          rows[r] = rows[r] or {}
          table.insert(rows[r], { cs, ce, m[3], m[4] })
        end
      end
    end
  end
  return rows
end
