---@mod org.export.latex.transcode LaTeX transcoders: markup, blocks and footnotes
---
--- Creates the transcoder table and its first entries, from bold to
--- footnote-reference.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local delayed_footnotes = shared.delayed_footnotes
local lcfg = shared.lcfg
local text_markup = shared.text_markup
local wrap_label = shared.wrap_label

---------------------------------------------------------------------------
-- Transcoders
---------------------------------------------------------------------------

local T = {}

T.bold = function(_, contents, info)
  return text_markup(contents, "bold", info)
end
T.italic = function(_, contents, info)
  return text_markup(contents, "italic", info)
end
T.underline = function(_, contents, info)
  return text_markup(contents, "underline", info)
end
T["strike-through"] = function(_, contents, info)
  return text_markup(contents, "strike-through", info)
end
T.code = function(el, _, info)
  return text_markup(el.value, "code", info)
end
T.verbatim = function(el, _, info)
  return text_markup(el.value, "verbatim", info)
end

T["center-block"] = function(el, contents, info)
  return wrap_label(el, fmt("\\begin{center}\n%s\\end{center}", contents or ""), info)
end

T.clock = function(el, _, info)
  return "\\noindent"
    .. "\\textbf{CLOCK:} "
    .. fmt(
      info.latex_inactive_timestamp_format,
      ox.timestamp_translate(el.value) .. (el.duration and fmt(" (%s)", el.duration) or "")
    )
    .. "\\\\"
end

T.drawer = function(el, contents, info)
  local f = lcfg().format_drawer_function
  local output = type(f) == "function" and f(el.drawer_name, contents) or contents
  return wrap_label(el, output, info)
end

T["dynamic-block"] = function(el, contents, info)
  return wrap_label(el, contents, info)
end

T.entity = function(el)
  return (entities[el.name] or {})[1] or ("\\" .. el.name)
end

T["example-block"] = function(el, _, info)
  if nw(el.value) then
    local env = ox.read_attribute("attr_latex", el, "environment") or "verbatim"
    return wrap_label(el, fmt("\\begin{%s}\n%s\\end{%s}", env, ox.format_code_default(el, info), env), info)
  end
end

T["export-block"] = function(el)
  if el.back_end_type == "LATEX" or el.back_end_type == "TEX" then
    return table.concat(element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true })), "\n")
      .. "\n"
  end
end

T["export-snippet"] = function(el)
  local tr = (require("org.config").opts.export or {}).snippet_translation or {}
  if (tr[el.back_end] or el.back_end) == "latex" then
    return el.value
  end
end

T["fixed-width"] = function(el, _, info)
  return wrap_label(
    el,
    fmt(
      "\\begin{verbatim}\n%s\n\\end{verbatim}",
      table.concat(element.remove_indentation(vim.split(el.value, "\n", { plain = true })), "\n")
    ),
    info
  )
end

T["footnote-reference"] = function(el, _, info)
  local label = el.label
  local prev = ox.get_previous_element(el, info)
  local sep = (prev and prev.type == "footnote-reference") and info.latex_footnote_separator or ""
  if not ox.footnote_first_reference_p(el, info) then
    return sep .. fmt(info.latex_footnote_defined_format, M.label(ox.get_footnote_definition(el, info), info, true))
  end
  local parent_el = element.parent_element(el)
  if
    element.lineage(el, { ["footnote-reference"] = true, ["footnote-definition"] = true, ["table-cell"] = true })
    or (parent_el and parent_el.type == "item")
  then
    return sep .. "\\footnotemark"
  end
  local def = ox.get_footnote_definition(el, info)
  local lbl = ""
  if label then
    local other = element.map(info.parse_tree, "footnote-reference", function(f)
      if f ~= el and f.label == label then
        return f
      end
    end, { first_match = true, ignore = info.ignore })
    if other then
      lbl = trim(M.label(def, info, true, true))
    end
  end
  local body = trim(ox.data(def, info))
  local cmd = info.latex_default_footnote_command
  local i = 0
  local s = cmd:gsub("%%s", function()
    i = i + 1
    return i == 1 and body or lbl
  end)
  return sep .. s .. delayed_footnotes(def, info)
end

-- Locals the later parts share
shared.T = T
