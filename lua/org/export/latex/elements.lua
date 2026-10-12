---@mod org.export.latex.elements LaTeX transcoders: rules, inline source, items, keywords, LaTeX
---
--- From horizontal-rule to line-break.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local T = shared.T
local caption_above_p = shared.caption_above_p
local delayed_footnotes = shared.delayed_footnotes
local engrave_code = shared.engrave_code
local environment_type = shared.environment_type
local find_verb_separator = shared.find_verb_separator
local lcfg = shared.lcfg
local make_option_string = shared.make_option_string
local protect_text = shared.protect_text
local text_markup = shared.text_markup
local wrap_label = shared.wrap_label

T["horizontal-rule"] = function(el, _, info)
  local attr = ox.read_attribute("attr_latex", el)
  local prev = ox.get_previous_element(el, info)
  local nl = (prev and (prev.post_blank or 0) == 0) and "\n" or ""
  return nl
    .. wrap_label(el, fmt("\\noindent\\rule{%s}{%s}", attr.width or "\\textwidth", attr.thickness or "0.5pt"), info)
end

local function langs_lookup(list, lang)
  for _, x in ipairs(list or {}) do
    if x[1] == lang then
      return x[2]
    end
  end
end

T["inline-src-block"] = function(el, _, info)
  local code, lang = el.value, el.language
  local backend = info.latex_src_block_backend
  if backend == "minted" and lang then
    local mlang = langs_lookup(info.latex_minted_langs, lang) or lang:lower()
    local options = make_option_string(info.latex_minted_options)
    return fmt("\\mintinline%s{%s}{%s}", options == "" and "" or fmt("[%s]", options), mlang, code)
  elseif backend == "engraved" and lang then
    return engrave_code(code, lang, nil, info.latex_engraved_options, true)
  elseif backend == "listings" and lang then
    local llang = langs_lookup(info.latex_listings_langs, lang) or lang
    local sep = find_verb_separator(code)
    local options =
      make_option_string(vim.list_extend(vim.deepcopy(info.latex_listings_options or {}), { { "language", llang } }))
    return fmt("\\lstinline[%s]", options) .. sep .. code .. sep
  end
  return text_markup(code, "code", info)
end

T.inlinetask = function(el, contents, info)
  local title = ox.data(el.title, info)
  local todo = info.with_todo_keywords and el.todo_keyword or nil
  local tags = info.with_tags and ox.get_tags(el, info) or nil
  if tags and #tags == 0 then
    tags = nil
  end
  local priority = info.with_priority and el.priority or nil
  contents = (M.label(el, info) or "") .. (contents or "")
  local f = lcfg().format_inlinetask_function
  if type(f) == "function" then
    return f(todo, el.todo_type, priority, title, tags, contents, info)
  end
  local full = (todo and fmt("\\textbf{\\textsf{\\textsc{%s}}} ", todo) or "")
    .. (priority and fmt("\\framebox{\\#%s} ", priority) or "")
    .. title
  if tags then
    local p = {}
    for i, t in ipairs(tags) do
      p[i] = protect_text(t)
    end
    full = full .. fmt("\\hfill{}\\textsc{%s}", ":" .. table.concat(p, ":") .. ":")
  end
  return "\\begin{center}\n"
    .. "\\fbox{\n"
    .. "\\begin{minipage}[c]{.6\\linewidth}\n"
    .. full
    .. "\n\n"
    .. (nw(contents) and ("\\rule[.8em]{\\linewidth}{2pt}\n\n" .. contents) or "")
    .. "\\end{minipage}\n"
    .. "}\n"
    .. "\\end{center}"
end

