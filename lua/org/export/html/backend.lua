---@mod org.export.html.backend HTML export options and back-end
---
--- The option defaults, the back-end definition and M.render.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local data = require("org.export.html_data")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local KLIPSE_SELECTION_SCRIPT = shared.KLIPSE_SELECTION_SCRIPT
local T = shared.T
local hcfg = shared.hcfg
local infojs_install = shared.infojs_install
local opt = shared.opt

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

local function defaults()
  local c = hcfg()
  local function v(name, default)
    if c[name] == nil then
      return default
    end
    return c[name]
  end
  local head_default_style = v("head_include_default_style", true)
  if c.style == false then
    head_default_style = false
  end
  return {
    { "html_doctype", "HTML_DOCTYPE", nil, v("doctype", "xhtml-strict") },
    { "html_container", "HTML_CONTAINER", nil, v("container", "div") },
    { "html_content_class", "HTML_CONTENT_CLASS", nil, v("content_class", "content") },
    { "description", "DESCRIPTION", nil, nil, "newline" },
    { "keywords_meta", "KEYWORDS", nil, nil, "space" },
    { "html_html5_fancy", nil, "html5-fancy", v("html5_fancy", false) },
    { "html_link_use_abs_url", nil, "html-link-use-abs-url", v("link_use_abs_url", false) },
    { "html_link_home", "HTML_LINK_HOME", nil, v("link_home", "") },
    { "html_link_up", "HTML_LINK_UP", nil, v("link_up", "") },
    { "html_mathjax", "HTML_MATHJAX", nil, "", "space" },
    {
      "html_equation_reference_format",
      "HTML_EQUATION_REFERENCE_FORMAT",
      nil,
      v("equation_reference_format", "\\eqref{%s}"),
      "t",
    },
    { "html_postamble", nil, "html-postamble", v("postamble", "auto") },
    { "html_preamble", nil, "html-preamble", v("preamble", true) },
    { "html_head", "HTML_HEAD", nil, v("head", ""), "newline" },
    { "html_head_extra", "HTML_HEAD_EXTRA", nil, v("head_extra", ""), "newline" },
    { "subtitle", "SUBTITLE", nil, nil, "parse" },
    { "html_head_include_default_style", nil, "html-style", head_default_style },
    { "html_head_include_scripts", nil, "html-scripts", v("head_include_scripts", false) },
    { "html_allow_name_attribute_in_anchors", nil, nil, v("allow_name_attribute_in_anchors", false) },
    {
      "html_divs",
      nil,
      nil,
      v(
        "divs",
        { preamble = { "div", "preamble" }, content = { "div", "content" }, postamble = { "div", "postamble" } }
      ),
    },
    { "html_checkbox_type", nil, nil, v("checkbox_type", "ascii") },
    { "html_extension", nil, nil, v("extension", "html") },
    { "html_footnote_format", nil, nil, v("footnote_format", "<sup>%s</sup>") },
    { "html_footnote_separator", nil, nil, v("footnote_separator", "<sup>, </sup>") },
    { "html_footnotes_section", nil, nil, v("footnotes_section", data.footnotes_section) },
    { "html_home_up_format", nil, nil, v("home_up_format", data.home_up_format) },
    { "html_inline_image_rules", nil, nil, v("inline_image_rules", M.inline_image_rules) },
    { "html_link_org_files_as_html", nil, nil, v("link_org_files_as_html", true) },
    { "html_mathjax_template", nil, nil, v("mathjax_template", data.mathjax_template) },
    { "html_metadata_timestamp_format", nil, nil, v("metadata_timestamp_format", "%Y-%m-%d %a %H:%M") },
    { "html_postamble_format", nil, nil, v("postamble_format", data.postamble_format) },
    { "html_preamble_format", nil, nil, v("preamble_format", { en = "" }) },
    { "html_prefer_user_labels", nil, nil, v("prefer_user_labels", false) },
    { "html_self_link_headlines", nil, "html-self-link-headlines", v("self_link_headlines", false) },
    { "html_table_align_individual_fields", nil, nil, v("table_align_individual_fields", true) },
    { "html_table_caption_above", nil, nil, v("table_caption_above", true) },
    { "html_table_data_tags", nil, nil, v("table_data_tags", { "<td%s>", "</td>" }) },
    { "html_table_header_tags", nil, nil, v("table_header_tags", { '<th scope="%s"%s>', "</th>" }) },
    { "html_table_use_header_tags_for_first_column", nil, nil, v("table_use_header_tags_for_first_column", false) },
    { "html_tag_class_prefix", nil, nil, v("tag_class_prefix", "") },
    {
      "html_text_markup_alist",
      nil,
      nil,
      v("text_markup_alist", {
        bold = "<b>%s</b>",
        code = "<code>%s</code>",
        italic = "<i>%s</i>",
        ["strike-through"] = "<del>%s</del>",
        underline = '<span class="underline">%s</span>',
        verbatim = "<code>%s</code>",
      }),
    },
    { "html_todo_kwd_class_prefix", nil, nil, v("todo_kwd_class_prefix", "") },
    { "html_toplevel_hlevel", nil, nil, v("toplevel_hlevel", 2) },
    { "html_validation_link", nil, nil, v("validation_link", data.validation_link) },
    {
      "html_viewport",
      nil,
      nil,
      v("viewport", {
        { "width", "device-width" },
        { "initial-scale", "1" },
        { "minimum-scale", "" },
        { "maximum-scale", "" },
        { "user-scalable", "" },
      }),
    },
    { "html_inline_images", nil, nil, v("inline_images", true) },
    {
      "html_table_attributes",
      nil,
      nil,
      v("table_default_attributes", {
        { "border", "2" },
        { "cellspacing", "0" },
        { "cellpadding", "6" },
        { "rules", "groups" },
        { "frame", "hsides" },
      }),
    },
    { "html_table_row_open_tag", nil, nil, v("table_row_open_tag", "<tr>") },
    { "html_table_row_close_tag", nil, nil, v("table_row_close_tag", "</tr>") },
    {
      "html_xml_declaration",
      nil,
      nil,
      v("xml_declaration", {
        html = '<?xml version="1.0" encoding="%s"?>',
        php = '<?php echo "<?xml version=\\"1.0\\" encoding=\\"%s\\" ?>"; ?>',
      }),
    },
    { "html_coding_system", nil, nil, v("coding_system", "utf-8") },
    { "html_wrap_src_lines", nil, nil, v("wrap_src_lines", false) },
    { "html_klipsify_src", nil, nil, v("klipsify_src", false) },
    {
      "html_klipse_css",
      nil,
      nil,
      v("klipse_css", "https://storage.googleapis.com/app.klipse.tech/css/codemirror.css"),
    },
    {
      "html_klipse_js",
      nil,
      nil,
      v("klipse_js", "https://storage.googleapis.com/app.klipse.tech/plugin_prod/js/klipse_plugin.min.js"),
    },
    { "html_klipse_selection_script", nil, nil, v("klipse_selection_script", KLIPSE_SELECTION_SCRIPT) },
    { "html_scripts", nil, nil, v("scripts", data.scripts) },
    { "infojs_opt", "INFOJS_OPT", nil, nil },
    { "creator", "CREATOR", nil, v("creator_string", nil) or ox.creator_string() },
    { "with_latex", nil, "tex", v("with_latex", (require("org.config").opts.export or {}).with_latex) },
    { "latex_header", "LATEX_HEADER", nil, nil, "newline" },
  }
end

M.backend = ox.define_backend("html", {
  transcoders = T,
  options = defaults,
  filters = {
    options = {
      function(info)
        return infojs_install(info)
      end,
    },
    ["parse-tree"] = {
      function(tree, _, info)
        return ox.insert_image_links(tree, info, info.html_inline_image_rules, true)
      end,
    },
    -- org-html-final-function: org-html-indent
    ["final-output"] = {
      function(text)
        if opt("indent", false) then
          return require("org.export.html_indent").indent(text)
        end
        return text
      end,
    },
  },
})

--- Render a parsed document (legacy API); prefer org.export.to_string.
function M.render(doc, opts)
  error("org.export.html.render is replaced by org.export.to_string")
end
