---@mod org.export.latex.backend LaTeX export options and back-end
---
--- The options alist and the back-end definition.
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local data = require("org.export.latex_data")
local shared = require("org.export.latex.shared")

local M = require("org.export.latex")

local T = shared.T
local lcfg = shared.lcfg

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

function M.options()
  local c = lcfg()
  local function v(name, default)
    if c[name] == nil then
      return default
    end
    return c[name]
  end
  return {
    { "latex_class", "LATEX_CLASS", nil, v("default_class", "article"), "t" },
    { "latex_class_options", "LATEX_CLASS_OPTIONS", nil, nil, "t" },
    { "latex_header", "LATEX_HEADER", nil, nil, "newline" },
    { "latex_header_extra", "LATEX_HEADER_EXTRA", nil, nil, "newline" },
    { "latex_class_pre", "LATEX_CLASS_PRE", nil, nil, "newline" },
    { "description_latex", "DESCRIPTION", nil, nil, "parse" },
    { "keywords_latex", "KEYWORDS", nil, nil, "parse" },
    { "subtitle", "SUBTITLE", nil, nil, "parse" },
    { "latex_active_timestamp_format", nil, nil, v("active_timestamp_format", "\\textit{%s}") },
    { "latex_caption_above", nil, nil, v("caption_above", { "table" }) },
    { "latex_classes", nil, nil, v("classes", data.classes) },
    { "latex_default_figure_position", nil, nil, v("default_figure_position", "htbp") },
    { "latex_default_table_environment", nil, nil, v("default_table_environment", "tabular") },
    { "latex_default_quote_environment", nil, nil, v("default_quote_environment", "quote") },
    { "latex_default_table_mode", nil, nil, v("default_table_mode", "table") },
    {
      "latex_default_footnote_command",
      "LATEX_FOOTNOTE_COMMAND",
      nil,
      v("default_footnote_command", "\\footnote{%s%s}"),
    },
    { "latex_diary_timestamp_format", nil, nil, v("diary_timestamp_format", "\\textit{%s}") },
    { "latex_engraved_options", nil, nil, v("engraved_options", data.engraved_options) },
    { "latex_engraved_preamble", nil, nil, v("engraved_preamble", data.engraved_preamble) },
    { "latex_engraved_theme", "LATEX_ENGRAVED_THEME", nil, v("engraved_theme", nil) },
    { "latex_footnote_defined_format", nil, nil, v("footnote_defined_format", "\\textsuperscript{\\ref{%s}}") },
    { "latex_footnote_separator", nil, nil, v("footnote_separator", "\\textsuperscript{,}\\,") },
    { "latex_hyperref_template", nil, nil, v("hyperref_template", data.hyperref_template), "t" },
    { "latex_image_default_scale", nil, nil, v("image_default_scale", "") },
    { "latex_image_default_height", nil, nil, v("image_default_height", "") },
    { "latex_image_default_option", nil, nil, v("image_default_option", "") },
    { "latex_image_default_width", nil, nil, v("image_default_width", ".9\\linewidth") },
    { "latex_images_centered", nil, nil, v("images_centered", true) },
    { "latex_inactive_timestamp_format", nil, nil, v("inactive_timestamp_format", "\\textit{%s}") },
    { "latex_inline_image_rules", nil, nil, v("inline_image_rules", M.inline_image_rules) },
    { "latex_link_with_unknown_path_format", nil, nil, v("link_with_unknown_path_format", "\\texttt{%s}") },
    { "latex_src_block_backend", nil, nil, v("src_block_backend", "verbatim") },
    { "latex_listings_langs", nil, nil, v("listings_langs", data.listings_langs) },
    { "latex_listings_options", nil, nil, v("listings_options", {}) },
    { "latex_listings_src_omit_language", nil, nil, v("listings_src_omit_language", false) },
    { "latex_minted_langs", nil, nil, v("minted_langs", data.minted_langs) },
    { "latex_minted_options", nil, nil, v("minted_options", {}) },
    { "latex_prefer_user_labels", nil, nil, v("prefer_user_labels", false) },
    { "latex_reference_command", nil, nil, v("reference_command", "\\ref{%s}") },
    { "latex_subtitle_format", nil, nil, v("subtitle_format", "\\\\\\medskip\n\\large %s") },
    { "latex_subtitle_separate", nil, nil, v("subtitle_separate", false) },
    { "latex_table_scientific_notation", nil, nil, v("table_scientific_notation", nil) },
    { "latex_tables_booktabs", nil, nil, v("tables_booktabs", false) },
    { "latex_tables_centered", nil, nil, v("tables_centered", true) },
    {
      "latex_text_markup_alist",
      nil,
      nil,
      v("text_markup_alist", {
        bold = "\\textbf{%s}",
        code = "protectedtexttt",
        italic = "\\emph{%s}",
        ["strike-through"] = "\\sout{%s}",
        underline = "\\uline{%s}",
        verbatim = "protectedtexttt",
      }),
    },
    { "latex_title_command", nil, nil, v("title_command", "\\maketitle") },
    { "latex_toc_command", nil, nil, v("toc_command", "\\tableofcontents\n\n") },
    { "latex_toc_include_unnumbered", nil, nil, v("toc_include_unnumbered", false) },
    { "latex_compiler", "LATEX_COMPILER", nil, v("compiler", "pdflatex") },
    { "latex_use_sans", nil, "latex-use-sans", v("use_sans", false) },
    { "latex_default_packages", nil, nil, v("default_packages", data.default_packages) },
    { "latex_packages", nil, nil, v("packages", {}) },
    { "date", "DATE", nil, "\\today", "parse" },
  }
end

local function image_filter(tree, _, info)
  return ox.insert_image_links(tree, info, info.latex_inline_image_rules)
end

local function clean_line_breaks(s)
  -- \end{...} \\ or a lone \\ at line start is invalid
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    local l = line:gsub("(\\end{[%w%*]+})[ \t]*\\\\[ \t]*$", "%1")
    if l:match("^[ \t]*\\\\[ \t]*$") then
      l = ""
    end
    out[#out + 1] = l
  end
  local r = table.concat(out, "\n")
  if not s:match("\n$") then
    r = r:sub(1, -2)
  end
  return r
end

M.backend = ox.define_backend("latex", {
  transcoders = T,
  options = M.options,
  filters = {
    options = {
      function(info)
        for _, prop in ipairs({ "author", "date", "title" }) do
          if type(info[prop]) == "table" then
            M.wrap_math_block(info[prop], info)
          end
        end
        return info
      end,
    },
    paragraph = {
      function(s)
        return clean_line_breaks(s)
      end,
    },
    ["verse-block"] = {
      function(s)
        return clean_line_breaks(s)
      end,
    },
    ["parse-tree"] = {
      function(tree, _, info)
        return M.wrap_math_block(tree, info)
      end,
      function(tree, _, info)
        return M.wrap_matrices(tree, info)
      end,
      image_filter,
    },
  },
})
