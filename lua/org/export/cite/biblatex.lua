---@mod org.export.cite.biblatex The biblatex citation processor
---
--- Port of oc-biblatex.el (LaTeX only): styles, shortcuts and
--- multi-citations.
---
--- Part of org.export.cite, which loads it.

local ox = require("org.export.ox")
local M = require("org.export.cite")
local shared = require("org.export.cite.shared")

local fmt = string.format
local trim = ox.trim
local opt, data_trim = shared.opt, shared.data_trim

---------------------------------------------------------------------------
-- biblatex processor
---------------------------------------------------------------------------

local biblatex = {}

function biblatex.package_options(initial, style)
  local no_style = {}
  if initial then
    local s = initial:match("^%[(.*)%]$") or initial
    for _, o in ipairs(vim.split(s, ",", { trimempty = true })) do
      o = trim(o)
      if o ~= "" and not (o:match("^bibstyle") or o:match("^citestyle") or o:match("^style")) then
        no_style[#no_style + 1] = o
      end
    end
  end
  local style_opts = {}
  if style then
    local kv = style:match("^[^,=]+=[^,]+,[^=]+=[^,]+$") ~= nil
    local a, b = style:match("^(.-)/(.*)$")
    if not a then
      style_opts[1] = kv and style or ("style=" .. style)
    else
      style_opts = { "bibstyle=" .. a, "citestyle=" .. b }
    end
  end
  local all = vim.list_extend(no_style, style_opts)
  if #all > 0 then
    return "[" .. table.concat(all, ",") .. "]"
  end
  return ""
end

local function multicite_p(citation)
  local refs = M.get_references(citation)
  if #refs <= 1 then
    return false
  end
  for _, r in ipairs(refs) do
    if r.prefix or r.suffix then
      return true
    end
  end
  return false
end

local function atomic_arguments(refs, info, no_opt)
  local keys = {}
  for i, r in ipairs(refs) do
    keys[i] = r.key
  end
  local mandatory = fmt("{%s}", table.concat(keys, ","))
  if no_opt then
    return mandatory
  end
  local origin = #refs == 1 and refs[1] or refs[1].parent
  local prefix, suffix = origin.prefix, origin.suffix
  return (prefix and fmt("[%s]", data_trim(prefix, info)) or "")
    .. (suffix and fmt("[%s]", data_trim(suffix, info)) or (prefix and "[]" or ""))
    .. mandatory
end

local function multi_arguments(citation, info)
  local gp, gs = citation.prefix, citation.suffix
  local s = (gp and fmt("(%s)", data_trim(gp, info)) or "")
    .. (gs and fmt("(%s)", data_trim(gs, info)) or (gp and "()" or ""))
  for _, r in ipairs(M.get_references(citation)) do
    s = s .. atomic_arguments({ r }, info)
  end
  return s
end

function biblatex.export_citation(citation, style, _, info)
  local shortcuts = opt("biblatex_style_shortcuts", M.BIBLATEX_SHORTCUTS)
  local name = style[1] and (shortcuts[style[1]] or style[1]) or nil
  local variant = style[2] and (shortcuts[style[2]] or style[2]) or nil
  local candidates = {}
  local style_match = false
  local chosen
  for _, s in ipairs(opt("biblatex_styles", M.BIBLATEX_STYLES)) do
    if s[1] == name and s[2] == variant then
      chosen = s
      break
    elseif s[1] == nil and s[2] == nil then
      if #candidates == 0 then
        table.insert(candidates, 1, s)
      end
    elseif s[1] == name and s[2] == nil then
      table.insert(candidates, 1, s)
      style_match = true
    elseif s[1] == nil and s[2] == variant then
      if not style_match then
        table.insert(candidates, 1, s)
      end
    end
  end
  chosen = chosen or candidates[1]
  if not chosen then
    error("Missing default style or variant in export.cite.biblatex_styles", 0)
  end
  local cmd, multi, no_opt = chosen[3], chosen[4], chosen[5]
  if multi and multicite_p(citation) then
    return fmt("\\%s%s", multi, multi_arguments(citation, info))
  end
  return fmt("\\%s%s", cmd, atomic_arguments(M.get_references(citation), info, no_opt))
end

function biblatex.export_bibliography(_, _, _, props)
  local s = "\\printbibliography"
  if props and #props > 0 then
    local results = {}
    local key
    for _, d in ipairs(props) do
      if type(d) == "table" and d.keyword then
        if key then
          results[#results + 1] = key
        end
        key = d.keyword:sub(2)
      else
        local parts = {}
        for _, v in ipairs(vim.split(d, ",", { trimempty = true })) do
          parts[#parts + 1] = (key or "nil") .. "=" .. v
        end
        results[#results + 1] = table.concat(parts, ",")
        key = nil
      end
    end
    s = s .. "[" .. table.concat(results, ",") .. "]"
  end
  return s
end

function biblatex.finalize(output, _, files, style)
  local b = output:find("\\begin{document}", 1, true)
  if not b then
    return output
  end
  local before, after = output:sub(1, b - 1), output:sub(b)
  -- last \usepackage[...]{biblatex} before \begin{document}
  local last_s, last_e, last_opts
  local pos = 1
  while true do
    local s, e = before:find("\\usepackage", pos, true)
    if not s then
      break
    end
    local opts = before:match("^(%b[])", e + 1)
    local k = e + 1 + (opts and #opts or 0)
    if before:sub(k, k + 9) == "{biblatex}" then
      last_s, last_e, last_opts = s, k + 9, opts
    end
    pos = e + 1
  end
  local point
  if not last_s then
    local ins = fmt("\\usepackage%s{biblatex}\n", biblatex.package_options(opt("biblatex_options", nil), style))
    before = before .. ins
    point = #before + 1
  elseif not last_opts then
    -- (search-forward "{"): options land after the first brace, like Emacs
    local brace = before:find("{", last_s, true)
    before = before:sub(1, brace) .. biblatex.package_options(nil, style) .. before:sub(brace + 1)
    point = (before:find("\n", brace, true) or #before) + 1
  else
    local new = biblatex.package_options(last_opts, style)
    local os = last_s + #"\\usepackage"
    before = before:sub(1, os - 1) .. new .. before:sub(os + #last_opts)
    point = (before:find("\n", last_s, true) or #before) + 1
  end
  local text_all = before .. after
  local res = {}
  for _, f in ipairs(files) do
    res[#res + 1] = fmt("\\addbibresource%s{%s}", f:match("^%a[%w+.-]*://") and "[location=remote]" or "", f)
  end
  local ins = table.concat(res, "\n") .. "\n"
  return text_all:sub(1, point - 1) .. ins .. text_all:sub(point)
end

--- org-cite-biblatex-list-styles: styles having at least one variant, in
--- table order; variants and shortcuts in reverse order, like Emacs.
function biblatex.list_styles()
  local shortcuts, variants, order = {}, {}, {}
  local sc = opt("biblatex_style_shortcuts", M.BIBLATEX_SHORTCUTS)
  local names = vim.tbl_keys(sc)
  table.sort(names)
  for _, name in ipairs(names) do
    local full = sc[name]
    shortcuts[full] = shortcuts[full] or {}
    table.insert(shortcuts[full], 1, name)
  end
  for _, s in ipairs(opt("biblatex_styles", M.BIBLATEX_STYLES)) do
    if s[2] then
      local name = s[1] or "nil"
      if not variants[name] then
        variants[name] = {}
        order[#order + 1] = name
      end
      table.insert(variants[name], 1, s[2])
    end
  end
  local out = {}
  for _, name in ipairs(order) do
    local style = { name }
    vim.list_extend(style, shortcuts[name ~= "nil" and name or ""] or {})
    local entry = { style }
    for _, v in ipairs(variants[name]) do
      local variant = { v }
      vim.list_extend(variant, shortcuts[v] or {})
      entry[#entry + 1] = variant
    end
    out[#out + 1] = entry
  end
  return out
end

M.processors.biblatex = {
  export_citation = biblatex.export_citation,
  export_bibliography = biblatex.export_bibliography,
  export_finalizer = biblatex.finalize,
  cite_styles = biblatex.list_styles,
}

return M
