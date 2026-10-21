---@mod org.cite.region Buffer text around the cursor
---
--- The paragraph around a line as one string, points in it, the citation
--- context at the cursor, and editing that text with Emacs marker
--- semantics for the cursor. Part of org.cite, which loads it.

local shared = require("org.cite.shared")

local M = require("org.cite")

local MAX_SPAN = require("org.cite.attach").MAX_SPAN

local function paragraph_bounds(lines_of, row, count)
  local function stop_line(l)
    return l == nil or l:match("^%s*$") or l:match("^%*+ ") or l:match("^%s*#%+")
  end
  local here = lines_of(row)
  if here:match("^%*+ ") then
    return row, row
  end
  local first, last = row, row
  while first > 1 and row - first < MAX_SPAN and not stop_line(lines_of(first - 1)) do
    first = first - 1
  end
  while last < count and last - row < MAX_SPAN and not stop_line(lines_of(last + 1)) do
    last = last + 1
  end
  return first, last
end

---@class org.cite.Region
---@field bufnr integer
---@field first integer first line (1-based)
---@field last integer
---@field text string lines joined with "\n"
---@field starts integer[] offset of each line in `text` (0-based)

--- The paragraph around line `row` of the buffer, as one string.
---@return org.cite.Region
function M.region(bufnr, row)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local cache = {}
  local function lines_of(r)
    if r < 1 or r > count then
      return nil
    end
    if not cache[r] then
      cache[r] = vim.api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1]
    end
    return cache[r]
  end
  local first, last = paragraph_bounds(lines_of, row, count)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  local starts, off = {}, 0
  for i, l in ipairs(lines) do
    starts[i] = off
    off = off + #l + 1
  end
  return { bufnr = bufnr, first = first, last = last, text = table.concat(lines, "\n"), starts = starts }
end

--- Point in the region's text for (row, col0).
function M.point(region, row, col)
  return region.starts[row - region.first + 1] + col + 1
end

--- Buffer (row, col0) of point `pos` in the region's text.
function M.position(region, pos)
  local off = pos - 1
  for i = #region.starts, 1, -1 do
    if off >= region.starts[i] then
      return region.first + i - 1, off - region.starts[i]
    end
  end
  return region.first, 0
end

--- The citation context at the cursor: { type, citation, reference, region, point }.
function M.at_cursor(bufnr, row, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not row then
    row, col = unpack(vim.api.nvim_win_get_cursor(0))
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  local region = M.region(bufnr, row)
  local pos = M.point(region, row, math.min(col, #line))
  local t, c, r = M.context_in(region.text, pos)
  return { type = t, citation = c, reference = r, region = region, point = pos }
end

--- Is the cursor on a citation or citation reference?
function M.at_point(bufnr, row, col)
  local ctx = M.at_cursor(bufnr, row, col)
  return ctx.type ~= nil and ctx or nil
end

---------------------------------------------------------------------------
-- Editing the region with Emacs marker semantics for the cursor
---------------------------------------------------------------------------

local Edit = {}
Edit.__index = Edit

local function new_edit(region, point)
  return setmetatable({ region = region, text = region.text, point = point }, Edit)
end

--- insert (before_markers: insert-before-markers, which moves a point
--- sitting at `pos`).
function Edit:insert(pos, str, before_markers)
  self.text = self.text:sub(1, pos - 1) .. str .. self.text:sub(pos)
  if self.point > pos or (self.point == pos and before_markers) then
    self.point = self.point + #str
  end
end

function Edit:delete(a, b)
  if b <= a then
    return
  end
  self.text = self.text:sub(1, a - 1) .. self.text:sub(b)
  if self.point >= b then
    self.point = self.point - (b - a)
  elseif self.point > a then
    self.point = a
  end
end

--- Write the text back and move the cursor to the tracked point.
function Edit:apply()
  local region = self.region
  local lines = vim.split(self.text, "\n", { plain = true })
  if self.drop_all then
    lines = {}
  end
  vim.api.nvim_buf_set_lines(region.bufnr, region.first - 1, region.last, false, lines)
  if #lines == 0 then
    lines = { "" }
  end
  local starts, off = {}, 0
  for i, l in ipairs(lines) do
    starts[i] = off
    off = off + #l + 1
  end
  local new_region = { bufnr = region.bufnr, first = region.first, last = region.first + #lines - 1, starts = starts }
  local row, col = M.position(new_region, self.point)
  if vim.api.nvim_get_current_buf() == region.bufnr then
    pcall(vim.api.nvim_win_set_cursor, 0, { row, col })
  end
end

shared.new_edit = new_edit
