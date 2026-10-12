---@mod org.export.ascii.transcode Plain text transcoders: markup, blocks, headlines
---
--- Creates the transcoder table and its entries from bold to line-break.
---
--- Part of org.export.ascii, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")
local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local fmt = string.format
local nw = ox.nw

local HARD = shared.HARD
local box_string = shared.box_string
local bullet_string = shared.bullet_string
local chars = shared.chars
local charset = shared.charset
local checkbox = shared.checkbox
local describe_links = shared.describe_links
local indent_string = shared.indent_string
local list_of = shared.list_of
local swidth = shared.swidth
local trim = shared.trim
local unique_links = shared.unique_links
local utf8p = shared.utf8p

---------------------------------------------------------------------------
-- Transcoders
---------------------------------------------------------------------------

local T = {}

T.bold = function(_, contents)
  return fmt("*%s*", contents or "")
end
T.italic = function(_, contents)
  return fmt("/%s/", contents or "")
end
T.underline = function(_, contents)
  return fmt("_%s_", contents or "")
end
T["strike-through"] = function(_, contents)
  return fmt("+%s+", contents or "")
end

local function verbatim_format(value, info)
  return (info.ascii_verbatim_format:gsub("%%s", function()
    return value
  end))
end

T.code = function(el, _, info)
  return verbatim_format(el.value, info)
end
T.verbatim = T.code
T["inline-src-block"] = T.code

T["center-block"] = function(_, contents)
  return contents
end

T.clock = function(el, _, info)
  local s = "CLOCK: " .. ox.timestamp_translate(el.value)
  if el.duration then
    local parts = vim.split(el.duration, ":", { plain = true })
    s = s .. " => " .. fmt("%2s:%2s", parts[1] or "", parts[2] or "")
  end
  return M.justify_element(s, el, info)
end

T.drawer = function(el, contents, info)
  local width = M.current_text_width(el, info)
  local f = info.ascii_format_drawer_function
  if type(f) == "function" then
    return f(el.drawer_name, contents, width)
  end
  return contents
end

T["dynamic-block"] = function(_, contents)
  return contents
end

T.entity = function(el, _, info)
  local e = entities[el.name]
  if not e then
    return "\\" .. el.name
  end
  local c = charset(info)
  if c == "utf-8" then
    return e[6]
  elseif c == "latin1" then
    return e[5]
  end
  return e[4]
end

T["example-block"] = function(el, _, info)
  return M.justify_element(box_string(ox.format_code_default(el, info), info), el, info)
end

T["export-snippet"] = function(el)
  local tr = (require("org.config").opts.export or {}).snippet_translation or {}
  if (tr[el.back_end] or el.back_end) == "ascii" then
    return el.value
  end
end

T["export-block"] = function(el, _, info)
  if el.back_end_type == "ASCII" then
    return M.justify_element(el.value, el, info)
  end
end

T["fixed-width"] = function(el, _, info)
  local lines = element.remove_indentation(vim.split(el.value, "\n", { plain = true }))
  return M.justify_element(box_string(table.concat(lines, "\n"), info), el, info)
end

T["footnote-reference"] = function(el, _, info)
  return fmt("[%s]", ox.get_footnote_number(el, info))
end

