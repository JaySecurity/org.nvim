---@mod org.export.latex.engraved LaTeX engraved source blocks
---
--- The preamble and code of org-latex-src-block-backend engraved.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local fmt = string.format

local caption_above_p = shared.caption_above_p
local make_option_string = shared.make_option_string

---------------------------------------------------------------------------
-- Engraved source blocks (org-latex-src-block-backend engraved)
---------------------------------------------------------------------------

-- Replace the first line of `s` matching "[ \t]*[NAME][ \t]*\n?" (Emacs
-- string-match with ^, so at any line start) by `repl`.
local function replace_placeholder(s, name, repl)
  local pat = "^[ \t]*%[" .. name:gsub("%-", "%%-") .. "%][ \t]*\n?"
  local pos = 1
  while pos <= #s + 1 do
    local a, b = s:find(pat, pos)
    if a then
      return s:sub(1, a - 1) .. repl .. s:sub(b + 1)
    end
    local nl = s:find("\n", pos, true)
    if not nl then
      break
    end
    pos = nl + 1
  end
  return s
end

local function theme_letters(theme)
  return (tostring(theme):gsub("[^A-Za-z]", ""))
end

--- org-latex-generate-engraved-preamble
function M.generate_engraved_preamble(info)
  local E = require("org.export.engrave")
  local pre = info.latex_engraved_preamble or ""
  local theme = info.latex_engraved_theme
  if theme == "t" then
    theme = true
  end
  -- themes of the blocks (cl-delete-duplicates keeps the last occurrence)
  local all = element.map(info.parse_tree, { ["src-block"] = true, ["inline-src-block"] = true }, function(src)
    return ox.read_attribute("attr_latex", src)["engraved-theme"]
  end, { ignore = info.ignore })
  local themes = {}
  for i, t in ipairs(all) do
    local later = false
    for j = i + 1, #all do
      later = later or all[j] == t
    end
    if not later then
      themes[#themes + 1] = t
    end
  end
  local function spec(t)
    return E.gen_preamble(E.get_theme(t))
  end
  pre = replace_placeholder(
    pre,
    "FVEXTRA-SETUP",
    "\\fvset{%\n  " .. make_option_string(info.latex_engraved_options, ",\n  ") .. "}\n"
  )
  pre = replace_placeholder(
    pre,
    "LISTINGS-SETUP",
    fmt(
      "%% Support listings with captions\n\\usepackage{float}\n\\floatstyle{%s}\n\\newfloat{listing}{htbp}{lst}\n"
        .. "\\newcommand{\\listingsname}{Listing}\n\\floatname{listing}{\\listingsname}\n"
        .. "\\newcommand{\\listoflistingsname}{List of Listings}\n"
        .. "\\providecommand{\\listoflistings}{\\listof{listing}{\\listoflistingsname}}\n",
      caption_above_p({ type = "src-block" }, info) and "plaintop" or "plain"
    )
  )
  local colors
  if #themes > 0 then
    local defs = {}
    local global_listed = false
    for _, t in ipairs(themes) do
      global_listed = global_listed or (theme ~= nil and tostring(theme) == t)
      local s = spec(t):gsub("#", "##"):gsub("newcommand", "renewcommand")
      defs[#defs + 1] = fmt("\n\\newcommand{\\engravedtheme%s}{%%\n%s\n}", theme_letters(t), s)
    end
    colors = table.concat(defs, "\n")
      .. "\n\n"
      .. (global_listed and ("\\engravedtheme" .. theme_letters(theme) .. "\n") or spec(theme))
  else
    colors = spec(theme)
  end
  return "\n% Setup for code blocks [1/2]\n\n"
    .. pre
    .. "\n\n% Setup for code blocks [2/2]: syntax highlighting colors\n\n"
    .. colors
    .. "\n"
end

--- org-latex-src--engrave-mathescape-p
local function engrave_mathescape_p(info, options)
  local function status(opts)
    for _, o in ipairs(opts or {}) do
      local k, v = o[1], o[2]
      local r
      if v == nil then
        local l = "," .. k .. ","
        if l:find(",mathescape=false,", 1, true) then
          r = "no"
        elseif l:find(",mathescape,", 1, true) or l:find(",mathescape=true,", 1, true) then
          r = "yes"
        end
      elseif k == "mathescape" then
        r = (v == "true" and "yes") or (v == "false" and "no") or nil
      end
      if r then
        return r
      end
    end
  end
  return (status(info.latex_engraved_options) or status(options)) == "yes"
end

--- org-latex-src--engrave-code: CONTENT engraved in a Code/Verbatim
--- environment, or a \Verb command when INLINE.
local function engrave_code(content, lang, theme, options, inline, mathescape)
  local E = require("org.export.engrave")
  local code = content:gsub("\n$", "")
  local engraved = E.engrave(code, lang, E.get_theme(theme), mathescape)
  local opts = (options and #options > 0) and ("[" .. make_option_string(options) .. "]") or ""
  local wrapped = inline and ("\\Verb" .. opts .. "{" .. engraved .. "}")
    or ("\\begin{Code}\n\\begin{Verbatim}" .. opts .. "\n" .. engraved .. "\n\\end{Verbatim}\n\\end{Code}")
  if theme then
    return "{\\engravedtheme" .. theme_letters(theme) .. wrapped .. "}"
  end
  return wrapped
end
M.engrave_code = engrave_code

-- Locals the later parts share
shared.engrave_mathescape_p = engrave_mathescape_p
shared.engrave_code = engrave_code
