---@mod org.export.html.headline HTML headlines, sections and items
---
--- Sections, headlines, list items, inline tasks, keywords and other
--- small transcoders.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local CHECKBOXES = shared.CHECKBOXES
local T = shared.T
local anchor = shared.anchor
local close_tag = shared.close_tag
local fontify = shared.fontify
local format_headline = shared.format_headline
local hcfg = shared.hcfg
local list_of = shared.list_of

local function container(h, info)
  return (h.props and h.props.HTML_CONTAINER) or (ox.get_relative_level(h, info) == 1 and info.html_container or "div")
end

T.section = function(el, contents, info)
  local parent = element.lineage(el, "headline")
  if not parent then
    return contents
  end
  local class_num = ox.get_relative_level(parent, info) + info.html_toplevel_hlevel - 1
  local num
  if ox.numbered_headline_p(parent, info) then
    local nums = ox.get_headline_number(parent, info)
    if nums then
      local parts = {}
      for i, x in ipairs(nums) do
        parts[i] = tostring(x)
      end
      num = table.concat(parts, "-")
    end
  end
  return fmt(
    '<div class="outline-text-%d" id="text-%s">\n%s</div>\n',
    class_num,
    (parent.props and parent.props.CUSTOM_ID) or num or ox.get_reference(parent, info),
    contents or ""
  )
end

function M.format_list_item(contents, ltype, checkbox, info, term_counter_id, headline)
  local class = checkbox and fmt(' class="%s"', checkbox) or ""
  local box = (checkbox and (CHECKBOXES[info.html_checkbox_type] or CHECKBOXES.ascii)[checkbox] or "")
    .. (checkbox and " " or "")
  local br = close_tag("br", nil, info)
  local extra = (nw(contents) and headline) and "\n" or ""
  local s
  if ltype == "ordered" then
    s = fmt("<li%s%s>", class, term_counter_id and fmt(' value="%s"', term_counter_id) or "")
      .. (headline and (headline .. br) or "")
  elseif ltype == "unordered" then
    s = fmt("<li%s%s>", class, term_counter_id and fmt(' id="%s"', term_counter_id) or "")
      .. (headline and (headline .. br) or "")
  else
    s = fmt("<dt%s>%s</dt>", class, box .. (term_counter_id or "(no term)")) .. "<dd>"
  end
  if ltype ~= "descriptive" then
    s = s .. box
  end
  s = s .. extra .. (nw(contents) and trim(contents) or "") .. extra
  if ltype == "descriptive" then
    return s .. "</dd>"
  end
  return s .. "</li>"
end

T.headline = function(el, contents, info)
  if el.footnote_section_p then
    return nil
  end
  local numberedp = ox.numbered_headline_p(el, info)
  local numbers = ox.get_headline_number(el, info)
  local level = ox.get_relative_level(el, info) + info.html_toplevel_hlevel - 1
  local todo = info.with_todo_keywords and el.todo_keyword and ox.data(el.todo_keyword, info) or nil
  local todo_type = todo and el.todo_type
  local priority = info.with_priority and el.priority or nil
  local text = ox.data(el.title, info)
  local tags = info.with_tags and ox.get_tags(el, info) or nil
  if tags and #tags == 0 then
    tags = nil
  end
  local full = format_headline(info, todo, todo_type, priority, text, tags, info)
  contents = contents or ""
  local id = M.reference(el, info)
  local formatted = info.html_self_link_headlines and fmt('<a href="#%s">%s</a>', id, full) or full
  if ox.low_level_p(el, info) then
    local html_type = numberedp and "ol" or "ul"
    return (ox.first_sibling_p(el, info) and fmt('<%s class="org-%s">\n', html_type, html_type) or "")
      .. M.format_list_item(
        contents,
        numberedp and "ordered" or "unordered",
        nil,
        info,
        nil,
        anchor(id, nil, nil, info) .. formatted
      )
      .. "\n"
      .. (ox.last_sibling_p(el, info) and fmt("</%s>\n", html_type) or "")
  end
  local extra_class = el.props and el.props.HTML_CONTAINER_CLASS
  local headline_class = el.props and el.props.HTML_HEADLINE_CLASS
  local first = el.contents[1]
  local num = ""
  if numberedp and numbers then
    local parts = {}
    for i, x in ipairs(numbers) do
      parts[i] = tostring(x)
    end
    num = fmt('<span class="section-number-%d">%s</span> ', level, table.concat(parts, ".") .. ".")
  end
  local body
  if first and first.type == "section" then
    body = contents
  elseif first then
    -- pretend there is an empty section (for org-info.js)
    body = T.section(first, "", info) .. contents
  else
    body = contents
  end
  local c = container(el, info)
  return fmt(
    '<%s id="%s" class="%s">%s%s</%s>\n',
    c,
    "outline-container-" .. id,
    fmt("outline-%d", level) .. (extra_class and (" " .. extra_class) or ""),
    fmt(
      '\n<h%d id="%s"%s>%s</h%d>\n',
      level,
      id,
      headline_class and fmt(' class="%s"', headline_class) or "",
      num .. formatted,
      level
    ),
    body,
    c
  )
end

T["horizontal-rule"] = function(_, _, info)
  return close_tag("hr", nil, info)
end

T["inline-src-block"] = function(el, _, info)
  local lbl = M.reference(el, info, true)
  return fmt(
    '<code class="src src-%s"%s>%s</code>',
    el.language,
    lbl and fmt(' id="%s"', lbl) or "",
    fontify(el.value, el.language)
  )
end

T.inlinetask = function(el, contents, info)
  local todo = info.with_todo_keywords and el.todo_keyword or nil
  local todo_type = todo and el.todo_type
  local priority = info.with_priority and el.priority or nil
  local text = ox.data(el.title, info)
  local tags = info.with_tags and ox.get_tags(el, info) or nil
  if tags and #tags == 0 then
    tags = nil
  end
  local f = hcfg().format_inlinetask_function
  if type(f) == "function" then
    return f(todo, todo_type, priority, text, tags, contents, info)
  end
  return fmt(
    '<div class="inlinetask">\n<b>%s</b>%s\n%s</div>',
    format_headline(info, todo, todo_type, priority, text, tags, info),
    close_tag("br", nil, info),
    contents or ""
  )
end

T.item = function(el, contents, info)
  local list = el.parent
  local ltype = list.list_type
  local tag = el.tag and ox.data(el.tag, info) or nil
  return M.format_list_item(contents, ltype, el.checkbox, info, tag or el.counter)
end

T.keyword = function(el, _, info)
  local key, value = el.key, el.value
  if key == "HTML" then
    return value
  elseif key == "TOC" then
    local low = value:lower()
    if low:match("%f[%w]headlines%f[%W]") then
      local depth = tonumber(value:match("%f[%d](%d+)%f[%D]"))
      local scope
      local target = value:match(':target +(".-")') or value:match(":target +(%S+)")
      if target then
        scope = ox.resolve_link(target:gsub('^"(.*)"$', "%1"), info)
      elseif low:match("%f[%w]local%f[%W]") then
        scope = el
      end
      return M.toc(depth, info, scope)
    elseif value == "listings" then
      return list_of("listings", info)
    elseif value == "tables" then
      return list_of("tables", info)
    end
  end
end
