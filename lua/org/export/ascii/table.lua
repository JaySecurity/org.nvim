---@mod org.export.ascii.table Plain text tables and the last transcoders
---
--- ascii-art-to-unicode, tables, timestamps and verse blocks; sets
--- M.transcoders.
---
--- Part of org.export.ascii, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local fmt = string.format

local HARD = shared.HARD
local T = shared.T
local build_caption = shared.build_caption
local chars = shared.chars
local indent_string = shared.indent_string
local inner_template = shared.inner_template
local swidth = shared.swidth
local template = shared.template
local utf8p = shared.utf8p

--- ascii-art-to-unicode (aa2u): every "-" and "|" becomes a light box
--- line, every "+" the junction its neighbours call for.
function M.aa2u(lines)
  local grid = {}
  for i, l in ipairs(lines) do
    grid[i] = vim.fn.split(l, "\\zs")
  end
  -- phase 1: components of each converted character
  local comp = {}
  for i, row in ipairs(grid) do
    comp[i] = {}
    for j, ch in ipairs(row) do
      if ch == "|" then
        row[j], comp[i][j] = "│", "V"
      elseif ch == "-" then
        row[j], comp[i][j] = "─", "H"
      end
    end
  end
  local GLYPH = {
    VH = "┼",
    DR = "┌",
    DL = "┐",
    UR = "└",
    UL = "┘",
    VR = "├",
    VL = "┤",
    UH = "┴",
    DH = "┬",
    U = "╵",
    D = "╷",
    L = "╴",
    R = "╶",
    V = "│",
    H = "─",
  }
  -- phase 2: what each "+" becomes, from the characters before the change
  local changes = {}
  for i, row in ipairs(grid) do
    for j, ch in ipairs(row) do
      if ch == "+" then
        local function ok(r, c, want)
          local x = grid[r] and grid[r][c]
          return x == "+" or (x and comp[r][c] == want)
        end
        local up, down = ok(i - 1, j, "V"), ok(i + 1, j, "V")
        local left, right = j > 1 and ok(i, j - 1, "H"), ok(i, j + 1, "H")
        local y = (up and down) and "V" or up and "U" or down and "D" or ""
        local x = (left and right) and "H" or left and "L" or right and "R" or ""
        changes[#changes + 1] = { i, j, GLYPH[y .. x] or "?" }
      end
    end
  end
  for _, c in ipairs(changes) do
    grid[c[1]][c[2]] = c[3]
  end
  local out = {}
  for i, row in ipairs(grid) do
    out[i] = table.concat(row)
  end
  return out
end

T.table = function(el, contents, info)
  local caption = build_caption(el, info)
  local above = info.ascii_caption_above
  local body
  if el.table_type == "org" then
    body = contents or ""
  else
    local lines = element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true }))
    if info.ascii_table_use_ascii_art and info.ascii_charset == "utf-8" then
      -- org-ascii-table-use-ascii-art: table.el art drawn with box characters
      lines = M.aa2u(lines)
      while #lines > 0 and not lines[#lines]:match("%S") do
        lines[#lines] = nil
      end
      lines[#lines] = lines[#lines] and (lines[#lines]:gsub("%s+$", "")) or nil
    end
    body = table.concat(lines, "\n") .. "\n"
  end
  return M.justify_element(
    ((caption and above) and (caption .. "\n") or "") .. body .. ((caption and not above) and caption or ""),
    el,
    info
  )
end

local function column_index(cell)
  for i, c in ipairs(cell.parent.contents) do
    if c == cell then
      return i
    end
  end
end

local function table_cell_width(cell, info)
  local row = cell.parent
  local tbl = row.parent
  local col_i = column_index(cell)
  info.ascii_table_cell_width_cache = info.ascii_table_cell_width_cache or {}
  local cache = info.ascii_table_cell_width_cache
  cache[tbl] = cache[tbl] or {}
  if cache[tbl][col_i] then
    return cache[tbl][col_i]
  end
  local widen = info.ascii_table_widen_columns
  local cookie = ox.table_cell_width(cell, info)
  local w
  if not widen and cookie then
    w = cookie
  else
    local maxw = 0
    for _, r in ipairs(tbl.contents) do
      if not info.ignore[r] then
        local c = r.contents[col_i]
        maxw = math.max(swidth(ox.data(c and c.contents or {}, info)), maxw)
      end
    end
    if not cookie then
      w = maxw
    elseif widen then
      w = math.max(cookie, maxw)
    else
      w = cookie
    end
  end
  cache[tbl][col_i] = w
  return w
end

T["table-cell"] = function(el, contents, info)
  local width = table_cell_width(el, info)
  if not info.ascii_table_widen_columns and swidth(contents or "") > width then
    local cs = chars(contents)
    contents = table.concat(cs, "", 1, math.max(0, width - 2)) .. "=>"
  end
  local data
  if contents then
    data = M.justify_lines(contents, width, ox.table_cell_alignment(el, info))
  end
  contents = (data or "") .. string.rep(" ", math.max(0, width - swidth(data or "")))
  local s = fmt(" %s ", contents)
  if ox.table_cell_borders(el, info).right then
    s = s .. (utf8p(info) and "│" or "|")
  end
  return s
end

T["table-row"] = function(el, contents, info)
  if el.row_type ~= "standard" then
    return nil
  end
  local u = utf8p(info)
  local first_cell
  for _, c in ipairs(el.contents) do
    if not info.ignore[c] then
      first_cell = c
      break
    end
  end
  local function build_hline(lcorner, horiz, vert, rcorner)
    local parts = {}
    for _, cell in ipairs(el.contents) do
      if not info.ignore[cell] then
        local width = table_cell_width(cell, info)
        local borders = ox.table_cell_borders(cell, info)
        local s = ""
        if borders.left and first_cell == cell then
          s = s .. lcorner
        end
        s = s .. string.rep(horiz, width + 2)
        if borders.right then
          if el.contents[#el.contents] == cell then
            s = s .. rcorner
          else
            s = s .. vert
          end
        end
        parts[#parts + 1] = s
      end
    end
    return table.concat(parts) .. "\n"
  end
  local borders = first_cell and ox.table_cell_borders(first_cell, info) or {}
  local s = ""
  if borders.top and (u or borders.above) then
    s = u and build_hline("┍", "━", "┯", "┑") or build_hline("+", "-", "+", "+")
  elseif borders.above then
    s = u and build_hline("├", "─", "┼", "┤") or build_hline("+", "-", "+", "+")
  end
  if borders.left then
    s = s .. (u and "│" or "|")
  end
  s = s .. (contents or "") .. "\n"
  if borders.bottom and (u or borders.below) then
    s = s .. (u and build_hline("┕", "━", "┷", "┙") or build_hline("+", "-", "+", "+"))
  end
  return s
end

T.timestamp = function(el, _, info)
  return M.plain_text(ox.timestamp_translate(el), info)
end

T["verse-block"] = function(el, contents, info)
  contents = contents and contents:gsub(HARD, "\n") or contents
  return indent_string(M.justify_element(contents, el, info), info.ascii_quote_margin)
end

T.template = template
T.inner_template = inner_template

M.transcoders = T
