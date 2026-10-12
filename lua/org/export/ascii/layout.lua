---@mod org.export.ascii.layout Plain text layout helpers
---
--- Indentation, boxes, text width and justification of elements,
--- titles, tables of contents and link descriptions.
---
--- Part of org.export.ascii, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local fmt = string.format
local nw = ox.nw

local chars = shared.chars
local charset = shared.charset
local column_between = shared.column_between
local indent_chars = shared.indent_chars
local swidth = shared.swidth
local trim = shared.trim
local trunc_div = shared.trunc_div
local utf8p = shared.utf8p

local function indent_string(s, width)
  if type(s) ~= "string" then
    return s
  end
  if width <= 0 then
    return s
  end
  local pad = string.rep(" ", width)
  local out = {}
  local ends = s:sub(-1) == "\n"
  local body = ends and s:sub(1, -2) or s
  for line in (body .. "\n"):gmatch("(.-)\n") do
    if line:match("%S") then
      line = line:gsub("^[ \t]*", function(ws)
        return pad .. ws
      end, 1)
    end
    out[#out + 1] = line
  end
  local r = table.concat(out, "\n")
  if ends then
    r = r .. "\n"
  end
  return r
end
M.indent_string = indent_string

local function box_string(s, info)
  local u = utf8p(info)
  s = s:gsub("\n[ \t]*$", "")
  local pre = u and "│ " or "| "
  -- replace-regexp-in-string "^" stops searching once a match (an empty
  -- one moves on by one character) reaches the end of the string: an
  -- empty string stays empty (a block holding only a blank line has an
  -- empty box), and so does an empty last line after an empty line
  local lines = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = pre .. line
  end
  if s == "" or (#lines > 1 and lines[#lines] == pre and lines[#lines - 1] == pre) then
    lines[#lines] = ""
  end
  return fmt(u and "┌────\n%s\n└────" or ",----\n%s\n`----", table.concat(lines, "\n"))
end

local function checkbox(item, info)
  local u = utf8p(info)
  local c = item.checkbox
  if c == "on" then
    return u and "☑ " or "[X] "
  elseif c == "off" then
    return u and "☐ " or "[ ] "
  elseif c == "trans" then
    return u and "☒ " or "[-] "
  end
end

local function bullet_string(b)
  return (b or "-"):gsub("[ \t]+$", "") .. " "
end

function M.current_text_width(el, info)
  local t = el.type
  if t == "inlinetask" then
    return info.ascii_inlinetask_width
  elseif t == "headline" then
    local rank = ox.low_level_p(el, info)
    return info.ascii_text_width - (rank and rank * 2 or info.ascii_global_margin)
  end
  local genealogy = {}
  local n = el
  while n do
    genealogy[#genealogy + 1] = n
    n = n.parent
  end
  local in_task = false
  for _, g in ipairs(genealogy) do
    if g.type == "inlinetask" then
      in_task = true
    end
  end
  local total
  if in_task then
    total = info.ascii_inlinetask_width
  else
    local parent = element.lineage(el, "headline")
    local inner = 0
    if parent then
      local rank = ox.low_level_p(parent, info)
      inner = rank and rank * 2 or info.ascii_inner_margin
    end
    total = info.ascii_text_width - info.ascii_global_margin - inner
  end
  local quotes, lists, indentation = 0, 0, 0
  for _, g in ipairs(genealogy) do
    if g.type == "quote-block" or g.type == "verse-block" then
      quotes = quotes + 1
    elseif g.type == "plain-list" and not (g.parent and g.parent.type == "item") then
      lists = lists + 1
    elseif g.type == "item" then
      if g.parent and g.parent.list_type == "descriptive" then
        indentation = indentation + info.ascii_quote_margin
      else
        indentation = indentation + swidth(checkbox(g, info) or "") + swidth(g.bullet or "")
      end
    end
  end
  return total - (quotes * 2 * info.ascii_quote_margin + lists * info.ascii_list_margin + indentation)
end

function M.current_justification(el)
  local p = el.parent
  while p do
    if p.type == "center-block" then
      return "center"
    elseif p.type == "special-block" then
      if p.block_type == "JUSTIFYRIGHT" then
        return "right"
      elseif p.block_type == "JUSTIFYLEFT" then
        return "left"
      end
    end
    p = p.parent
  end
  return "left"
end

function M.justify_element(contents, el, info)
  if not nw(contents) then
    return contents
  end
  local width = M.current_text_width(el, info)
  local how = M.current_justification(el)
  if el.type == "paragraph" then
    return M.fill_string(contents, width, info, how)
  elseif how == "left" then
    return contents
  end
  local lines = {}
  local ends = contents:sub(-1) == "\n"
  local body = ends and contents:sub(1, -2) or contents
  for line in (body .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  local max = 0
  for _, l in ipairs(lines) do
    if not l:match("^[ \t]*$") then
      local c = column_between(chars(l), 1, #chars(l) + 1)
      if c >= width then
        return contents
      end
      max = math.max(max, c)
    end
  end
  local offset = trunc_div(width - max, how == "right" and 1 or 2)
  if offset == 0 then
    return contents
  end
  local pad = table.concat(indent_chars(0, offset, true))
  for i, l in ipairs(lines) do
    if not l:match("^[ \t]*$") then
      lines[i] = pad .. l
    end
  end
  return table.concat(lines, "\n") .. (ends and "\n" or "")
end

local function translate(s, info)
  return ox.translate(s, charset(info), info)
end

local function make_tag_string(tags)
  return ":" .. table.concat(tags, ":") .. ":"
end

function M.build_title(el, info, text_width, underline, notags, toc)
  local headlinep = el.type == "headline"
  local numbers = ""
  if headlinep and ox.numbered_headline_p(el, info) then
    local num = ox.get_headline_number(el, info) or {}
    if toc then
      numbers = fmt("%d. ", num[#num] or 0)
    else
      local parts = {}
      for i, x in ipairs(num) do
        parts[i] = tostring(x)
      end
      numbers = table.concat(parts, ".") .. " "
    end
  end
  local text = trim(ox.data((toc and headlinep) and ox.get_alt_title(el) or el.title, info))
  local todo = (info.with_todo_keywords and el.todo_keyword) and (el.todo_keyword .. " ") or ""
  local tags
  if not notags and info.with_tags then
    local tl = ox.get_tags(el, info)
    if #tl > 0 then
      tags = make_tag_string(tl)
    end
  end
  local priority = (info.with_priority and el.priority) and fmt("(#%s) ", el.priority) or ""
  local first = numbers .. todo .. priority .. text
  local s = first
  if tags then
    local w = math.max(text_width - (1 + swidth(first)), swidth(tags))
    s = s .. " " .. string.rep(" ", w - swidth(tags)) .. tags
  end
  if underline and headlinep then
    local unders = (info.ascii_underline or {})[charset(info)] or {}
    local ch = unders[ox.get_relative_level(el, info)]
    if ch then
      s = s .. "\n" .. string.rep(ch, math.floor(swidth(first) / math.max(1, swidth(ch))))
    end
  end
  return s
end

local function has_caption(el)
  return el.caption ~= nil
end

local function build_caption(el, info)
  local caption = ox.get_caption(el)
  if not caption then
    return nil
  end
  local reference = ox.get_ordinal(el, info, nil, has_caption)
  local title_fmt = translate(el.type == "table" and "Table %d:" or "Listing %d:", info)
  return M.fill_string(
    (title_fmt:gsub("%%d", tostring(reference))) .. " " .. ox.data(caption, info),
    M.current_text_width(el, info),
    info
  )
end

local function rule_title(title, info)
  return title .. "\n" .. string.rep(utf8p(info) and "─" or "_", swidth(title)) .. "\n\n"
end

function M.build_toc(info, n, keyword, scope)
  local out = {}
  if not scope then
    out[#out + 1] = rule_title(translate("Table of Contents", info), info)
  end
  local text_width = keyword and M.current_text_width(keyword, info)
    or (info.ascii_text_width - info.ascii_global_margin)
  local entries = {}
  for _, h in ipairs(ox.collect_headlines(info, n, scope)) do
    local level = ox.get_relative_level(h, info)
    local indent = (level - 1) * 3
    entries[#entries + 1] = (indent ~= 0 and (string.rep(".", indent - 1) .. " ") or "")
      .. M.build_title(h, info, text_width - indent, nil, (not info.with_tags) or info.with_tags == "not-in-toc", true)
  end
  out[#out + 1] = table.concat(entries, "\n")
  return table.concat(out)
end

local function list_of(kind, keyword, info)
  local title = translate(kind == "tables" and "List of Tables" or "List of Listings", info)
  local text_width = keyword and M.current_text_width(keyword, info)
    or (info.ascii_text_width - info.ascii_global_margin)
  local elems = kind == "tables" and ox.collect_tables(info) or ox.collect_listings(info)
  local count = 0
  local items = {}
  for _, e in ipairs(elems) do
    count = count + 1
    local initial = (translate(kind == "tables" and "Table %d:" or "Listing %d:", info):gsub("%%d", tostring(count)))
    local iw = swidth(initial)
    local caption = ox.get_caption(e, true) or ox.get_caption(e)
    items[#items + 1] = initial
      .. " "
      .. trim(indent_string(M.fill_string(ox.data(caption, info), text_width - iw, info), iw))
  end
  return rule_title(title, info) .. table.concat(items, "\n")
end

local function unique_links(el, info)
  local seen = {}
  local out = {}
  local data
  if el.type == "section" then
    data = el
  else
    data = { el.title or {}, el.contents[1] and el.contents[1].type == "section" and el.contents[1] or {} }
  end
  element.map(data, "link", function(link)
    local contents = #link.contents > 0 and trim(element.interpret(link.contents)):gsub("[ \r\t\n]+", " ") or ""
    local footprint = (link.raw_link or "") .. "\0" .. contents
    if nw(info.exported_data[link]) and not seen[footprint] then
      seen[footprint] = true
      out[#out + 1] = link
    end
  end, { ignore = info.ignore, no_recursion = { headline = true }, with_affiliated = true })
  return out
end

-- `format "%s"' of an ordinal: a target inside a list item or a
-- headline section gets a list of numbers, which Emacs prints in Lisp
-- syntax, e.g. "(1 2)".
local function ordinal_string(n)
  if type(n) == "table" then
    local parts = {}
    for i, x in ipairs(n) do
      parts[i] = tostring(x)
    end
    return "(" .. table.concat(parts, " ") .. ")"
  end
  return tostring(n)
end

local function describe_datum(datum, info)
  local t = datum.type
  if t == "plain-text" then
    return fmt("See file %s", datum.value)
  elseif t == "headline" then
    local d
    if ox.numbered_headline_p(datum, info) then
      local parts = {}
      for i, x in ipairs(ox.get_headline_number(datum, info) or {}) do
        parts[i] = tostring(x)
      end
      d = table.concat(parts, ".")
    else
      d = ox.data(datum.title, info)
    end
    return (translate("See section %s", info):gsub("%%s", function()
      return d
    end))
  end
  local number = ox.get_ordinal(datum, info, nil, has_caption)
  local enumerable =
    element.lineage(datum, { headline = true, paragraph = true, ["src-block"] = true, table = true }, true)
  local et = enumerable and enumerable.type
  if et == "headline" then
    local d
    if ox.numbered_headline_p(enumerable, info) then
      local parts = {}
      for i, x in ipairs(number or {}) do
        parts[i] = tostring(x)
      end
      d = table.concat(parts, ".")
    else
      d = ox.data(enumerable.title, info)
    end
    return (translate("See section %s", info):gsub("%%s", function()
      return d
    end))
  elseif not number then
    return translate("Unknown reference", info)
  elseif et == "paragraph" then
    -- lint: allow gsub: an ordinal of a number
    return (translate("See figure %s", info):gsub("%%s", ordinal_string(number)))
  elseif et == "src-block" then
    -- lint: allow gsub: an ordinal of a number
    return (translate("See listing %s", info):gsub("%%s", ordinal_string(number)))
  elseif et == "table" then
    -- lint: allow gsub: an ordinal of a number
    return (translate("See table %s", info):gsub("%%s", ordinal_string(number)))
  end
  return translate("Unknown reference", info)
end

local function describe_links(links, width, info)
  local out = {}
  for _, link in ipairs(links) do
    local t = link.link_type
    local description = #link.contents > 0 and link.contents or nil
    local anchor = ox.data(description or link.raw_link, info)
    if t == "coderef" or t == "radio" then
      -- nothing
    elseif t == "custom-id" or t == "fuzzy" or t == "id" then
      if description then
        local ok, dest = pcall(function()
          if t == "fuzzy" then
            return ox.resolve_fuzzy_link(link, info)
          end
          return ox.resolve_id_link(link, info)
        end)
        if ok and dest then
          out[#out + 1] = M.fill_string(fmt("[%s] %s", anchor, describe_datum(dest, info)), width, info) .. "\n\n"
        end
      end
    elseif not description then
      -- the destination is already visible
    elseif ox.custom_protocol_maybe(link, anchor, "ascii", info) then
      -- handled by a custom export function
    else
      out[#out + 1] = M.fill_string(fmt("[%s] <%s>", anchor, link.raw_link), width, info) .. "\n\n"
    end
  end
  return table.concat(out)
end

local function with_opt(info, key, value)
  return setmetatable({ [key] = value }, { __index = info })
end

-- Locals the later parts share
shared.indent_string = indent_string
shared.box_string = box_string
shared.checkbox = checkbox
shared.bullet_string = bullet_string
shared.translate = translate
shared.has_caption = has_caption
shared.build_caption = build_caption
shared.rule_title = rule_title
shared.list_of = list_of
shared.unique_links = unique_links
shared.describe_datum = describe_datum
shared.describe_links = describe_links
shared.with_opt = with_opt
