---@mod org.export.latex.src LaTeX source blocks
---
--- The src-block transcoder for every org-latex-src-block-backend,
--- statistics cookies, subscripts and superscripts.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local nw = ox.nw
local fmt = string.format

local T = shared.T
local caption_above_p = shared.caption_above_p
local engrave_code = shared.engrave_code
local engrave_mathescape_p = shared.engrave_mathescape_p
local langs_lookup = shared.langs_lookup
local lcfg = shared.lcfg
local make_option_string = shared.make_option_string

local function code_with_refs(el, retain_labels)
  local code, refs = ox.unravel_code(el)
  local max_width = 0
  for _, l in ipairs(vim.split(code, "\n", { plain = true })) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(l))
  end
  return ox.format_code(code, function(loc, _, ref)
    if ref then
      return loc .. string.rep(" ", max_width - #loc + 6) .. fmt("(%s)", ref)
    end
    return loc
  end, nil, retain_labels and refs or nil)
end

T["src-block"] = function(el, _, info)
  if not nw(el.value) then
    return nil
  end
  local lang = el.language
  local caption = el.caption
  local above = caption_above_p(el, info)
  local label = el.name
  local customs = lcfg().custom_lang_environments or {}
  local custom_env = lang and customs[lang]
  local num_start = ox.get_loc(el, info)
  local retain = el.retain_labels
  local attributes = ox.read_attribute("attr_latex", el)
  local float = attributes.float
  local backend = info.latex_src_block_backend
  if backend == "engraved" and lang then
    -- org-latex-src-block--engraved
    local cap = M.caption_label_string(el, info)
    local placement = (attributes.placement and attributes.placement:gsub("^%[(.*)%]$", "%1"))
      or info.latex_default_figure_position
    local multicol = float == "multicolumn"
    local open, close = "", ""
    if caption or multicol then
      open = "\\begin{listing" .. (multicol and "*" or "") .. "}[" .. placement .. "]\n" .. (above and cap or "")
      close = "\n" .. (above and "" or cap) .. "\\end{listing" .. (multicol and "*" or "") .. "}"
    elseif float == "t" then
      open = "\\begin{listing}[" .. placement .. "]\n"
      close = "\n\\end{listing}"
    end
    local options = {}
    if num_start then
      local has_linenos = false
      for _, o in ipairs(info.latex_engraved_options or {}) do
        has_linenos = has_linenos or o[1] == "linenos"
      end
      if not has_linenos then
        options = { { "linenos" }, { "firstnumber", tostring(num_start + 1) } }
      end
    end
    if attributes.options then
      options[#options + 1] = { attributes.options }
    end
    local body = engrave_code(
      code_with_refs(el, retain),
      lang,
      attributes["engraved-theme"],
      options,
      false,
      engrave_mathescape_p(info, options)
    )
    return open .. body .. close
  end
  if backend == "verbatim" or not lang or (backend ~= "minted" and backend ~= "listings" and not custom_env) then
    local cap = M.caption_label_string(el, info)
    local verbatim = fmt("\\begin{verbatim}\n%s\\end{verbatim}", ox.format_code_default(el, info))
    if float == "multicolumn" then
      return fmt(
        "\\begin{figure*}[%s]\n%s%s\n%s\\end{figure*}",
        info.latex_default_figure_position,
        above and cap or "",
        verbatim,
        above and "" or cap
      )
    elseif caption then
      return (above and cap or "") .. verbatim .. (above and "" or ("\n" .. cap))
    end
    return verbatim
  elseif custom_env and backend ~= "minted" and backend ~= "listings" then
    local cap = M.caption_label_string(el, info)
    local formatted = ox.format_code_default(el, info)
    if custom_env:match("^[%w]+$") then
      return fmt(
        "\\begin{%s}\n%s\\end{%s}\n",
        custom_env,
        (above and cap or "") .. formatted .. ((not above) and cap or ""),
        custom_env
      )
    end
    return (
      custom_env:gsub("%%(.)", function(c)
        return ({
          s = formatted,
          c = caption and ox.data(ox.get_caption(el), info) or "",
          f = float or "",
          l = M.label(el, info) or "",
          o = attributes.options or "",
        })[c] or ("%" .. c)
      end)
    )
  elseif backend == "minted" then
    local cap = M.caption_label_string(el, info)
    local placement = (attributes.placement and attributes.placement:gsub("^%[(.*)%]$", "%1"))
      or info.latex_default_figure_position
    local multicol = float == "multicolumn"
    local open, close = "", ""
    if caption or multicol then
      open = "\\begin{listing" .. (multicol and "*" or "") .. "}[" .. placement .. "]\n" .. (above and cap or "")
      close = "\n" .. (above and "" or cap) .. "\\end{listing" .. (multicol and "*" or "") .. "}"
    elseif float == "t" then
      open = "\\begin{listing}[" .. placement .. "]\n"
      close = "\n\\end{listing}"
    end
    local options = vim.deepcopy(info.latex_minted_options or {})
    local has_linenos = false
    for _, o in ipairs(options) do
      if o[1] == "linenos" then
        has_linenos = true
      end
    end
    if num_start and not has_linenos then
      options = vim.list_extend({ { "linenos" }, { "firstnumber", tostring(num_start + 1) } }, options)
    end
    local opts = make_option_string(options) .. (attributes.options and ("," .. attributes.options) or "")
    local mlang = langs_lookup(info.latex_minted_langs, lang) or lang:lower()
    return open .. fmt("\\begin{minted}[%s]{%s}\n%s\\end{minted}", opts, mlang, code_with_refs(el, retain)) .. close
  else
    local llang = langs_lookup(info.latex_listings_langs, lang) or lang
    local caption_str
    if caption then
      local main = ox.get_caption(el)
      local secondary = ox.get_caption(el, true)
      if not secondary then
        caption_str = fmt("{%s}", ox.data(main, info))
      else
        caption_str = fmt("{[%s]%s}", ox.data(secondary, info), ox.data(main, info))
      end
    end
    local lst = vim.deepcopy(info.latex_listings_options or {})
    local opts = vim.deepcopy(lst)
    local has = function(k)
      for _, o in ipairs(lst) do
        if o[1] == k then
          return true
        end
      end
      return false
    end
    if not float and vim.tbl_contains(attributes._keys, "float") then
      -- no float
    elseif float == "multicolumn" then
      opts[#opts + 1] = { "float", "*" }
    elseif float and not has("float") then
      opts[#opts + 1] = { "float", info.latex_default_figure_position }
    end
    if not info.latex_listings_src_omit_language then
      opts[#opts + 1] = { "language", llang }
    end
    if label then
      opts[#opts + 1] = { "label", M.label(el, info) }
    end
    if caption_str then
      opts[#opts + 1] = { "caption", caption_str }
      opts[#opts + 1] = { "captionpos", above and "t" or "b" }
    end
    if not has("numbers") then
      if not num_start then
        opts[#opts + 1] = { "numbers", "none" }
      else
        opts[#opts + 1] = { "firstnumber", tostring(num_start + 1) }
        opts[#opts + 1] = { "numbers", "left" }
      end
    end
    return fmt(
      "\\begin{lstlisting}[%s]\n%s\\end{lstlisting}",
      make_option_string(opts) .. (attributes.options and ("," .. attributes.options) or ""),
      code_with_refs(el, retain)
    )
  end
end

T["statistics-cookie"] = function(el)
  return (el.value:gsub("%%", "\\%%"))
end

T.subscript = function(_, contents)
  return fmt("\\textsubscript{%s}", contents or "")
end

T.superscript = function(_, contents)
  return fmt("\\textsuperscript{%s}", contents or "")
end
