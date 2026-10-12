---@mod org.export.html.table HTML tables and the last transcoders
---
--- Tables, targets, timestamps, verse blocks and citations; sets
--- M.transcoders.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local trim = ox.trim
local fmt = string.format

local T = shared.T
local anchor = shared.anchor
local attribute_string = shared.attribute_string
local close_tag = shared.close_tag
local encode = shared.encode
local format_timestamp = shared.format_timestamp
local has_caption = shared.has_caption
local html5_p = shared.html5_p
local inner_template = shared.inner_template
local set_attr = shared.set_attr
local template = shared.template
local translate = shared.translate

T["table-cell"] = function(el, contents, info)
  local row = el.parent
  local tbl = element.lineage(el, "table")
  local attrs = ""
  if info.html_table_align_individual_fields then
    attrs = fmt(' class="org-%s"', ox.table_cell_alignment(el, info))
  end
  if not contents or trim(contents) == "" then
    contents = "&nbsp;"
  end
  if ox.table_has_header_p(tbl, info) and ox.table_row_group(row, info) == 1 then
    local h = info.html_table_header_tags
    return "\n" .. fmt(h[1], "col", attrs) .. contents .. h[2]
  end
  if info.html_table_use_header_tags_for_first_column then
    local _, col = ox.table_cell_address(el, info)
    if col == 0 then
      local h = info.html_table_header_tags
      return "\n" .. fmt(h[1], "row", attrs) .. contents .. h[2]
    end
  end
  local d = info.html_table_data_tags
  return "\n" .. fmt(d[1], attrs) .. contents .. d[2]
end

T["table-row"] = function(el, contents, info)
  if el.row_type ~= "standard" then
    return nil
  end
  local group = ox.table_row_group(el, info)
  local start_p = ox.table_row_starts_rowgroup_p(el, info)
  local end_p = ox.table_row_ends_rowgroup_p(el, info)
  local open_tag = info.html_table_row_open_tag
  local close = info.html_table_row_close_tag
  if type(open_tag) == "function" then
    open_tag = open_tag(ox.table_row_number(el, info), group, start_p, end_p)
  end
  if type(close) == "function" then
    close = close(ox.table_row_number(el, info), group, start_p, end_p)
  end
  local tags
  if group ~= 1 then
    tags = { "<tbody>", "\n</tbody>" }
  elseif ox.table_has_header_p(element.lineage(el, "table"), info) then
    tags = { "<thead>", "\n</thead>" }
  else
    tags = { "<tbody>", "\n</tbody>" }
  end
  return (start_p and tags[1] or "")
    .. "\n"
    .. open_tag
    .. (contents or "")
    .. "\n"
    .. close
    .. (end_p and tags[2] or "")
end

local function first_row_data_cells(tbl, info)
  local row
  for _, r in ipairs(tbl.contents) do
    if r.row_type ~= "rule" and not info.ignore[r] then
      row = r
      break
    end
  end
  if not row then
    return {}
  end
  local cells = row.contents
  if ox.table_has_special_column_p(tbl) then
    cells = vim.list_slice(cells, 2)
  end
  return cells
end

T.table = function(el, contents, info)
  if el.table_type == "table.el" then
    return trim(M.table_el(el) or "")
  end
  local caption = ox.get_caption(el)
  local number = ox.get_ordinal(el, info, nil, has_caption)
  local attrs = { _keys = { "id" }, id = M.reference(el, info, true) }
  if not html5_p(info) then
    for _, kv in ipairs(info.html_table_attributes or {}) do
      set_attr(attrs, kv[1], kv[2])
    end
  end
  local user = ox.read_attribute("attr_html", el)
  for _, k in ipairs(user._keys) do
    set_attr(attrs, k, user[k])
  end
  local a = attribute_string(attrs)
  local specs = {}
  for _, cell in ipairs(first_row_data_cells(el, info)) do
    local s = ""
    if ox.table_cell_starts_colgroup_p(cell, info) then
      s = s .. "\n<colgroup>"
    end
    s = s .. "\n" .. close_tag("col", " " .. fmt('class="org-%s"', ox.table_cell_alignment(cell, info)), info)
    if ox.table_cell_ends_colgroup_p(cell, info) then
      s = s .. "\n</colgroup>"
    end
    specs[#specs + 1] = s
  end
  local cap = ""
  if caption then
    cap = fmt(
      info.html_table_caption_above and '<caption class="t-above">%s</caption>'
        or '<caption class="t-bottom">%s</caption>',
      '<span class="table-number">'
        .. (translate("Table %d:", info):gsub("%%d", tostring(number)))
        .. "</span> "
        .. ox.data(caption, info)
    )
  end
  return fmt(
    "<table%s>\n%s\n%s\n%s</table>",
    a == "" and "" or (" " .. a),
    cap,
    table.concat(specs, "\n"),
    contents or ""
  )
end

--- table.el tables: the HTML table.el generates (org-html-table--table.el-table),
--- or preformatted text when the grid cannot be read.
function M.table_el(el)
  local lines = vim.split((el.value:gsub("\n$", "")), "\n", { plain = true })
  return require("org.table.el").to_html(lines) or ('<pre class="example">\n' .. encode(el.value) .. "</pre>")
end

T.target = function(el, _, info)
  return anchor(M.reference(el, info), nil, nil, info)
end

T.timestamp = function(el, _, info)
  local copy = setmetatable({ post_blank = 0 }, { __index = el })
  return fmt('<span class="timestamp-wrapper">%s</span>', format_timestamp(copy, info))
end

T["verse-block"] = function(_, contents, info)
  local br = close_tag("br", nil, info)
  contents = contents or ""
  -- each newline, with a <br> before it or the blanks before it (not
  -- those before the <br>: "plan <br />"), becomes a <br> and a newline
  contents = contents:gsub(vim.pesc(br) .. "[ \t]*\n", "\0"):gsub("[ \t]*\n", "\0")
  -- lint: allow gsub: a <br> tag
  contents = contents:gsub("%z", br .. "\n")
  contents = contents:gsub("\n([ \t]+)", function(ws)
    return "\n" .. string.rep("&nbsp;", #ws)
  end)
  contents = contents:gsub("^([ \t]+)", function(ws)
    return string.rep("&nbsp;", #ws)
  end)
  return fmt('<p class="verse">\n%s</p>', contents)
end

T.citation = function(el, _, info)
  return require("org.export.cite").export_citation(el, info, "html")
end

T.template = template
T.inner_template = inner_template

M.transcoders = T
