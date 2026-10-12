---@mod org.export.cite.natbib The natbib and bibtex citation processors
---
--- Ports of oc-natbib.el and oc-bibtex.el (LaTeX only).
---
--- Part of org.export.cite, which loads it.

local ox = require("org.export.ox")
local M = require("org.export.cite")
local shared = require("org.export.cite.shared")

local fmt = string.format
local trim = ox.trim
local opt = shared.opt

---------------------------------------------------------------------------
-- natbib and bibtex processors
---------------------------------------------------------------------------

local function data_trim(d, info)
  return trim(ox.data(d, info))
end

local function file_sans_extension(f)
  return (f:gsub("%.[^./]*$", ""))
end

shared.data_trim = data_trim

local natbib = {}

function natbib.command(style)
  local name, v = style[1], style[2]
  if name == "author" or name == "a" then
    if v == "caps" or v == "c" then
      return "\\Citeauthor"
    elseif v == "full" or v == "f" then
      return "\\citeauthor*"
    end
    return "\\citeauthor"
  elseif name == "noauthor" or name == "na" then
    if v == "bare" or v == "b" then
      return "\\citeyear"
    end
    return "\\citeyearpar"
  elseif name == "nocite" or name == "n" then
    return "\\nocite"
  end
  local base = (name == "text" or name == "t") and "t" or "p"
  local map = {
    bare = "\\citeal" .. base,
    b = "\\citeal" .. base,
    caps = "\\Cite" .. base,
    c = "\\Cite" .. base,
    full = "\\cite" .. base .. "*",
    f = "\\cite" .. base .. "*",
    ["bare-caps"] = "\\Citeal" .. base,
    bc = "\\Citeal" .. base,
    ["bare-full"] = "\\citeal" .. base .. "*",
    bf = "\\citeal" .. base .. "*",
    ["caps-full"] = "\\Cite" .. base .. "*",
    cf = "\\Cite" .. base .. "*",
    ["bare-caps-full"] = "\\Citeal" .. base .. "*",
    bcf = "\\Citeal" .. base .. "*",
  }
  return map[v or ""] or ("\\cite" .. base)
end

function natbib.export_citation(citation, style, _, info)
  local prefix, suffix = M.main_affixes(citation)
  local opts = (prefix and fmt("[%s]", data_trim(prefix, info)) or "")
    .. (suffix and fmt("[%s]", data_trim(suffix, info)) or (prefix and "[]" or ""))
  return natbib.command(style) .. opts .. fmt("{%s}", table.concat(M.get_references(citation, true), ","))
end

function natbib.export_bibliography(_, files, style)
  local names = {}
  for i, f in ipairs(files) do
    names[i] = file_sans_extension(f)
  end
  return fmt("\\bibliographystyle{%s}\n", style or opt("natbib_bibliography_style", "unsrtnat"))
    .. fmt("\\bibliography{%s}", table.concat(names, ","))
end

function natbib.finalize(output)
  local b = output:find("\\begin{document}", 1, true)
  if not b then
    return output
  end
  local before = output:sub(1, b - 1)
  if before:find("\\usepackage%b[]{natbib}") or before:find("\\usepackage{natbib}", 1, true) then
    return output
  end
  local options = opt("natbib_options", {})
  local o = #options > 0 and fmt("[%s]", table.concat(options, ",")) or ""
  return before .. fmt("\\usepackage%s{natbib}\n", o) .. output:sub(b)
end

M.processors.natbib = {
  export_citation = natbib.export_citation,
  export_bibliography = natbib.export_bibliography,
  export_finalizer = natbib.finalize,
  cite_styles = {
    { { "author", "a" }, { "caps", "a" }, { "full", "f" } },
    { { "noauthor", "na" }, { "bare", "b" } },
    {
      { "text", "t" },
      { "bare", "b" },
      { "caps", "c" },
      { "full", "f" },
      { "bare-caps", "bc" },
      { "bare-full", "bf" },
      { "caps-full", "cf" },
      { "bare-caps-full", "bcf" },
    },
    {
      { "nil" },
      { "bare", "b" },
      { "caps", "c" },
      { "full", "f" },
      { "bare-caps", "bc" },
      { "bare-full", "bf" },
      { "caps-full", "cf" },
      { "bare-caps-full", "bcf" },
    },
  },
}

local bibtex = {}

function bibtex.export_citation(citation, style, _, info)
  local name = style[1]
  local _, suffix = M.main_affixes(citation)
  return fmt(
    "\\%s%s{%s}",
    (name == "nocite" or name == "n") and "nocite" or "cite",
    suffix and fmt("[%s]", data_trim(suffix, info)) or "",
    table.concat(M.get_references(citation, true), ",")
  )
end

function bibtex.export_bibliography(_, files, style)
  local names = {}
  for i, f in ipairs(files) do
    names[i] = file_sans_extension(f)
  end
  return fmt("\\bibliographystyle{%s}\n", style or opt("bibtex_bibliography_style", "plain"))
    .. fmt("\\bibliography{%s}", table.concat(names, ","))
end

M.processors.bibtex = {
  export_citation = bibtex.export_citation,
  export_bibliography = bibtex.export_bibliography,
  cite_styles = { { { "nocite", "n" } }, { { "nil" } } },
}

return M
