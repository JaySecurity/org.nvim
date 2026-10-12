---@mod org.export.latex.preamble LaTeX preamble
---
--- Document classes, packages and the header (org-latex-make-preamble,
--- org-splice-latex-header), compiler and language guessing.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local data = require("org.export.latex_data")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local nw = ox.nw
local fmt = string.format

local lcfg = shared.lcfg

---------------------------------------------------------------------------
-- Preamble and template
---------------------------------------------------------------------------

local COMPILERS = { pdflatex = true, xelatex = true, lualatex = true }

local function remove_packages(pkgs, info)
  local compiler = (info.latex_compiler or ""):lower()
  if not COMPILERS[compiler] then
    return pkgs
  end
  local out = {}
  for _, p in ipairs(pkgs) do
    if type(p) ~= "table" or not p[4] then
      out[#out + 1] = p
    else
      local ok = false
      for _, c in ipairs(p[4]) do
        if c:lower() == compiler then
          ok = true
        end
      end
      if ok then
        out[#out + 1] = p
      end
    end
  end
  return out
end

local function packages_to_string(pkgs, snippets, newline)
  local parts = {}
  for _, p in ipairs(pkgs) do
    if type(p) == "string" then
      parts[#parts + 1] = p
    elseif snippets and #p >= 3 and not p[3] then
      parts[#parts + 1] = fmt("%% Package %s omitted", p[2])
    elseif p[1] == "" then
      parts[#parts + 1] = fmt("\\usepackage{%s}", p[2])
    else
      parts[#parts + 1] = fmt("\\usepackage[%s]{%s}", p[1], p[2])
    end
  end
  local s = table.concat(parts, "\n")
  return newline and (s .. "\n") or s
end

--- org-splice-latex-header
function M.splice_header(tpl, def_pkg, pkg, snippets, extra)
  local ending = ""
  local a, b, no = tpl:find("\n?[ \t]*%[(N?O?%-?)DEFAULT%-PACKAGES%][ \t]*\n?")
  -- anchored at line start
  local s1, e1 = tpl:find("%[NO%-DEFAULT%-PACKAGES%][ \t]*\n?")
  local s2, e2 = tpl:find("%[DEFAULT%-PACKAGES%][ \t]*\n?")
  _ = a
  _ = b
  _ = no
  if s1 then
    local ls = s1
    while ls > 1 and tpl:sub(ls - 1, ls - 1):match("[ \t]") do
      ls = ls - 1
    end
    tpl = tpl:sub(1, ls - 1) .. tpl:sub(e1 + 1)
  elseif s2 then
    local ls = s2
    while ls > 1 and tpl:sub(ls - 1, ls - 1):match("[ \t]") do
      ls = ls - 1
    end
    local rpl = (#def_pkg > 0) and packages_to_string(def_pkg, snippets, true) or ""
    tpl = tpl:sub(1, ls - 1) .. rpl .. tpl:sub(e2 + 1)
  elseif #def_pkg > 0 then
    ending = packages_to_string(def_pkg, snippets)
  end
  local s3, e3 = tpl:find("%[NO%-PACKAGES%][ \t]*\n?")
  local s4, e4 = tpl:find("%[PACKAGES%][ \t]*\n?")
  if s3 then
    tpl = tpl:sub(1, s3 - 1) .. tpl:sub(e3 + 1)
  elseif s4 then
    local rpl = (#pkg > 0) and packages_to_string(pkg, snippets, true) or ""
    tpl = tpl:sub(1, s4 - 1) .. rpl .. tpl:sub(e4 + 1)
  elseif #pkg > 0 then
    ending = ending .. "\n" .. packages_to_string(pkg, snippets)
  end
  local s5, e5 = tpl:find("%[NO%-EXTRA%][ \t]*\n?")
  local s6, e6 = tpl:find("%[EXTRA%][ \t]*\n?")
  if s5 then
    tpl = tpl:sub(1, s5 - 1) .. tpl:sub(e5 + 1)
  elseif s6 then
    local rpl = extra and (extra .. "\n") or ""
    tpl = tpl:sub(1, s6 - 1) .. rpl .. tpl:sub(e6 + 1)
  elseif extra and extra:find("%S") then
    ending = ending .. "\n" .. extra
  end
  if ending:find("%S") then
    return tpl .. "\n" .. ending
  end
  return tpl
end

local function guess_inputenc(header)
  local cs = lcfg().inputenc or "utf8"
  local alist = lcfg().inputenc_alist or {}
  cs = alist[cs] or cs
  return (
    header:gsub("\\usepackage%[AUTO%]{inputenc}", function()
      return "\\usepackage[" .. cs .. "]{inputenc}"
    end)
  )
end

local function guess_babel_language(header, info)
  local code = info.language
  local plist = data.languages[code] or {}
  local language = plist.babel
  local ini_only = plist.babel_ini_only
  local ini_alt = plist.babel_ini_alt
  if not ini_only and type(code) == "string" then
    local a, b, opts = header:find("\\usepackage%[([^%]]*)%]{babel}")
    if a then
      local options = vim.split(opts, ",[ \t]*")
      local new
      if vim.tbl_contains(options, language) then
        new = vim.tbl_filter(function(o)
          return o ~= "AUTO"
        end, options)
      elseif vim.tbl_contains(options, "AUTO") then
        new = options
      else
        new = vim.list_extend(vim.deepcopy(options), { language })
      end
      local mapped = {}
      for i, o in ipairs(new) do
        mapped[i] = o == "AUTO" and language or o
      end
      local repl = "\\usepackage[" .. table.concat(mapped, ", ") .. "]{babel}"
      header = header:sub(1, a - 1) .. repl .. header:sub(b + 1)
    end
  end
  local prov = header:match("\\babelprovide%[.-%]{(.-)}")
  if prov == "AUTO" then
    header = header:gsub("(\\babelprovide%[.-%]){AUTO}", function(pre)
      return pre .. "{" .. (ini_alt or language or ini_only or "") .. "}"
    end)
  end
  return header
end

local function guess_polyglossia_language(header, info)
  local language = info.language
  if type(language) ~= "string" then
    return header
  end
  local a, b, options = header:find("\\usepackage%[([^%]]-)%]{polyglossia}\n")
  if not a then
    return header
  end
  local langs = {}
  local seen = {}
  local list = vim.split((options:gsub("AUTO", require("org.utils").gsub_escape(language))), ",[ \t]*")
  for i = #list, 1, -1 do
    if not seen[list[i]] then
      seen[list[i]] = true
      langs[#langs + 1] = list[i]
    end
  end
  local main_set = header:find("\\setmainlanguage{.-}") ~= nil
  local out = { "\\usepackage{polyglossia}\n" }
  for _, l in ipairs(langs) do
    local plist = data.languages[language] or {}
    local variant = plist.polyglossia_variant
    local name = l == language and plist.polyglossia or l
    if main_set then
      out[#out + 1] = fmt("\\setotherlanguage{%s}\n", name)
    else
      main_set = true
      out[#out + 1] = fmt("\\setmainlanguage%s{%s}\n", variant and fmt("[variant=%s]", variant) or "", name)
    end
  end
  return header:sub(1, a - 1) .. table.concat(out) .. header:sub(b + 1)
end

function M.find_class(info, name)
  for _, c in ipairs(info.latex_classes) do
    if c[1] == name then
      return c
    end
  end
end

function M.make_preamble(info, template, snippet)
  local class = info.latex_class
  local class_template = template
  if not class_template then
    local c = M.find_class(info, class)
    if not c or type(c[2]) ~= "string" then
      error(fmt("Unknown LaTeX class `%s'", tostring(class)), 0)
    end
    local header = c[2]
    local opts = info.latex_class_options
    if opts then
      header = header:gsub("^[ \t]*\\documentclass(%[[^%]]*%])", function()
        return "\\documentclass" .. opts
      end, 1)
      if not header:find("\\documentclass" .. vim.pesc(opts), 1) then
        header = header:gsub("^([ \t]*\\documentclass)", "%1" .. opts:gsub("%%", "%%%%"), 1)
      end
    end
    local parts = {}
    if not snippet and info.latex_class_pre then
      parts[#parts + 1] = ox.normalize_string(info.latex_class_pre)
    end
    parts[#parts + 1] = ox.normalize_string(header)
    class_template = table.concat(parts)
  end
  local extra_parts = {}
  for _, x in ipairs({
    info.latex_header,
    (not snippet) and info.latex_header_extra or nil,
    ((not snippet) and info.latex_use_sans) and "\\renewcommand*\\familydefault{\\sfdefault}" or nil,
  }) do
    if x then
      extra_parts[#extra_parts + 1] = ox.normalize_string(x)
    end
  end
  local header = M.splice_header(
    class_template,
    remove_packages(info.latex_default_packages or data.default_packages, info),
    remove_packages(info.latex_packages or {}, info),
    snippet,
    table.concat(extra_parts)
  )
  return guess_polyglossia_language(guess_babel_language(guess_inputenc(ox.normalize_string(header)), info), info)
end

--- The "% Intended LaTeX compiler" line (org-latex-compiler-file-string,
--- export.latex.compiler_file_string), for pdflatex, xelatex and lualatex.
function M.compiler_file_string(info)
  local compiler = info.latex_compiler
  local f = lcfg().compiler_file_string
  if f == nil then
    f = "%% Intended LaTeX compiler: %s\n"
  end
  if not (f and nw(f) and COMPILERS[compiler or ""]) then
    return nil
  end
  return (f:gsub("%%(.)", function(c)
    return c == "s" and compiler or c == "%" and "%" or "%" .. c
  end))
end

--- Known warnings found in a LaTeX log (org-latex--collect-warnings with
--- org-latex-known-warnings), or "error" when the log has an error.
function M.log_warnings(text)
  local warnings = {}
  if text:match("\n!") and not text:match("\n![^\n]*Unicode character") then
    return "error"
  end
  for _, w in ipairs(lcfg().known_warnings or data.known_warnings) do -- org-latex-known-warnings
    local re = vim.regex(w[1])
    if re:match_str(text) then
      warnings[#warnings + 1] = w[2]
    end
  end
  return warnings
end
