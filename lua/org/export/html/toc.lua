---@mod org.export.html.toc HTML table of contents, lists and footnotes
---
--- The table of contents, the lists of tables and listings
--- (org-html-toc, org-html-list-of-*) and the footnote section.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local trim = ox.trim
local fmt = string.format

local anchor = shared.anchor
local format_headline = shared.format_headline
local html5_fancy_p = shared.html5_fancy_p
local translate = shared.translate

---------------------------------------------------------------------------
-- TOC and lists of tables/listings
---------------------------------------------------------------------------

local function toc_text(entries, scope)
  local prev = scope and (entries[1][2] - 1) or 0
  local start = prev
  local out = {}
  for _, e in ipairs(entries) do
    local level = e[2]
    local cnt = level - prev
    local times = cnt > 0 and (cnt - 1) or -cnt
    prev = level
    local s = ""
    for _ = 1, times do
      s = s .. (cnt > 0 and "\n<ul>\n<li>" or "</li>\n</ul>\n")
    end
    s = s .. (cnt > 0 and "\n<ul>\n<li>" or "</li>\n<li>")
    out[#out + 1] = s .. e[1]
  end
  local tail = ""
  for _ = 1, prev - start do
    tail = tail .. "</li>\n</ul>\n"
  end
  return table.concat(out) .. tail
end

local function format_toc_headline(h, info)
  local num = ox.get_headline_number(h, info)
  local todo = info.with_todo_keywords and h.todo_keyword and ox.data(h.todo_keyword, info) or nil
  local todo_type = todo and h.todo_type
  local priority = info.with_priority and h.priority or nil
  local text = ox.data_with_backend(ox.get_alt_title(h), ox.toc_entry_backend("html"), info)
  local tags = info.with_tags == true and ox.get_tags(h, info) or nil
  local prefix = ""
  if not ox.low_level_p(h, info) and ox.numbered_headline_p(h, info) and num then
    local parts = {}
    for i, n in ipairs(num) do
      parts[i] = tostring(n)
    end
    prefix = table.concat(parts, ".") .. ". "
  end
  return fmt(
    '<a href="#%s">%s</a>',
    M.reference(h, info),
    prefix .. format_headline(info, todo, todo_type, priority, text, tags, info)
  )
end

function M.toc(depth, info, scope)
  local headlines = ox.collect_headlines(info, depth, scope)
  if #headlines == 0 then
    return nil
  end
  local entries = {}
  for _, h in ipairs(headlines) do
    entries[#entries + 1] = { format_toc_headline(h, info), ox.get_relative_level(h, info) }
  end
  local counter = info.html_toc_counter
  local suffix = counter and ("-" .. counter) or ""
  local toc = fmt('<div id="text-table-of-contents%s" role="doc-toc">', suffix)
    .. toc_text(entries, scope)
    .. "</div>\n"
  info.html_toc_counter = (counter or 0) + 1
  if scope then
    return toc
  end
  local outer = html5_fancy_p(info) and "nav" or "div"
  local top = info.html_toplevel_hlevel
  return fmt('<%s id="table-of-contents%s" role="doc-toc">\n', outer, suffix)
    .. fmt("<h%d>%s</h%d>\n", top, translate("Table of Contents", info), top)
    .. toc
    .. fmt("</%s>\n", outer)
end

local function has_caption(el)
  return el.caption ~= nil
end

local function list_of(kind, info)
  local entries, id, title, numfmt, cls
  if kind == "tables" then
    entries = ox.collect_tables(info)
    id, title, numfmt, cls = "list-of-tables", "List of Tables", "Table %d:", "table-number"
  else
    entries = ox.collect_listings(info)
    id, title, numfmt, cls = "list-of-listings", "List of Listings", "Listing %d:", "listing-number"
  end
  if #entries == 0 then
    return nil
  end
  local top = info.html_toplevel_hlevel
  local items = {}
  local count = 0
  local initial = fmt('<span class="%s">%s</span>', cls, translate(numfmt, info))
  for _, e in ipairs(entries) do
    local label = M.reference(e, info, true)
    local t = trim(ox.data(ox.get_caption(e, true) or ox.get_caption(e), info))
    count = count + 1
    local num = initial:gsub("%%d", tostring(count))
    if not label then
      items[#items + 1] = "<li>" .. num .. " " .. t .. "</li>"
    else
      items[#items + 1] = "<li>" .. fmt('<a href="#%s">%s %s</a>', label, num, t) .. "</li>"
    end
  end
  return fmt('<div id="%s">\n', id)
    .. fmt("<h%d>%s</h%d>\n", top, translate(title, info), top)
    .. fmt('<div id="text-%s">\n<ul>\n', id)
    .. table.concat(items, "\n")
    .. "\n</ul>\n</div>\n</div>"
end

---------------------------------------------------------------------------
-- Footnotes
---------------------------------------------------------------------------

function M.footnote_section(info)
  local defs = ox.collect_footnote_definitions(info)
  if #defs == 0 then
    return nil
  end
  local parts = {}
  for _, d in ipairs(defs) do
    local n, label, def = d[1], d[2], d[3]
    if label and tostring(tonumber(label)) == label then
      label = nil
    end
    local inline = true
    for _, x in ipairs(def) do
      if element.ELEMENTS[x.type] then
        inline = false
      end
    end
    local a = anchor(
      "fn." .. (label or n),
      tostring(n),
      fmt(' class="footnum" href="#fnr.%s" role="doc-backlink"', label or n),
      info
    )
    local contents = trim(ox.data(def, info))
    parts[#parts + 1] = fmt(
      '<div class="footdef">%s %s</div>\n',
      fmt(info.html_footnote_format, a),
      fmt(
        '<div class="footpara" role="doc-footnote">%s</div>',
        inline and fmt('<p class="footpara">%s</p>', contents) or contents
      )
    )
  end
  local section = info.html_footnotes_section
  local body = "\n" .. table.concat(parts, "\n") .. "\n"
  local title = translate("Footnotes", info)
  local i = 0
  return (section:gsub("%%s", function()
    i = i + 1
    return i == 1 and title or body
  end))
end

-- Locals the later parts share
shared.has_caption = has_caption
shared.list_of = list_of
