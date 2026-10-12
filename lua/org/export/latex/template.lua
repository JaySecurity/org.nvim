---@mod org.export.latex.template LaTeX document template
---
--- The full document around the transcoded contents (org-latex-template).
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local fmt = string.format

local format_spec = shared.format_spec
local format_spec_apply = shared.format_spec_apply

local function template(contents, info)
  local title = ox.data(info.title, info)
  local spec = format_spec(info)
  local out = {}
  if info.time_stamp_file then
    out[#out + 1] = ox.format_time("%% Created %Y-%m-%d %a %H:%M\n")
  end
  out[#out + 1] = M.compiler_file_string(info)
  out[#out + 1] = M.make_preamble(info)
  if type(info.section_numbers) == "number" then
    out[#out + 1] = fmt("\\setcounter{secnumdepth}{%d}\n", info.section_numbers)
  end
  local author = info.with_author and info.author and ox.data(info.author, info) or nil
  local email = info.with_email and ox.data(info.email, info) or nil
  if author and email and email ~= "" then
    out[#out + 1] = fmt("\\author{%s\\thanks{%s}}\n", author, email)
  elseif author or email then
    out[#out + 1] = fmt("\\author{%s}\n", author or email)
  end
  local date = info.with_date and ox.get_date(info) or nil
  out[#out + 1] = fmt("\\date{%s}\n", type(date) == "string" and date or ox.data(date, info))
  local sub = info.subtitle
  local fsub = sub and info.latex_subtitle_format:gsub("%%s", function()
    return ox.data(sub, info)
  end)
  out[#out + 1] = fmt("\\title{%s%s}\n", title, info.latex_subtitle_separate and "" or (fsub or ""))
  if info.latex_subtitle_separate and sub then
    out[#out + 1] = fsub .. "\n"
  end
  if type(info.latex_hyperref_template) == "string" then
    out[#out + 1] = format_spec_apply(info.latex_hyperref_template, spec)
  end
  if
    info.latex_src_block_backend == "engraved"
    and element.map(info.parse_tree, { ["src-block"] = true, ["inline-src-block"] = true }, function()
        return true
      end, { first_match = true, ignore = info.ignore })
      == true
  then
    out[#out + 1] = M.generate_engraved_preamble(info)
  end
  out[#out + 1] = "\\begin{document}\n\n"
  local tc = info.latex_title_command
  local command = type(tc) == "string" and format_spec_apply(tc, spec) or nil
  if info.with_title and title ~= "" and command then
    if command:match("%%s") then
      command = command:gsub("%%s", function()
        return title
      end)
    end
    out[#out + 1] = ox.normalize_string(command)
  end
  local depth = info.with_toc
  if depth then
    if type(depth) == "number" then
      out[#out + 1] = fmt("\\setcounter{tocdepth}{%d}\n", depth)
    end
    out[#out + 1] = info.latex_toc_command
  end
  out[#out + 1] = contents
  if info.with_creator then
    out[#out + 1] = (info.creator or "") .. "\n"
  end
  out[#out + 1] = "\\end{document}"
  return table.concat(out)
end
M.template = template

-- Locals the later parts share
shared.template = template
