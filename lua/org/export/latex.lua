---@mod org.export.latex LaTeX back-end (port of Emacs ox-latex.el)
---
--- This file holds the configuration, the escaping and label helpers the
--- whole back-end shares; the rest loads from org/export/latex/: math
--- (math block and matrix filters), preamble (classes, packages, header),
--- engraved (engraved source blocks), template, transcode (markup, blocks,
--- footnotes), headline, elements (rules to line breaks), link (links and
--- inline images), text (plain text and text blocks), src (source blocks),
--- table (tables and the last transcoders), backend (options and the
--- back-end) and compile (PDF compilation).

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")
local data = require("org.export.latex_data")

local M = {}
-- The parts in org/export/latex/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.export.latex"] = M

M.extension = "tex"

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local function lcfg()
  return (require("org.config").opts.export or {}).latex or {}
end

--- String replacement without pattern characters in the replacement.
local function replace_first(s, pat, repl)
  local a, b = s:find(pat)
  if not a then
    return s, false
  end
  return s:sub(1, a - 1) .. repl .. s:sub(b + 1), true
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function protect_text(text)
  return (text:gsub("([\\{}%$%%&_#~%^])", "\\%1"))
end
M.protect_text = protect_text

local function protect_texttt(text)
  local out = {}
  local i = 1
  while i <= #text do
    local two = text:sub(i, i + 1)
    local c = text:sub(i, i)
    if two == "--" then
      out[#out + 1] = "-{}-{}"
      i = i + 2
    elseif two == "<<" then
      out[#out + 1] = "<{}<{}"
      i = i + 2
    elseif two == ">>" then
      out[#out + 1] = ">{}>{}"
      i = i + 2
    elseif c == "\\" then
      out[#out + 1] = "\\textbackslash{}"
      i = i + 1
    elseif c == "~" then
      out[#out + 1] = "\\textasciitilde{}"
      i = i + 1
    elseif c == "^" then
      out[#out + 1] = "\\textasciicircum{}"
      i = i + 1
    elseif c:match("[{}%$%%&_#]") then
      out[#out + 1] = "\\" .. c
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return "\\texttt{" .. table.concat(out) .. "}"
end
M.protect_texttt = protect_texttt

local function find_verb_separator(s)
  local ll = "~,./?;':\"|!@#%^&-_=+abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ<>()[]{}"
  for i = 1, #ll do
    local c = ll:sub(i, i)
    if not s:find(c, 1, true) then
      return c
    end
  end
end

local function text_markup(text, markup, info)
  local f = info.latex_text_markup_alist[markup]
  if f == nil then
    return text
  elseif f == "verb" then
    local sep = find_verb_separator(text)
    return "\\verb" .. sep .. text:gsub("\n", " ") .. sep
  elseif f == "protectedtexttt" then
    return protect_texttt(text)
  end
  return (f:gsub("%%s", function()
    return text
  end))
end
M.text_markup = text_markup

local MATH_ENVS = {
  "equation",
  "eqnarray",
  "math",
  "displaymath",
  "align",
  "gather",
  "multline",
  "flalign",
  "alignat",
  "xalignat",
  "xxalignat",
  "subequations",
  "dmath",
  "dseries",
  "dgroup",
  "darray",
  "empheq",
}
local function math_env_p(value)
  local env = (value or ""):match("^[ \t]*\\begin{([^}]+)}")
  if not env then
    return false
  end
  env = env:gsub("%*$", "")
  return vim.tbl_contains(MATH_ENVS, env)
end
M.math_env_p = math_env_p

local function caption_above_p(el, info)
  local above = info.latex_caption_above
  if type(above) ~= "table" then
    return above
  end
  local t = el.type == "link" and "image" or el.type
  return vim.tbl_contains(above, t)
end

function M.label(datum, info, force, full)
  local t = datum.type
  local user
  if t == "headline" or t == "inlinetask" then
    user = datum.props and datum.props.CUSTOM_ID
  elseif t == "target" then
    user = datum.value
  else
    user = datum.name or (datum.results and datum.results[1])
    if type(user) ~= "string" then
      user = nil
    end
  end
  local label
  if user or force then
    if user and info.latex_prefer_user_labels then
      label = user
    else
      local prefix = ""
      if t == "headline" then
        prefix = "sec:"
      elseif t == "table" then
        prefix = "tab:"
      elseif t == "latex-environment" then
        prefix = math_env_p(datum.value) and "eq:" or ""
      elseif t == "latex-matrices" then
        prefix = "eq:"
      elseif t == "paragraph" then
        prefix = datum.caption and "fig:" or ""
      elseif t == "src-block" then
        prefix = "lst:"
      end
      label = prefix .. ox.get_reference(datum, info)
    end
  end
  if not full then
    return label
  end
  if label then
    return fmt("\\label{%s}%s", label, t == "target" and "" or "\n")
  end
  return ""
end

local function environment_type(el)
  local value = el.value or ""
  local env = value:match("\\begin{([%w%*]+)}") or ""
  if math_env_p(value) then
    return "math"
  end
  for _, e in ipairs({ "table", "longtable", "tabular", "tabu", "longtabu" }) do
    if env:find(e, 1, true) then
      return "table"
    end
  end
  if env:find("figure", 1, true) then
    return "image"
  end
  for _, e in ipairs({ "lstlisting", "listing", "verbatim", "minted" }) do
    if env:find(e, 1, true) then
      return "src-block"
    end
  end
  return "special-block"
end

function M.caption_label_string(el, info)
  local label = M.label(el, info, nil, true)
  local main = ox.get_caption(el)
  local attr = ox.read_attribute("attr_latex", el)
  local t = el.type
  local backend = info.latex_src_block_backend
  local nonfloat = (vim.tbl_contains(attr._keys, "float") and not attr.float and main)
    or (t == "src-block" and not attr.float and (backend == "verbatim" or backend == nil))
  local short = ox.get_caption(el, true)
  if nw(attr.caption) then
    return attr.caption .. "\n"
  end
  if not main and label == "" then
    return ""
  end
  if not main then
    return label
  end
  local tt = t == "latex-environment" and environment_type(el) or t
  local env = ""
  if nonfloat then
    if tt == "paragraph" or tt == "image" or tt == "special-block" then
      env = "figure"
    elseif tt == "src-block" then
      env = (backend ~= "verbatim" and backend ~= nil) and "listing" or "figure"
    else
      env = tt
    end
  end
  return fmt(
    nonfloat and "\\captionof{%s}%s{%s%s}\n" or "\\caption%s%s{%s%s}\n",
    env,
    short and fmt("[%s]", ox.data(short, info)) or "",
    trim(label),
    ox.data(main, info)
  )
end

local function wrap_label(el, output, info)
  local label = M.label(el, info)
  if not (nw(output) and label) then
    return output
  end
  return fmt("\\phantomsection\n\\label{%s}\n", label) .. output
end

local function translate(s, info)
  return ox.translate(s, "latex", info)
end

local function make_option_string(options, sep)
  local parts = {}
  for _, pair in ipairs(options or {}) do
    local key = pair[1]
    local value = pair[2]
    parts[#parts + 1] = key .. (value and ("=" .. (value:find("[%[%]]") and fmt("{%s}", value) or value)) or "")
  end
  return table.concat(parts, sep or ",")
end
M.make_option_string = make_option_string

--- Footnote definitions of references inside ELEMENT as \footnotetext.
local function delayed_footnotes(el, info)
  local all = {}
  local function search(d)
    element.map(d, "footnote-reference", function(ref)
      if ox.footnote_first_reference_p(ref, info) then
        all[#all + 1] = ref
        if ref.fn_type == "standard" then
          search(ox.get_footnote_definition(ref, info))
        end
      end
    end, { ignore = info.ignore })
  end
  search(el)
  local out = {}
  for _, ref in ipairs(all) do
    local def = ox.get_footnote_definition(ref, info)
    out[#out + 1] = fmt(
      "\\footnotetext[%d]{%s%s}",
      ox.get_footnote_number(ref, info),
      trim(M.label(def, info, true, true)),
      trim(ox.data(def, info))
    )
  end
  return table.concat(out)
end

local function language_name(info)
  local lang = info.language
  local plist = data.languages[lang]
  return plist and plist.lang_name or lang
end

local function capitalize(s)
  return (s:gsub("(%w)(%w*)", function(a, b)
    return a:upper() .. b:lower()
  end))
end

local function format_spec(info)
  local lang = language_name(info) or ""
  return {
    a = info.with_author and ox.data(info.author, info) or "",
    t = info.with_title and ox.data(info.title, info) or "",
    s = info.with_title and ox.data(info.subtitle, info) or "",
    k = ox.data(M.wrap_math_block(info.keywords_latex, info), info),
    d = ox.data(M.wrap_math_block(info.description_latex, info), info),
    c = info.with_creator and (info.creator or "") or "",
    l = lang,
    L = capitalize(lang),
    D = (function()
      local d = ox.get_date(info)
      return type(d) == "string" and d or ox.data(d, info)
    end)(),
  }
end

local function format_spec_apply(s, spec)
  return (
    s:gsub("%%(.)", function(c)
      if c == "%" then
        return "%"
      end
      return spec[c] or ("%" .. c)
    end)
  )
end

-- Locals the parts below share
local shared = require("org.export.latex.shared")
shared.lcfg = lcfg
shared.protect_text = protect_text
shared.protect_texttt = protect_texttt
shared.find_verb_separator = find_verb_separator
shared.text_markup = text_markup
shared.caption_above_p = caption_above_p
shared.environment_type = environment_type
shared.wrap_label = wrap_label
shared.translate = translate
shared.make_option_string = make_option_string
shared.delayed_footnotes = delayed_footnotes
shared.format_spec = format_spec
shared.format_spec_apply = format_spec_apply

require("org.export.latex.math")
require("org.export.latex.preamble")
require("org.export.latex.engraved")
require("org.export.latex.template")
require("org.export.latex.transcode")
require("org.export.latex.headline")
require("org.export.latex.elements")
require("org.export.latex.link")
require("org.export.latex.text")
require("org.export.latex.src")
require("org.export.latex.table")
require("org.export.latex.backend")
require("org.export.latex.compile")

return M