T.headline = function(el, contents, info)
  if el.footnote_section_p then
    return nil
  end
  contents = contents or ""
  local low = ox.low_level_p(el, info)
  local width = M.current_text_width(el, info)
  local title = M.build_title(el, info, width, not low)
  local spacing = info.ascii_headline_spacing
  local pre = string.rep("\n", (spacing and spacing[1]) or el.pre_blank or 0)
  local links = info.ascii_links_to_notes and describe_links(unique_links(el, info), width, info) or nil
  local body = contents
  if nw(links) then
    local first = el.contents[1]
    local section = first and first.type == "section" and first or nil
    local parts = {}
    if section then
      parts[#parts + 1] = ox.normalize_string(ox.data(section, info)) .. "\n\n"
    end
    parts[#parts + 1] = links
    for i, e in ipairs(el.contents) do
      if not (section and i == 1) then
        parts[#parts + 1] = ox.data(e, info)
      end
    end
    body = table.concat(parts)
  end
  if low then
    local bullets = (info.ascii_bullets or {})[charset(info)] or { "*" }
    local bullet = bullets[((low - 1) % #bullets) + 1] .. " "
    return bullet .. title .. "\n" .. pre .. indent_string(body, #chars(bullet))
  end
  return title .. "\n" .. pre .. body
end

T["horizontal-rule"] = function(el, _, info)
  local text_width = M.current_text_width(el, info)
  local spec = ox.read_attribute("attr_ascii", el, "width")
  local w = (spec and spec:match("^%d+$")) and tonumber(spec) or text_width
  return M.justify_lines(string.rep(utf8p(info) and "―" or "-", w), text_width, "center")
end

function M.format_inlinetask_default(_todo, _type, _priority, _name, _tags, contents, width, inlinetask, info)
  local u = utf8p(info)
  width = width or info.ascii_inlinetask_width
  local title = M.build_title(inlinetask, info, width)
  if swidth(title) > width then
    title = M.fill_string(title, width, info)
  end
  local s = string.rep(u and "━" or "_", width)
    .. "\n"
    .. (u and "" or (string.rep(" ", width) .. "\n"))
    .. title
    .. "\n"
    .. (nw(contents) and (string.rep(u and "─" or "-", width) .. "\n" .. contents) or "")
    .. string.rep(u and "━" or "_", width)
  return indent_string(
    s,
    info.ascii_text_width
      - info.ascii_global_margin
      - (element.lineage(inlinetask, "headline") and info.ascii_inner_margin or 0)
      - M.current_text_width(inlinetask, info)
  )
end

T.inlinetask = function(el, contents, info)
  local width = M.current_text_width(el, info)
  local f = info.ascii_format_inlinetask_function
  if type(f) ~= "function" then
    f = M.format_inlinetask_default
  end
  return f(
    info.with_todo_keywords and el.todo_keyword or nil,
    el.todo_type,
    info.with_priority and el.priority or nil,
    ox.data(el.title, info),
    info.with_tags and el.tags or nil,
    contents,
    width,
    el,
    info
  )
end

T.item = function(el, contents, info)
  local u = utf8p(info)
  local cb = checkbox(el, info)
  local list_type = el.parent.list_type
  local bullet
  if list_type == "descriptive" then
    bullet = (cb or "") .. ox.data(el.tag, info)
  elseif list_type == "ordered" then
    local bul = bullet_string(el.bullet)
    local num = ox.get_ordinal(el, info)
    bullet = bul:gsub("[%w]+", tostring(num[#num]), 1)
  else
    local bul = bullet_string(el.bullet)
    if u then
      bul = bul:gsub("%*", "‣"):gsub("%+", "⁃"):gsub("%-", "•")
    end
    bullet = bul
  end
  local indentation = list_type == "descriptive" and info.ascii_quote_margin or swidth(bullet)
  local c = indent_string(contents, indentation)
  local rest
  local first_contrib
  for _, e in ipairs(el.contents) do
    if nw(ox.data(e, info)) then
      first_contrib = e
      break
    end
  end
  if list_type ~= "descriptive" and nw(c) and first_contrib and first_contrib.type == "paragraph" then
    rest = trim(c)
  else
    rest = "\n" .. (c or "")
  end
  return bullet .. (cb or "") .. rest
end

T.keyword = function(el, _, info)
  local key, value = el.key, el.value
  if key == "ASCII" then
    return M.justify_element(value, el, info)
  elseif key == "TOC" then
    local low = value:lower()
    local r
    if low:match("%f[%w]headlines%f[%W]") then
      local depth = tonumber(value:match("%f[%d](%d+)%f[%D]"))
      local scope
      local target = value:match(':target +(".-")') or value:match(":target +(%S+)")
      if target then
        scope = ox.resolve_link((target:gsub('^"(.*)"$', "%1")), info)
      elseif low:match("%f[%w]local%f[%W]") then
        scope = el
      end
      r = M.build_toc(info, depth, el, scope)
    elseif low:match("%f[%w]tables%f[%W]") then
      r = list_of("tables", el, info)
    elseif low:match("%f[%w]listings%f[%W]") then
      r = list_of("listings", el, info)
    end
    return M.justify_element(r, el, info)
  end
end

T["latex-environment"] = function(el, _, info)
  if info.with_latex then
    local lines = element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true }))
    return M.justify_element(table.concat(lines, "\n") .. "\n", el, info)
  end
end

T["latex-fragment"] = function(el, _, info)
  if info.with_latex then
    return el.value
  end
end

T["line-break"] = function()
  return HARD
end

-- Locals the later parts share
shared.T = T
