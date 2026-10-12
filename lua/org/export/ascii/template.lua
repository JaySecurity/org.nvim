---@mod org.export.ascii.template Plain text document template
---
--- The title block and the document around the contents
--- (org-ascii-template, org-ascii-inner-template).
---
--- Part of org.export.ascii, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local fmt = string.format
local nw = ox.nw

local indent_string = shared.indent_string
local rule_title = shared.rule_title
local swidth = shared.swidth
local translate = shared.translate
local trim = shared.trim
local utf8p = shared.utf8p
local with_opt = shared.with_opt

---------------------------------------------------------------------------
-- Template
---------------------------------------------------------------------------

local function document_title(info)
  local text_width = info.ascii_text_width
  info = with_opt(info, "ascii_links_to_notes", false)
  local with_title = info.with_title
  local title = ox.data(with_title and info.title or nil, info)
  local subtitle = ox.data(with_title and info.subtitle or nil, info)
  local author = info.with_author and info.author and ox.data(info.author, info) or nil
  local email = info.with_email and ox.data(info.email, info) or nil
  local date = nil
  if info.with_date then
    local d = ox.get_date(info)
    date = type(d) == "string" and d or ox.data(d, info)
  end
  if title == "" then
    if nw(date) and nw(author) then
      return author
        .. string.rep(" ", text_width - swidth(date) - swidth(author))
        .. date
        .. (nw(email) and ("\n" .. email) or "")
        .. "\n\n\n"
    elseif nw(date) and nw(email) then
      return email .. string.rep(" ", text_width - swidth(date) - swidth(email)) .. date .. "\n\n\n"
    elseif nw(date) then
      return M.justify_lines(date, text_width, "right") .. "\n\n\n"
    elseif nw(author) and nw(email) then
      return author .. "\n" .. email .. "\n\n\n"
    elseif nw(author) then
      return author .. "\n\n\n"
    elseif nw(email) then
      return email .. "\n\n\n"
    end
    return nil
  end
  local u = utf8p(info)
  local maxw = 0
  for line in (title .. "\n" .. subtitle .. "\n"):gmatch("(.-)\n") do
    maxw = math.max(maxw, swidth(line))
  end
  local title_len = math.min(maxw, math.floor(2 * text_width / 3))
  local formatted_title = M.fill_string(title, title_len, info)
  local formatted_subtitle = nw(subtitle) and M.fill_string(subtitle, title_len, info) or nil
  local line = string.rep(
    u and "━" or "_",
    math.min(math.max(title_len, swidth(author or ""), swidth(email or "")) + 2, text_width)
  )
  local s = line
    .. "\n"
    .. (u and "" or "\n")
    .. vim.fn.toupper(formatted_title)
    .. (formatted_subtitle and ("\n" .. formatted_subtitle) or "")
  if nw(author) and nw(email) then
    s = s .. "\n\n" .. author .. "\n" .. email
  elseif nw(author) then
    s = s .. "\n\n" .. author
  elseif nw(email) then
    s = s .. "\n\n" .. email
  end
  s = s .. "\n" .. line .. (nw(date) and ("\n\n\n" .. date) or "") .. "\n\n\n"
  return M.justify_lines(s, text_width, "center")
end

local function inner_template(contents, info)
  local margin = info.ascii_global_margin
  local s = contents
  local defs = ox.collect_footnote_definitions(info)
  if #defs > 0 then
    local ninfo = with_opt(info, "ascii_links_to_notes", false)
    local text_width = info.ascii_text_width - margin
    local parts = {}
    for _, ref in ipairs(defs) do
      local id = fmt("[%s] ", ref[1])
      local def = ref[3]
      local full = false
      for _, x in ipairs(def) do
        if element.ELEMENTS[x.type] then
          full = true
        end
      end
      local r
      if full then
        local first = def[1]
        if not first or first.type ~= "paragraph" then
          r = id .. "\n" .. ox.data(def, ninfo)
        else
          local t = element.text(id, first)
          table.insert(first.contents, 1, t)
          r = ox.data(def, ninfo)
        end
      else
        r = M.fill_string(id .. ox.data(def, ninfo), text_width, ninfo)
      end
      parts[#parts + 1] = trim(r)
    end
    s = s .. "\n\n\n" .. rule_title(translate("Footnotes", info), info) .. table.concat(parts, "\n\n")
  end
  return ox.normalize_string(indent_string(s, margin))
end

local function template(contents, info)
  local margin = info.ascii_global_margin
  local depth = info.with_toc
  local head = (document_title(info) or "")
    .. (depth and (M.build_toc(info, type(depth) == "number" and depth or nil) .. "\n\n\n") or "")
  local out = indent_string(head, margin) .. contents
  if info.with_creator then
    out = out
      .. indent_string(
        "\n\n\n" .. M.fill_string(info.creator or "", info.ascii_text_width - margin, info, "right"),
        margin
      )
  end
  return out
end

-- Locals the later parts share
shared.inner_template = inner_template
shared.template = template
