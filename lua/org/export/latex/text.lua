---@mod org.export.latex.text LaTeX plain text and text blocks
---
--- Plain text (org-latex-plain-text), planning, property drawers, quote,
--- special and verse-like blocks, sections.
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
local wrap_label = shared.wrap_label

--- Verse block plain text rules (org-latex--plain-text-verse-block).
local function verse_text(output, node)
  local verse = node and element.lineage(node, "verse-block")
  if not verse or element.lineage(node, "footnote-reference") then
    return output
  end
  local lin = ox.read_attribute("attr_latex", verse, "lines")
  local lit = ox.read_attribute("attr_latex", verse, "literal")
  local s = output:gsub("[ \t]*\\\\[ \t]*\n", "\\\\\n"):gsub("[ \t]*\n", "\\\\\n")
  if not lit then
    -- several empty lines: a single stanza break
    s = s:gsub("\\\\\n([ \t]*\\\\\n)+", lin and "\\\\!\n\n" or "\n\n")
  else
    s = s:gsub("\n[ \t]*\\\\\n", "\n\\vspace*{\\baselineskip}\n"):gsub("^[ \t]*\\\\\n", "\\vspace*{\\baselineskip}\n")
  end
  s = s:gsub("\n([ \t]+)", function(ws)
    return fmt("\n\\hspace*{%d\\fontdimen2\\font}", #ws)
  end)
  s = s:gsub("^([ \t]+)", function(ws)
    return fmt("\\hspace*{%d\\fontdimen2\\font}", #ws)
  end)
  return s
end

function M.plain_text(text, info, node)
  local specialp = info.with_special_strings
  local out = {}
  local i = 1
  while i <= #text do
    local c = text:sub(i, i)
    if c == "\\" then
      local nxt = text:sub(i + 1, i + 1)
      if specialp and nxt == "-" then
        out[#out + 1] = "\\"
      else
        out[#out + 1] = "$\\backslash$"
      end
    elseif c == "~" then
      out[#out + 1] = "\\textasciitilde{}"
    elseif c == "^" then
      out[#out + 1] = "\\^{}"
    elseif c:match("[%%%$#&{}_]") then
      out[#out + 1] = "\\" .. c
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  local output = table.concat(out)
  -- LaTeX -> \LaTeX{}, TeX -> \TeX{}
  output = output:gsub("%f[%w]LaTeX%f[%W]", "\\LaTeX{}"):gsub("%f[%w\\]TeX%f[%W]", "\\TeX{}")
  if info.with_smart_quotes and node then
    output = ox.activate_smart_quotes(output, "latex", info, node)
  end
  if specialp then
    output = output:gsub("%.%.%.", "\\ldots{}")
  end
  if info.preserve_breaks then
    output = output:gsub("[ \t]*\\\\[ \t]*\n", "\n"):gsub("[ \t]*\n", "\\\\\n")
  end
  output = output:gsub("\n([ \t]*)%[", "\n%1{[}"):gsub("^([ \t]*)%[", "%1{[}")
  output = verse_text(output, node)
  return output
end

T["plain-text"] = function(text, info, node)
  return M.plain_text(text, info, node)
end

T.planning = function(el, _, info)
  local parts = {}
  if el.closed then
    parts[#parts + 1] = "\\textbf{CLOSED:} "
      .. fmt(info.latex_inactive_timestamp_format, ox.timestamp_translate(el.closed))
  end
  if el.deadline then
    parts[#parts + 1] = "\\textbf{DEADLINE:} "
      .. fmt(info.latex_active_timestamp_format, ox.timestamp_translate(el.deadline))
  end
  if el.scheduled then
    parts[#parts + 1] = "\\textbf{SCHEDULED:} "
      .. fmt(info.latex_active_timestamp_format, ox.timestamp_translate(el.scheduled))
  end
  return "\\noindent" .. table.concat(parts, " ") .. "\\\\"
end

T["property-drawer"] = function(_, contents)
  if nw(contents) then
    return fmt("\\begin{verbatim}\n%s\\end{verbatim}", contents)
  end
end

T["quote-block"] = function(el, contents, info)
  local env = ox.read_attribute("attr_latex", el, "environment") or info.latex_default_quote_environment
  local options = ox.read_attribute("attr_latex", el, "options") or ""
  return wrap_label(el, fmt("\\begin{%s}%s\n%s\\end{%s}", env, options, contents or "", env), info)
end

T["radio-target"] = function(el, text, info)
  return fmt("\\label{%s}%s", ox.get_reference(el, info), text or "")
end

T.section = function(_, contents)
  return contents
end

T["special-block"] = function(el, contents, info)
  local t = el.block_type
  local opt = ox.read_attribute("attr_latex", el, "options")
  local caption = M.caption_label_string(el, info)
  local above = caption_above_p(el, info)
  return fmt("\\begin{%s}%s\n", t, opt or "")
    .. (above and caption or "")
    .. (contents or "")
    .. ((not above) and caption or "")
    .. fmt("\\end{%s}", t)
end