T.item = function(el, contents, info)
  local list = el.parent
  local orderedp = list.list_type == "ordered"
  local level = 0
  local p = el.parent
  while p and (p.type == "plain-list" or p.type == "item") do
    if p.type == "plain-list" and p.list_type == "ordered" then
      level = level + 1
    end
    p = p.parent
  end
  local count = el.counter
  -- (nth (1- level) ...): nth of -1 is the first element, so an item of an
  -- unordered list sets enumi
  local counter = (count and level < 5)
      and fmt("\\setcounter{enum%s}{%s}\n", ({ "i", "ii", "iii", "iv" })[math.max(level, 1)], count - 1)
    or ""
  local checkbox = ({ on = "$\\boxtimes$", off = "$\\square$", trans = "$\\boxminus$" })[el.checkbox or ""]
  local tag = el.tag and ox.data(el.tag, info) or nil
  local tag_fn = tag and delayed_footnotes(el.tag, info) or ""
  local head
  if checkbox and tag then
    head = fmt(orderedp and "{%s %s} %s" or "[{%s %s}] %s", checkbox, tag, tag_fn)
  elseif checkbox or tag then
    head = fmt(orderedp and "{%s} %s" or "[{%s}] %s", checkbox or tag, tag_fn)
  elseif contents and contents:match("^[ \t]*%[") then
    local e = el.contents[1]
    local o = e and e.type == "paragraph" and e.contents[1]
    if not (o and o.type == "export-snippet" and o.back_end == "latex") then
      head = "\\relax "
    else
      head = " "
    end
  else
    head = " "
  end
  return counter .. "\\item" .. head .. (contents and trim(contents) or "")
end

T.keyword = function(el, _, info)
  local key, value = el.key, el.value
  if key == "LATEX" then
    return value
  elseif key == "INDEX" then
    return fmt("\\index{%s}", value)
  elseif key == "TOC" then
    local low = value:lower()
    if low:match("%f[%w]headlines%f[%W]") then
      local localp = low:match("%f[%w]local%f[%W]") ~= nil
      local parent = element.lineage(el, "headline")
      local level = (localp and parent) and ox.get_relative_level(parent, info) or 0
      local n = value:match("%f[%d](%d+)%f[%D]")
      local depth = n and fmt("\\setcounter{tocdepth}{%d}", tonumber(n) + level) or nil
      if localp and parent then
        return fmt("\\startcontents[level-%d]\n\\printcontents[level-%d]{}{0}{%s}", level, level, depth or "")
      end
      return (depth and (depth .. "\n") or "") .. "\\tableofcontents"
    elseif low:match("%f[%w]tables%f[%W]") then
      return "\\listoftables"
    elseif low:match("%f[%w]listings%f[%W]") then
      local b = info.latex_src_block_backend
      if b == nil then
        return "\\listoffigures"
      elseif b == "minted" or b == "engraved" then
        return "\\listoflistings"
      end
      return "\\lstlistoflistings"
    end
  end
end

T["latex-environment"] = function(el, _, info)
  if not info.with_latex then
    return nil
  end
  local lines = element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true }))
  local value = table.concat(lines, "\n") .. "\n"
  local t = environment_type(el)
  local caption = t == "math" and M.label(el, info, nil, true) or M.caption_label_string(el, info)
  local above = t == "math" or caption_above_p(el, info)
  if not (el.name or el.caption) then
    return value
  end
  if above then
    local nl = value:find("\n")
    return value:sub(1, nl) .. caption .. value:sub(nl + 1)
  end
  -- before the last line
  local last_nl = value:sub(1, -2):match(".*()\n")
  if last_nl then
    return value:sub(1, last_nl) .. caption .. value:sub(last_nl + 1)
  end
  return caption .. value
end

T["latex-fragment"] = function(el)
  local v = el.value
  if v:match("^%$[^%$]") then
    return v:sub(2, -2)
  elseif v:sub(1, 2) == "\\(" then
    return v:sub(3, -3)
  end
  return v
end

T["latex-math-block"] = function(_, contents)
  if nw(contents) then
    return fmt("\\(%s\\)", trim(contents))
  end
end

T["latex-matrices"] = function(el, contents, info)
  if el.markup == "inline" then
    return fmt("\\(%s\\)", contents)
  elseif el.markup == "equation" then
    local caption = M.caption_label_string(el, info)
    local above = caption_above_p(el, info)
    return "\\begin{equation}\n"
      .. (above and caption or "")
      .. contents
      .. ((not above) and caption or "")
      .. "\\end{equation}"
  end
  return fmt("\\[\n%s\\]", contents)
end

T["line-break"] = function()
  return "\\\\\n"
end

-- Locals the later parts share
shared.langs_lookup = langs_lookup
