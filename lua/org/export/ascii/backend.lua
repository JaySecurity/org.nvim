---@mod org.export.ascii.backend Plain text filters, options and back-end
---
--- The blank line filters, the option defaults and the back-end
--- definition.
---
--- Part of org.export.ascii, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.ascii.shared")

local M = require("org.export.ascii")

local HARD = shared.HARD
local T = shared.T
local acfg = shared.acfg

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------

--- org-ascii-filter-headline-blank-lines
local function headline_blank_lines(s, _, info)
  local spacing = info.ascii_headline_spacing
  if not spacing then
    return s
  end
  local blanks = string.rep("\n", 1 + spacing[2])
  -- leftmost match of "\n\(\n[ \t]*\)*\'"
  local last = #s
  while last > 0 and s:sub(last, last):match("[ \t\n]") do
    last = last - 1
  end
  local i = s:find("\n", last + 1, true)
  while i do
    local rest = s:sub(i + 1)
    local ok = true
    while rest ~= "" do
      if rest:sub(1, 1) ~= "\n" then
        ok = false
        break
      end
      rest = rest:sub(2):gsub("^[ \t]*", "")
    end
    if ok then
      return s:sub(1, i - 1) .. blanks
    end
    i = s:find("\n", i + 1, true)
  end
  return s
end

local function paragraph_spacing(tree, _, info)
  local sp = info.ascii_paragraph_spacing
  if type(sp) == "number" and sp >= 0 then
    element.map(tree, "paragraph", function(p)
      local nxt = ox.get_next_element(p, info)
      if nxt and nxt.type == "paragraph" then
        p.post_blank = sp
      end
    end, { ignore = info.ignore })
  end
  return tree
end

local function comment_spacing(tree, _, info)
  element.map(tree, { comment = true, ["comment-block"] = true }, function(c)
    local nxt = ox.get_next_element(c, info)
    if nxt and (nxt.type == "comment" or nxt.type == "comment-block") then
      c.post_blank = 0
    end
  end, { ignore = info.ignore })
  return tree
end

local function final_output(s)
  return (s:gsub(HARD, "\n"))
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

M.defaults = {
  bullets = { ascii = { "*", "+", "-" }, latin1 = { "§", "¶" }, ["utf-8"] = { "◊" } },
  caption_above = false,
  charset = "ascii",
  global_margin = 0,
  headline_spacing = { 1, 2 },
  indented_line_width = "auto",
  inlinetask_width = 30,
  inner_margin = 2,
  links_to_notes = true,
  list_margin = 0,
  paragraph_spacing = "auto",
  quote_margin = 6,
  table_keep_all_vertical_lines = false,
  table_use_ascii_art = false,
  table_widen_columns = true,
  text_width = 72,
  underline = {
    ascii = { "=", "~", "-" },
    latin1 = { "=", "~", "-" },
    ["utf-8"] = { "═", "─", "╌", "┄", "┈" },
  },
  verbatim_format = "`%s'",
}

function M.options()
  local c = acfg()
  local function v(name)
    if c[name] == nil then
      if name == "text_width" then
        local legacy = (require("org.config").opts.export or {}).text_width
        if legacy ~= nil then
          return legacy
        end
      end
      return M.defaults[name]
    end
    return c[name]
  end
  local function thunk(f)
    return function()
      return f
    end
  end
  return {
    { "subtitle", "SUBTITLE", nil, nil, "parse" },
    { "ascii_bullets", nil, nil, v("bullets") },
    { "ascii_caption_above", nil, nil, v("caption_above") },
    { "ascii_charset", nil, nil, v("charset") },
    { "ascii_global_margin", nil, nil, v("global_margin") },
    -- function defaults are thunks in ox, so wrap the functions
    { "ascii_format_drawer_function", nil, nil, thunk(c.format_drawer_function) },
    { "ascii_format_inlinetask_function", nil, nil, thunk(c.format_inlinetask_function) },
    { "ascii_headline_spacing", nil, nil, v("headline_spacing") },
    { "ascii_indented_line_width", nil, nil, v("indented_line_width") },
    { "ascii_inlinetask_width", nil, nil, v("inlinetask_width") },
    { "ascii_inner_margin", nil, nil, v("inner_margin") },
    { "ascii_links_to_notes", nil, nil, v("links_to_notes") },
    { "ascii_list_margin", nil, nil, v("list_margin") },
    { "ascii_paragraph_spacing", nil, nil, v("paragraph_spacing") },
    { "ascii_quote_margin", nil, nil, v("quote_margin") },
    { "ascii_table_keep_all_vertical_lines", nil, nil, v("table_keep_all_vertical_lines") },
    { "ascii_table_use_ascii_art", nil, nil, v("table_use_ascii_art") },
    { "ascii_table_widen_columns", nil, nil, v("table_widen_columns") },
    { "ascii_text_width", nil, nil, v("text_width") },
    { "ascii_underline", nil, nil, v("underline") },
    { "ascii_verbatim_format", nil, nil, v("verbatim_format") },
  }
end

M.backend = ox.define_backend("ascii", {
  transcoders = T,
  options = M.options,
  filters = {
    headline = { headline_blank_lines },
    section = { headline_blank_lines },
    ["parse-tree"] = { paragraph_spacing, comment_spacing },
    ["final-output"] = { final_output },
  },
})
