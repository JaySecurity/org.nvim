---@mod org.export.latex.link LaTeX links and inline images
---
--- Inline images, links, paragraphs and plain lists.
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
local protect_text = shared.protect_text
local wrap_label = shared.wrap_label

M.inline_image_rules = {
  file = { "pdf", "jpeg", "jpg", "png", "ps", "eps", "tikz", "pgf", "svg" },
  https = { "jpeg", "jpg", "png", "ps", "eps", "tikz", "pgf", "svg" },
}

local function inline_image(link, info)
  local parent = element.parent_element(link)
  local path = link.path
  if require("org.utils").is_absolute(path) or path:match("^~") then
    path = vim.fn.fnamemodify(require("org.utils").expand_vars(path), ":p")
  end
  local filetype = path:match("%.([%w]+)$")
  filetype = filetype and filetype:lower()
  local caption = M.caption_label_string(parent, info)
  local above = caption_above_p(link, info)
  local attr = ox.read_attribute("attr_latex", parent)
  local float
  local lone = true
  for _, node in ipairs(parent.contents) do
    if not info.ignore[node] then
      if node.type == "plain-text" and not nw(node.value) then
        -- ignore blanks
      elseif node ~= link and not (link.parent and link.parent ~= parent and node == link.parent) then
        lone = false
      end
    end
  end
  local f = attr.float
  if not lone then
    float = nil
  elseif f == "wrap" then
    float = "wrap"
  elseif f == "sideways" then
    float = "sideways"
  elseif f == "multicolumn" then
    float = "multicolumn"
  elseif f == "t" then
    float = "figure"
  elseif vim.tbl_contains(attr._keys, "float") and not f then
    float = "nonfloat"
  elseif f then
    float = f
  elseif parent.caption or nw(attr.caption) then
    float = "figure"
  else
    float = "nonfloat"
  end
  local placement
  if attr.placement then
    placement = attr.placement
  elseif float == "wrap" then
    placement = "{l}{0.5\\textwidth}"
  elseif float == "figure" then
    placement = fmt("[%s]", info.latex_default_figure_position)
  else
    placement = ""
  end
  local center
  if link.parent and link.parent.type == "link" then
    center = false
  elseif vim.tbl_contains(attr._keys, "center") then
    center = attr.center
  else
    center = info.latex_images_centered
  end
  local comment = attr["comment-include"] and "%" or ""
  local scale = float == "wrap" and "" or (attr.scale or info.latex_image_default_scale)
  local width
  if nw(scale) then
    width = ""
  elseif attr.width then
    width = attr.width
  elseif attr.height then
    width = ""
  elseif float == "wrap" then
    width = "0.48\\textwidth"
  else
    width = info.latex_image_default_width
  end
  local height
  if nw(scale) then
    height = ""
  elseif attr.height then
    height = attr.height
  elseif attr.width or float == "figure" or float == "wrap" then
    height = ""
  else
    height = info.latex_image_default_height
  end
  local options = attr.options or info.latex_image_default_option
  options = options:match("^%[(.*)%]$") or options
  local code
  if filetype == "tikz" or filetype == "pgf" then
    code = fmt("\\input{%s}", path)
    if nw(options) then
      code = fmt("\\begin{tikzpicture}[%s]\n%s\n\\end{tikzpicture}", options, code)
    end
    if nw(scale) then
      code = fmt("\\scalebox{%s}{%s}", scale, code)
    elseif nw(width) or nw(height) then
      code = fmt("\\resizebox{%s}{%s}{%s}", nw(width) and width or "!", nw(height) and height or "!", code)
    end
  else
    if nw(scale) then
      options = options .. ",scale=" .. scale
    else
      if nw(width) then
        options = options .. ",width=" .. width
      end
      if nw(height) then
        options = options .. ",height=" .. height
      end
    end
    local so = link.search_option
    if so and filetype == "pdf" and so:match("^%d+$") and not options:find("page=", 1, true) then
      options = options .. ",page=" .. so
    end
    local optstr = ""
    if nw(options) then
      optstr = options:sub(1, 1) == "," and fmt("[%s]", options:sub(2)) or fmt("[%s]", options)
    end
    local p = path
    if filetype == "svg" and p:find("[\128-\255]") then
      p = "\\detokenize{" .. p .. "}"
    end
    code = fmt("\\includegraphics%s{%s}", optstr, p)
    if filetype == "svg" then
      code = code:gsub("^\\includegraphics", "\\includesvg"):gsub("%.svg}", "}")
    end
  end
  local cap_above = above and caption or ""
  local cap_below = above and "" or caption
  local c = center and "\\centering" or ""
  if type(float) == "string" and not ({ wrap = 1, sideways = 1, multicolumn = 1, figure = 1, nonfloat = 1 })[float] then
    return fmt(
      "\\begin{%s}%s\n%s%s\n%s%s\n%s\\end{%s}",
      float,
      placement,
      cap_above,
      c,
      comment,
      code,
      cap_below,
      float
    )
  elseif float == "wrap" then
    return fmt(
      "\\begin{wrapfigure}%s\n%s%s\n%s%s\n%s\\end{wrapfigure}",
      placement,
      cap_above,
      c,
      comment,
      code,
      cap_below
    )
  elseif float == "sideways" then
    return fmt("\\begin{sidewaysfigure}\n%s%s\n%s%s\n%s\\end{sidewaysfigure}", cap_above, c, comment, code, cap_below)
  elseif float == "multicolumn" then
    return fmt("\\begin{figure*}%s\n%s%s\n%s%s\n%s\\end{figure*}", placement, cap_above, c, comment, code, cap_below)
  elseif float == "figure" then
    return fmt("\\begin{figure}%s\n%s%s\n%s%s\n%s\\end{figure}", placement, cap_above, c, comment, code, cap_below)
  elseif center then
    return fmt("\\begin{center}\n%s%s\n%s\\end{center}", cap_above, code, cap_below)
  end
  return (above and caption or "") .. code .. (above and caption or "")
