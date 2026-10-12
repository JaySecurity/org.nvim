---@mod org.export.latex.table LaTeX tables and the last transcoders
---
--- Tables (org-latex-table and friends), targets, timestamps, verse
--- blocks and citations; sets M.transcoders.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local nw = ox.nw
local fmt = string.format

local T = shared.T
local caption_above_p = shared.caption_above_p
local delayed_footnotes = shared.delayed_footnotes
local template = shared.template
local translate = shared.translate
local wrap_label = shared.wrap_label

local function align_string(tbl, info, math)
  local a = ox.read_attribute("attr_latex", tbl, "align")
  if a then
    return a
  end
  local row
  for _, r in ipairs(tbl.contents) do
    if r.row_type == "standard" and not info.ignore[r] then
      row = r
      break
    end
  end
  if not row then
    return ""
  end
  local align = {}
  for _, cell in ipairs(row.contents) do
    if not info.ignore[cell] then
      local borders = ox.table_cell_borders(cell, info)
      if borders.left and #align == 0 then
        align[#align + 1] = "|"
      end
      if math then
        align[#align + 1] = "c"
      else
        align[#align + 1] = ({ left = "l", right = "r", center = "c" })[ox.table_cell_alignment(cell, info)]
      end
      if borders.right then
        align[#align + 1] = "|"
      end
    end
  end
  return table.concat(align)
end

local function decorate_table(tbl_str, attr, caption, above, info)
  local float = attr.float
  local env
  if not float and vim.tbl_contains(attr._keys, "float") then
    env = nil
  elseif float == "sidewaystable" or float == "sideways" then
    env = "sidewaystable"
  elseif float == "multicolumn" then
    env = "table*"
  elseif float == "t" then
    env = "table"
  elseif float then
    env = float
  elseif nw(caption) then
    env = "table"
  end
  local placement = attr.placement or fmt("[%s]", info.latex_default_figure_position)
  local center
  if vim.tbl_contains(attr._keys, "center") then
    center = attr.center
  else
    center = info.latex_tables_centered
  end
  local fontsize = attr.font and (attr.font .. "\n") or nil
  local pre, post
  if env then
    pre = fmt("\\begin{%s}%s\n", env, placement)
      .. (above and caption or "")
      .. (center and "\\centering\n" or "")
      .. (fontsize or "")
    post = (above and "" or ("\n" .. caption)) .. fmt("\n\\end{%s}", env)
  elseif caption and caption ~= "" then
    pre = (center and "\\begin{center}\n" or "")
      .. (above and caption or "")
      .. ((fontsize and center) and fontsize or (fontsize and ("{" .. fontsize) or ""))
    post = (above and "" or ("\n" .. caption))
      .. (center and "\n\\end{center}" or "")
      .. ((fontsize and not center) and "}" or "")
  elseif center then
    pre = "\\begin{center}\n" .. (fontsize or "")
    post = "\n\\end{center}"
  elseif fontsize then
    pre = "{" .. fontsize
    post = "}"
  else
    pre, post = "", ""
  end
  return pre .. tbl_str .. post
end

local function org_table(tbl, contents, info)
  local attr = ox.read_attribute("attr_latex", tbl)
  local alignment = align_string(tbl, info)
  local opt = attr.options
  local env = attr.environment or info.latex_default_table_environment
  local width = ""
  if attr.width then
    if env == "tabular" or env == "longtable" then
      width = ""
    elseif env == "tabu" or env == "longtabu" then
      width = fmt(attr.spread and " spread %s " or " to %s ", attr.width)
    else
      width = fmt("{%s}", attr.width)
    end
  end
  local caption = M.caption_label_string(tbl, info)
  local above = caption_above_p(tbl, info)
  if env == "longtable" or env == "longtabu" then
    local fontsize = attr.font and (attr.font .. "\n") or nil
    return (fontsize and ("{" .. fontsize) or "")
      .. fmt("\\begin{%s}%s{%s}\n", env, width, alignment)
      .. ((above and nw(caption)) and (caption .. "\\\\\n") or "")
      .. contents
      .. (((not above) and nw(caption)) and (caption .. "\\\\\n") or "")
      .. fmt("\\end{%s}", env)
      .. (fontsize and "}" or "")
  end
  local output =
    fmt("\\begin{%s}%s%s{%s}\n%s\\end{%s}", env, opt and fmt("[%s]", opt) or "", width, alignment, contents, env)
  return decorate_table(output, attr, caption, above, info)
end

local function math_table(tbl, info)
  local attr = ox.read_attribute("attr_latex", tbl)
  local env = attr.environment or info.latex_default_table_environment
  local macros = { bordermatrix = "\\cr", qbordermatrix = "\\cr", kbordermatrix = "\\\\" }
  local rows = {}
  for _, row in ipairs(tbl.contents) do
    if not info.ignore[row] then
      if row.row_type == "rule" then
        rows[#rows + 1] = "\\hline"
      else
        local cells = {}
        for _, cell in ipairs(row.contents) do
          if not info.ignore[cell] then
            cells[#cells + 1] = element.interpret(cell.contents)
          end
        end
        rows[#rows + 1] = table.concat(cells, "&") .. (macros[env] or "\\\\") .. "\n"
      end
    end
  end
  local contents = table.concat(rows)
  local body
  if env == "array" or env == "tabular" then
    body = fmt("\\begin{%s}{%s}\n%s\\end{%s}", env, align_string(tbl, info, true), contents, env)
  elseif macros[env] then
    body = fmt("\\%s%s{\n%s}", env, attr["math-arguments"] or "", contents)
  else
    body = fmt("\\begin{%s}\n%s\\end{%s}", env, contents, env)
  end
  return (attr["math-prefix"] or "") .. body .. (attr["math-suffix"] or "")
end

T.table = function(el, contents, info)
  if el.table_type == "table.el" then
    local attr = ox.read_attribute("attr_latex", el)
    -- The tabular table.el generates (org-latex--table.el-table); `:rmlines`
    -- is ignored as in Emacs, whose loop removing rules never runs.
    local lines = vim.split((el.value:gsub("\n$", "")), "\n", { plain = true })
    local out = require("org.table.el").to_latex(lines) or ("\\begin{verbatim}\n" .. el.value .. "\\end{verbatim}")
    return decorate_table(out, attr, M.caption_label_string(el, info), caption_above_p(el, info), info)
  end
  local mode = ox.read_attribute("attr_latex", el, "mode") or info.latex_default_table_mode
  if mode == "verbatim" then
    local rows = {}
    for _, r in ipairs(el.contents) do
      if r.row_type == "rule" then
        rows[#rows + 1] = "|-"
      else
        local cells = {}
        for _, c in ipairs(r.contents) do
          cells[#cells + 1] = " " .. element.interpret(c.contents) .. " |"
        end
        rows[#rows + 1] = "|" .. table.concat(cells)
      end
    end
    return fmt("\\begin{verbatim}\n%s\n\\end{verbatim}", require("org.export.org").align_table_lines(rows))
  elseif mode == "math" or mode == "inline-math" then
    return math_table(el, info)
  elseif mode == "tabbing" then
    local attr_align = ox.read_attribute("attr_latex", el, "align")
    local align = attr_align
    if not align then
      local count = 0
      for _, r in ipairs(el.contents) do
        if r.row_type == "standard" then
          count = #r.contents
          break
        end
      end
      local sep = fmt("\\hspace{%s\\textwidth} \\= ", tostring((1.0 / count) - 0.01))
      align = string.rep(sep, count) .. "\\kill"
    end
    return fmt("\\begin{%s}\n%s\n%s\\end{%s}", "tabbing", align, contents or "", "tabbing")
  end
  return org_table(el, contents or "", info) .. delayed_footnotes(el, info)
end

T["table-cell"] = function(el, contents, info)
  local mode = ox.read_attribute("attr_latex", element.lineage(el, "table"), "mode")
  local sci = info.latex_table_scientific_notation
  local out = contents or ""
  if contents and sci then
    local m, e = contents:match("^([-+]?%d[%d.]*)[eE]([-+]?%d+)$")
    if m then
      out = fmt(sci, m, e)
    end
  end
  if ox.get_next_element(el, info) then
    out = out .. (mode == "tabbing" and " \\> " or " & ")
  end
  return out
end

T["table-row"] = function(el, contents, info)
  local tbl = el.parent
  local attr = ox.read_attribute("attr_latex", tbl)
  local booktabs
  if vim.tbl_contains(attr._keys, "booktabs") then
    booktabs = attr.booktabs
  else
    booktabs = info.latex_tables_booktabs
  end
  local env = attr.environment or info.latex_default_table_environment
  local longtable = env == "longtable" or env == "longtabu"
  if el.row_type == "rule" then
    if not booktabs then
      return "\\hline"
    elseif not ox.get_previous_element(el, info) then
      return "\\toprule"
    elseif not ox.get_next_element(el, info) then
      return "\\bottomrule"
    elseif longtable and ox.table_row_ends_header_p(ox.get_previous_element(el, info), info) then
      return ""
    end
    return "\\midrule"
  end
  info.latex_table_head_cache = info.latex_table_head_cache or {}
  if ox.table_row_in_header_p(el, info) then
    local cache = info.latex_table_head_cache
    if cache[tbl] then
      cache[tbl] = cache[tbl] .. "\\\\\n" .. (contents or "")
    else
      cache[tbl] = contents or ""
    end
  end
  local s = ((booktabs and not ox.get_previous_element(el, info)) and "\\toprule\n" or "")
    .. (contents or "")
    .. "\\\\\n"
  if longtable and ox.table_row_ends_header_p(el, info) then
    local _, columns = ox.table_dimensions(element.lineage(el, "table"), info)
    s = s
      .. fmt(
        "%s\n\\endfirsthead\n\\multicolumn{%d}{l}{%s} \\\\\n%s\n%s \\\\\n\n%s\n\\endhead\n%s\\multicolumn{%d}{r}{%s} \\\\\n\\endfoot\n\\endlastfoot",
        booktabs and "\\midrule" or "\\hline",
        columns,
        translate("Continued from previous page", info),
        (not ox.table_row_starts_header_p(el, info)) and "" or (booktabs and "\\toprule\n" or "\\hline\n"),
        info.latex_table_head_cache[tbl] or "",
        booktabs and "\\midrule" or "\\hline",
        booktabs and "\\midrule" or "\\hline",
        columns,
        translate("Continued on next page", info)
      )
  elseif booktabs and not ox.get_next_element(el, info) then
    s = s .. "\\bottomrule"
  end
  return s
end

T.target = function(el, _, info)
  return fmt("\\label{%s}", M.label(el, info))
end

T.timestamp = function(el, _, info)
  local value = M.plain_text(ox.timestamp_translate(el), info)
  local t = el.ts_type
  local f
  if t == "active" or t == "active-range" then
    f = info.latex_active_timestamp_format
  elseif t == "inactive" or t == "inactive-range" then
    f = info.latex_inactive_timestamp_format
  else
    f = info.latex_diary_timestamp_format
  end
  return (f:gsub("%%s", function()
    return value
  end))
end

T["verse-block"] = function(el, contents, info)
  local lin = ox.read_attribute("attr_latex", el, "lines")
  local latcode = ox.read_attribute("attr_latex", el, "latexcode")
  local cent = ox.read_attribute("attr_latex", el, "center")
  local attr = (cent and "[\\versewidth]" or "")
    .. (lin and fmt("\n\\poemlines{%s}", lin) or "")
    .. (latcode and fmt("\n%s", latcode) or "")
  local lit = ox.read_attribute("attr_latex", el, "literal")
  local vw = ox.read_attribute("attr_latex", el, "versewidth")
  local vwidth = vw and fmt("\\settowidth{\\versewidth}{%s}\n", vw) or ""
  local linreset = lin and "\n\\poemlines{0}" or ""
  contents = contents or ""
  local body = lit and contents or ((contents:gsub("^[ \t\n]*", ""):gsub("[ \t\n]*$", "")) .. "\n")
  return wrap_label(el, fmt("%s\\begin{verse}%s\n%s\\end{verse}%s", vwidth, attr, body, linreset), info)
end

T.citation = function(el, _, info)
  return require("org.export.cite").export_citation(el, info, "latex")
end

T.template = template

M.transcoders = T
