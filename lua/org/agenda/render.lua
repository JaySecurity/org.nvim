---@mod org.agenda.render Turning agenda blocks into buffer lines
---
--- Rendering is a pure function of (view, state, width): it returns lines,
--- highlight ranges and a line -> item map. The buffer side lives in
--- `org.agenda.view`. Lines follow `org-agenda-format-item`: a prefix built
--- from `agenda.prefix_format` (org-agenda-prefix-format), the headline
--- text, and the tags aligned to the right.
---
--- This file holds the extension hooks and the line builder; the rest
--- loads from org/agenda/render/: dates (day headers and spans), prefix
--- (org-agenda-prefix-format), item (item lines), limits
--- (org-agenda-max-*), clock (clock checks and the clock report), blocks
--- (what agenda and list blocks share), day (the agenda block), list
--- (the TODO, tags, search and stuck blocks) and view (a whole view).

-- Not compiled by the JIT: building an agenda over many files ran 3 to 5
-- times faster interpreted. Its loops are short (an entry's dates, its
-- tags) and branch a lot, so most traces aborted ("leaving loop", closures)
-- and the many that were compiled filled the machine-code area, which
-- flushed every compiled trace in Neovim over and over ("failed to allocate
-- mcode memory", on macOS arm64). See "Performance budgets" in
-- CONTRIBUTING.md.
if jit then
  jit.off(true, true)
end

local M = {}

-- The parts in org/agenda/render/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.agenda.render"] = M

--- Extra list block types (used by extensions): type -> `fun(block, ctx,
--- lopts)` returning `{ items, kind?, header?, sorted?, error? }`. `items`
--- are agenda items (see `org.agenda.items`); `sorted` keeps their order
--- unless the block sets `sorting`.
---@type table<string, fun(block: table, ctx: table, lopts: table): table>
M.sources = {}

--- Optional item grouping (the super_agenda extension). Called with the
--- builder, the sorted rows of a day or list block, the block, the render
--- context, `add(item)`, which adds one row as usual, and the day number
--- of an agenda day (nil for a list block); returns true when it added the
--- rows itself. nil renders the rows in order. A highlight in `b.hls` may
--- carry an extmark priority as its fifth element (default 110).
---@type (fun(b: table, rows: table[], block: table, ctx: table, add: fun(item: table), day?: integer): boolean)|nil
M.grouper = nil

---------------------------------------------------------------------------
-- Line builder
---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

function M.builder()
  return setmetatable({ lines = {}, hls = {}, items = {}, line_hls = {}, blocks = {} }, Builder)
end

--- The text of a line made of parts { text, group? } and its highlights
--- { start_col, end_col, group } (byte columns).
---@return string text, table[] hls
function M.line_text(parts)
  local text, hls = {}, {}
  local len = 0
  for _, p in ipairs(parts) do
    local s = p[1] or ""
    if p[2] and #s > 0 then
      hls[#hls + 1] = { len, len + #s, p[2] }
    end
    text[#text + 1] = s
    len = len + #s
  end
  return table.concat(text), hls
end

--- Add a line made of parts { text, group? }.
function Builder:add(parts, item, line_hl)
  local text, hls = M.line_text(parts)
  return self:add_line(text, hls, item, line_hl)
end

--- Add a line `text` with highlights { start_col, end_col, group, priority? }.
function Builder:add_line(text, hls, item, line_hl)
  local row = #self.lines
  for _, h in ipairs(hls) do
    self.hls[#self.hls + 1] = { row, h[1], h[2], h[3], h[4] }
  end
  self.lines[#self.lines + 1] = text
  if item then
    self.items[#self.lines] = item
  end
  if line_hl then
    self.line_hls[#self.lines] = line_hl
  end
  return #self.lines
end

function Builder:text(s, group)
  return self:add({ { s, group } })
end

require("org.agenda.render.dates")
require("org.agenda.render.prefix")
require("org.agenda.render.item")
require("org.agenda.render.limits")
require("org.agenda.render.clock")
require("org.agenda.render.blocks")
require("org.agenda.render.day")
require("org.agenda.render.list")
require("org.agenda.render.view")

return M