end

T.link = function(el, desc, info)
  local ltype = el.link_type
  local raw = el.path
  desc = (desc ~= nil and desc ~= "") and desc or nil
  local imagep = ox.inline_image_p(el, info.latex_inline_image_rules)
  local path
  if ltype == "file" then
    path = protect_text(ox.file_uri(raw))
  else
    path = protect_text(ltype .. ":" .. raw)
  end
  local custom = ox.custom_protocol_maybe(el, desc, "latex", info)
  if custom then
    return custom
  end
  if imagep then
    return inline_image(el, info)
  end
  if ltype == "radio" then
    local dest = ox.resolve_radio_link(el, info)
    if not dest then
      return desc
    end
    return fmt("\\hyperref[%s]{%s}", ox.get_reference(dest, info), desc or "")
  end
  if ltype == "custom-id" or ltype == "fuzzy" or ltype == "id" then
    local dest = ltype == "fuzzy" and ox.resolve_fuzzy_link(el, info, { "latex-matrices" })
      or ox.resolve_id_link(el, info)
    if dest.type == "plain-text" then
      if desc then
        return fmt("\\href{%s}{%s}", dest.value, desc)
      end
      return fmt("\\url{%s}", dest.value)
    elseif dest.type == "headline" then
      local label = M.label(dest, info, true)
      if not desc and ox.numbered_headline_p(dest, info) then
        return fmt(info.latex_reference_command, label)
      end
      return fmt("\\hyperref[%s]{%s}", label, desc or ox.data(dest.title, info))
    else
      local ref = M.label(dest, info, true)
      if not desc then
        return fmt(info.latex_reference_command, ref)
      end
      return fmt("\\hyperref[%s]{%s}", ref, desc)
    end
  end
  if ltype == "coderef" then
    local f = ox.get_coderef_format(path, desc)
    local r = ox.resolve_coderef(raw, info)
    return (f:gsub("%%s", function()
      return tostring(r)
    end))
  end
  if path and desc then
    return fmt("\\href{%s}{%s}", path, desc)
  elseif path then
    return fmt("\\url{%s}", path)
  end
  return fmt(info.latex_link_with_unknown_path_format, desc or "")
end

T["node-property"] = function(el)
  return fmt("%s:%s", el.key, el.value and (" " .. el.value) or "")
end

T.paragraph = function(_, contents)
  return ((contents or ""):gsub("\n[ \t\n]*\n", "\n"))
end

T["plain-list"] = function(el, contents, info)
  local attr = ox.read_attribute("attr_latex", el)
  local env = attr.environment
    or (el.list_type == "ordered" and "enumerate" or (el.list_type == "descriptive" and "description" or "itemize"))
  return wrap_label(el, fmt("\\begin{%s}%s\n%s\\end{%s}", env, attr.options or "", contents or "", env), info)
end
