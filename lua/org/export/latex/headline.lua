---@mod org.export.latex.headline LaTeX headlines
---
--- Section formats and the headline transcoder (org-latex-headline).
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local fmt = string.format

local T = shared.T
local lcfg = shared.lcfg
local protect_text = shared.protect_text
local protect_texttt = shared.protect_texttt

--- Section format of a headline (org-latex--get-section-format).
local function section_format(h, info)
  local class = M.find_class(info, info.latex_class)
  if not class then
    return nil
  end
  local level = ox.get_relative_level(h, info)
  local numberedp = ox.numbered_headline_p(h, info)
  local sec
  if type(class[3]) == "function" then
    sec = class[3](level, numberedp)
  else
    sec = class[level + 2]
  end
  if not sec then
    return nil
  end
  if type(sec) == "string" then
    return sec .. "\n%s"
  end
  if #sec == 2 then
    -- (numbered . unnumbered) pairs have a %s in both strings;
    -- (numbered-open numbered-close) environments only in the first
    if sec[1]:find("%%s") and sec[2]:find("%%s") then
      return (numberedp and sec[1] or sec[2]) .. "\n%s"
    end
    if numberedp then
      return sec[1] .. "\n%s" .. sec[2]
    end
    return nil
  elseif #sec == 4 then
    if numberedp then
      return sec[1] .. "\n%s" .. sec[2]
    end
    return sec[3] .. "\n%s" .. sec[4]
  end
end

local section_backend = ox.create_backend("latex", {
  underline = function(_, c)
    return fmt("\\underline{%s}", c or "")
  end,
  code = function(o)
    return protect_texttt(o.value)
  end,
  verbatim = function(o)
    return protect_texttt(o.value)
  end,
})
local section_no_footnote_backend = ox.create_backend(section_backend, {
  ["footnote-reference"] = function()
    return nil
  end,
})

function M.format_headline(todo, _todo_type, priority, text, tags)
  local s = (todo and fmt("{\\bfseries\\sffamily %s} ", todo) or "")
    .. (priority and fmt("\\framebox{\\#%s} ", priority) or "")
    .. (text or "")
  if tags and #tags > 0 then
    local parts = {}
    for i, t in ipairs(tags) do
      parts[i] = protect_text(t)
    end
    s = s .. fmt("\\hfill{}\\textsc{%s}", table.concat(parts, ":"))
  end
  return s
end

local function format_headline(info, ...)
  local f = lcfg().format_headline_function
  if type(f) == "function" then
    return f(...)
  end
  return M.format_headline(...)
end

--- Apply a two-slot format ("%s" title, "%s" contents).
local function format2(f, a, b)
  local i = 0
  return (
    f:gsub("%%s", function()
      i = i + 1
      if i == 1 then
        return a
      elseif i == 2 then
        return b
      end
      return "%s"
    end)
  )
end

T.headline = function(el, contents, info)
  if el.footnote_section_p then
    return nil
  end
  contents = contents or ""
  local level = ox.get_relative_level(el, info)
  local unnumbered_type = ox.get_node_property("UNNUMBERED", el, true)
  local numberedp = ox.numbered_headline_p(el, info)
  local section_fmt = section_format(el, info)
  local text = ox.data_with_backend(el.title, section_backend, info)
  local text_nf = ox.data_with_backend(el.title, section_no_footnote_backend, info)
  local todo = info.with_todo_keywords and el.todo_keyword or nil
  local todo_type = todo and el.todo_type
  local tags = info.with_tags and ox.get_tags(el, info) or nil
  if tags and #tags == 0 then
    tags = nil
  end
  local priority = info.with_priority and el.priority or nil
  local full = format_headline(info, todo, todo_type, priority, text, tags, info)
  local full_nf = format_headline(info, todo, todo_type, priority, text_nf, tags, info)
  local hlabel = M.label(el, info, true, true)
  local pre = string.rep("\n", el.pre_blank or 0)
  if not section_fmt or ox.low_level_p(el, info) then
    local body = (ox.first_sibling_p(el, info) and fmt("\\begin{%s}\n", numberedp and "enumerate" or "itemize") or "")
      .. "\\item"
      .. ((full and full:match("^[ \t]*%[")) and "\\relax" or "")
      .. " "
      .. full
      .. "\n"
      .. hlabel
      .. pre
      .. contents
    if not ox.last_sibling_p(el, info) then
      return body
    end
    return (body:gsub("[ \t\n]*$", "")) .. fmt("\n\\end{%s}", numberedp and "enumerate" or "itemize")
  end
  local opt_title = format_headline(
    info,
    todo,
    todo_type,
    priority,
    ox.data_with_backend(ox.get_alt_title(el), section_backend, info),
    info.with_tags == true and tags or nil,
    info
  )
  -- local TOC end
  local first = el.contents[1]
  if first and first.type == "section" then
    local stop = element.map(first, "keyword", function(k)
      if
        k.key == "TOC"
        and k.value:lower():match("%f[%w]headlines%f[%W]")
        and k.value:lower():match("%f[%w]local%f[%W]")
      then
        return fmt("\\stopcontents[level-%d]", level)
      end
    end, { first_match = true, ignore = info.ignore })
    if stop then
      contents = contents .. stop
    end
  end
  local section_kw = section_fmt:match("^\\(.-){")
  local need_alt
  if not section_kw then
    need_alt = false
  elseif section_kw:match("%*$") then
    if info.latex_toc_include_unnumbered then
      need_alt = unnumbered_type ~= "notoc"
    else
      need_alt = unnumbered_type == "toc"
    end
  else
    need_alt = not (full == full_nf and full == opt_title)
  end
  if full_nf ~= full and full == opt_title then
    opt_title = full_nf
  end
  if need_alt then
    local new_fmt = section_fmt
    local extra = ""
    if section_kw:match("%*$") then
      extra = fmt("\\addcontentsline{toc}{%s}{%s}\n", section_kw:gsub("%*$", ""), opt_title)
    else
      local alt = opt_title:gsub("%[", "("):gsub("%]", ")")
      new_fmt = "\\" .. section_kw .. "[" .. alt:gsub("%%", "%%%%") .. "]" .. section_fmt:sub(#section_kw + 2)
    end
    return format2(new_fmt, full, hlabel .. extra .. pre .. contents)
  end
  return format2(section_fmt, full, hlabel .. pre .. contents)
end
