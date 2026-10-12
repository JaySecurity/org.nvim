---@mod org.export.html.transcode HTML plain text and markup transcoders
---
--- Plain text (org-html-plain-text), and the transcoder table with its
--- first entries, from bold to footnote-reference.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local nw = ox.nw
local fmt = string.format

local anchor = shared.anchor
local attribute_string = shared.attribute_string
local close_tag = shared.close_tag
local encode = shared.encode
local format_timestamp = shared.format_timestamp
local has_attr = shared.has_attr
local hcfg = shared.hcfg
local set_attr = shared.set_attr
local textarea_block = shared.textarea_block

---------------------------------------------------------------------------
-- Plain text
---------------------------------------------------------------------------

local function convert_special_strings(s)
  s = s:gsub("\\%-", "&shy;")
  s = s:gsub("%-%-%-([^%-])", "&mdash;%1")
  s = s:gsub("%-%-([^%-])", "&ndash;%1")
  s = s:gsub("%.%.%.", "&hellip;")
  return s
end
M.convert_special_strings = convert_special_strings

function M.plain_text(text, info, node)
  local out = encode(text)
  if info.with_smart_quotes and node then
    out = ox.activate_smart_quotes(out, "html", info, node)
  end
  if info.with_special_strings then
    out = convert_special_strings(out)
  end
  if info.preserve_breaks then
    -- lint: allow gsub: a <br> tag
    out = out:gsub("\\\\([ \t]*\n)", "%1"):gsub("[ \t]*\n", close_tag("br", nil, info) .. "\n")
  end
  return out
end

---------------------------------------------------------------------------
-- Transcoders
---------------------------------------------------------------------------

local T = {}

local function markup(kind, contents, info)
  local f = info.html_text_markup_alist[kind] or "%s"
  return (f:gsub("%%s", function()
    return contents
  end))
end

T.bold = function(_, contents, info)
  return markup("bold", contents, info)
end
T.italic = function(_, contents, info)
  return markup("italic", contents, info)
end
T.underline = function(_, contents, info)
  return markup("underline", contents, info)
end
T["strike-through"] = function(_, contents, info)
  return markup("strike-through", contents, info)
end
T.code = function(el, _, info)
  return markup("code", encode(el.value), info)
end
T.verbatim = function(el, _, info)
  return markup("verbatim", encode(el.value), info)
end

T["center-block"] = function(_, contents)
  return fmt('<div class="org-center">\n%s</div>', contents or "")
end

T.clock = function(el, _, info)
  return fmt(
    '<p>\n<span class="timestamp-wrapper">\n<span class="timestamp-kwd">%s</span> %s%s\n</span>\n</p>',
    "CLOCK:",
    format_timestamp(el.value, info),
    el.duration and fmt(' <span class="timestamp">(%s)</span>', el.duration) or ""
  )
end

T.drawer = function(el, contents)
  local f = hcfg().format_drawer_function
  if type(f) == "function" then
    return f(el.drawer_name, contents)
  end
  return contents
end

T["dynamic-block"] = function(_, contents)
  return contents
end

T.entity = function(el)
  return (entities[el.name] or {})[3] or ("\\" .. el.name)
end

T["example-block"] = function(el, _, info)
  local attrs = ox.read_attribute("attr_html", el)
  if attrs.textarea then
    return textarea_block(el)
  end
  if attrs.class then
    attrs.class = "example " .. attrs.class
  else
    set_attr(attrs, "class", "example")
  end
  local ref = M.reference(el, info)
  if ref and not has_attr(attrs, "id") then
    set_attr(attrs, "id", ref)
  end
  local a = attribute_string(attrs)
  return fmt("<pre%s>\n%s</pre>", nw(a) and (" " .. a) or "", M.format_code_of(el, info))
end

T["export-snippet"] = function(el)
  if M.snippet_backend(el) == "html" then
    return el.value
  end
end

function M.snippet_backend(el)
  local tr = (require("org.config").opts.export or {}).snippet_translation or {}
  return tr[el.back_end] or el.back_end
end

T["export-block"] = function(el)
  if el.back_end_type == "HTML" then
    return table.concat(element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true })), "\n")
      .. "\n"
  end
end

T["fixed-width"] = function(el)
  local lines = element.remove_indentation(vim.split(el.value, "\n", { plain = true }))
  return fmt('<pre class="example">\n%s</pre>', M.do_format_code(table.concat(lines, "\n")))
end

T["footnote-reference"] = function(el, _, info)
  local sep = ""
  local prev = ox.get_previous_element(el, info)
  if prev and prev.type == "footnote-reference" then
    sep = info.html_footnote_separator
  end
  local n = ox.get_footnote_number(el, info)
  local label = el.label
  if label and tostring(tonumber(label)) == label then
    label = nil
  end
  local id
  if ox.footnote_first_reference_p(el, info) then
    id = fmt("fnr.%s", label or n)
  else
    local lab = el.label
    local ord = ox.get_ordinal(el, info, nil, function(ref)
      if lab then
        return ref.label == lab
      end
      return ref.label == nil
    end)
    id = fmt("fnr.%s.%d", label or n, ord or 1)
  end
  return sep
    .. fmt(
      info.html_footnote_format,
      anchor(id, tostring(n), fmt(' class="footref" href="#fn.%s" role="doc-backlink"', label or n), info)
    )
end

-- Locals the later parts share
shared.T = T
