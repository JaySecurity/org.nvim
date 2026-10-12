---@mod org.export.html.template HTML document template
---
--- Meta tags, head, MathJax, preamble and postamble, info.js and the
--- document around the contents (org-html-template, org-html-inner-template).
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local data = require("org.export.html_data")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local close_tag = shared.close_tag
local encode = shared.encode
local hcfg = shared.hcfg
local html5_fancy_p = shared.html5_fancy_p
local html5_p = shared.html5_p
local opt = shared.opt
local translate = shared.translate
local xhtml_p = shared.xhtml_p

---------------------------------------------------------------------------
-- Template
---------------------------------------------------------------------------

local function build_meta_entry(label, identity, content)
  local s = "<meta " .. fmt('%s="%s', label, identity)
  if content then
    s = s .. '" content="' .. (encode(content):gsub('"', "&quot;"))
  end
  return s .. '" />\n'
end

local function build_meta_info(info)
  local title = M.plain_text(element.interpret(info.title or {}), info)
  if not nw(title) then
    title = "&lrm;"
  end
  local charset = info.html_coding_system or "utf-8"
  local out = {}
  if info.time_stamp_file then
    out[#out + 1] = ox.format_time("<!-- " .. info.html_metadata_timestamp_format .. " -->\n")
  end
  if html5_p(info) then
    out[#out + 1] = build_meta_entry("charset", charset)
  else
    out[#out + 1] = build_meta_entry("http-equiv", "Content-Type", "text/html;charset=" .. charset)
  end
  local vp = {}
  for _, cell in ipairs(info.html_viewport or {}) do
    if nw(cell[2]) then
      vp[#vp + 1] = cell[1] .. "=" .. cell[2]
    end
  end
  if #vp > 0 then
    out[#out + 1] = build_meta_entry("name", "viewport", table.concat(vp, ", "))
  end
  out[#out + 1] = fmt("<title>%s</title>\n", title)
  local meta = hcfg().meta_tags
  local tags
  if type(meta) == "function" then
    tags = meta(info)
  elseif type(meta) == "table" then
    tags = meta
  else
    local author = info.with_author and info.author and element.interpret(info.author) or nil
    tags = {}
    if nw(author) then
      tags[#tags + 1] = { "name", "author", author }
    end
    if nw(info.description) then
      tags[#tags + 1] = { "name", "description", info.description }
    end
    if nw(info.keywords_meta) then
      tags[#tags + 1] = { "name", "keywords", info.keywords_meta }
    end
    tags[#tags + 1] = { "name", "generator", "Org Mode" }
  end
  for _, t in ipairs(tags) do
    out[#out + 1] = build_meta_entry(t[1], t[2], t[3])
  end
  return table.concat(out)
end

local function norm_or_fn(v, info)
  if type(v) == "function" then
    v = tostring(v(info) or "")
  end
  return ox.normalize_string(v or "")
end

local function build_head(info)
  local s = ""
  if info.html_head_include_default_style then
    s = s .. ox.normalize_string(data.style_default)
  end
  -- legacy `style` option: CSS string added after the default style
  if type(hcfg().style) == "string" then
    s = s .. ox.normalize_string('<style type="text/css">\n' .. hcfg().style .. "\n</style>")
  end
  s = s .. (norm_or_fn(info.html_head, info) or "")
  s = s .. (norm_or_fn(info.html_head_extra, info) or "")
  if info.html_head_include_scripts then
    s = s .. (info.html_scripts or data.scripts)
  end
  return ox.normalize_string(s) or ""
end

local function has_math(info)
  return element.map(info.parse_tree, { ["latex-fragment"] = true, ["latex-environment"] = true }, function(x)
    return x
  end, { ignore = info.ignore, first_match = true }) ~= nil
end

local MATHJAX_DEFAULTS = {
  { "path", "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js" },
  { "scale", 1.0 },
  { "align", "center" },
  { "font", "mathjax-modern" },
  { "overflow", "overflow" },
  { "tags", "ams" },
  { "indent", "0em" },
  { "multlinewidth", "85%" },
  { "tagindent", ".8em" },
  { "tagside", "right" },
}

local function num_str(v)
  if type(v) == "number" then
    if v == math.floor(v) then
      return fmt("%.1f", v)
    end
    return tostring(v)
  end
  return tostring(v)
end

local function build_mathjax_config(info)
  local wl = info.with_latex
  if not (wl == "mathjax" or wl == true) or not has_math(info) then
    return ""
  end
  if hcfg().mathjax == false then
    return ""
  end
  local template = info.html_mathjax_template or data.mathjax_template
  local user = hcfg().mathjax_options or {}
  local options = {}
  for _, o in ipairs(MATHJAX_DEFAULTS) do
    local v = user[o[1]]
    if v == nil then
      v = o[2]
    end
    options[#options + 1] = { o[1], v }
  end
  local inbuf = info.html_mathjax or ""
  for _, o in ipairs(options) do
    local sym, value = o[1], o[2]
    local m = inbuf:match("%f[%w]" .. sym .. ":%s*(%S+)")
    if m then
      value = m
      if sym == "scale" then
        local n = tonumber(value) or 1.0
        if n >= 10 then
          n = n / 100
        end
        value = n
      elseif sym == "font" then
        value = ({
          TeX = "mathjax-tex",
          ["STIX-Web"] = "mathjax-stix2",
          ["Asana-Math"] = "mathjax-asana",
          ["Neo-Euler"] = "mathjax-euler",
          ["Gyre-Pagella"] = "mathjax-pagella",
          ["Gyre-Termes"] = "mathjax-termes",
          ["Latin-Modern"] = "mathjax-modern",
        })[value] or value
      end
    end
    if sym == "linebreaks" or sym == "autonumber" then
      -- legacy options
    end
    template = template:gsub("%%" .. sym:upper() .. "([^A-Z])", function(after)
      return num_str(value) .. after
    end)
  end
  -- legacy in-buffer options
  local lb = inbuf:match("%f[%w]linebreaks:%s*(%S+)")
  if lb then
    template = template:gsub(
      "displayOverflow: '[^']*'",
      "displayOverflow: '" .. (lb == "true" and "linebreak" or "overflow") .. "'"
    )
  end
  local an = inbuf:match("%f[%w]autonumber:%s*(%S+)")
  if an then
    template = template:gsub("tags: '[^']*'", "tags: '" .. an:lower():gsub("%%", "%%%%") .. "'")
  end
  return ox.normalize_string(template)
end

local function format_spec(info)
  local tsfmt = info.html_metadata_timestamp_format
  local date = ox.get_date(info, tsfmt)
  local emails = {}
  for e in (info.email or ""):gmatch("[^,]+") do
    e = trim(e)
    if e ~= "" then
      emails[#emails + 1] = fmt('<a href="mailto:%s">%s</a>', e, e)
    end
  end
  local file = info.input_file
  return {
    t = ox.data(info.title, info),
    s = ox.data(info.subtitle, info),
    d = type(date) == "string" and date or ox.data(date, info),
    T = ox.format_time(tsfmt),
    a = ox.data(info.author, info),
    e = table.concat(emails, ", "),
    c = info.creator or "",
    C = ox.format_time(tsfmt, file and vim.fn.getftime(file) > 0 and vim.fn.getftime(file) or nil),
    v = info.html_validation_link or "",
  }
end

local function format_spec_apply(s, spec)
  return (
    s:gsub("%%(.)", function(c)
      if c == "%" then
        return "%"
      end
      return spec[c] or ("%" .. c)
    end)
  )
end

local function build_pre_postamble(kind, info)
  local section = info["html_" .. kind]
  if not section then
    return ""
  end
  local spec = format_spec(info)
  local contents
  if type(section) == "function" then
    contents = section(info)
  elseif type(section) == "string" and section ~= "auto" then
    contents = format_spec_apply(section, spec)
  elseif section == "auto" and kind == "postamble" then
    local parts = {}
    if info.with_date and nw(spec.d) then
      parts[#parts + 1] = fmt('<p class="date">%s: %s</p>\n', translate("Date", info), spec.d)
    end
    if info.with_author and nw(spec.a) then
      parts[#parts + 1] = fmt('<p class="author">%s: %s</p>\n', translate("Author", info), spec.a)
    end
    if info.with_email and nw(spec.e) then
      parts[#parts + 1] = fmt('<p class="email">%s: %s</p>\n', translate("Email", info), spec.e)
    end
    if info.time_stamp_file then
      parts[#parts + 1] = fmt(
        '<p class="date">%s: %s</p>\n',
        translate("Created", info),
        ox.format_time(info.html_metadata_timestamp_format)
      )
    end
    if info.with_creator and nw(spec.c) then
      parts[#parts + 1] = fmt('<p class="creator">%s</p>\n', spec.c)
    end
    if nw(spec.v) then
      parts[#parts + 1] = fmt('<p class="validation">%s</p>\n', spec.v)
    end
    contents = table.concat(parts)
  else
    local formats = kind == "preamble" and (info.html_preamble_format or { en = "" })
      or (info.html_postamble_format or data.postamble_format)
    local f = formats[info.language] or formats.en or ""
    contents = format_spec_apply(f, spec)
  end
  if not nw(contents) then
    return ""
  end
  local div = info.html_divs[kind]
  return fmt('<%s id="%s" class="status">\n', div[1], div[2]) .. ox.normalize_string(contents) .. fmt("</%s>\n", div[1])
end

--- org-html-infojs-install-script (options filter).
local function infojs_install(info)
  local use = opt("use_infojs", "when-configured")
  if not use or (use == "when-configured" and not nw(info.infojs_opt)) then
    return info
  end
  if info.html_klipsify_src then
    return info
  end
  local o = info.infojs_opt or ""
  if o:match("%f[%w]view:nil%f[^%w]") and use == "when-configured" then
    return info
  end
  if info.export_options and info.export_options.body_only then
    return info
  end
  -- org-html-infojs-opts-table / org-html-infojs-options defaults
  local table_ = {
    { "path", "PATH", "https://orgmode.org/org-info.js" },
    { "view", "VIEW", "info" },
    { "toc", "TOC", info.with_toc },
    { "ftoc", "FIXED_TOC", "0" },
    { "tdepth", "TOC_DEPTH", "max" },
    { "sdepth", "SECTION_DEPTH", "max" },
    { "mouse", "MOUSE_HINT", "underline" },
    { "buttons", "VIEW_BUTTONS", "0" },
    { "ltoc", "LOCAL_TOC", "1" },
    { "up", "LINK_UP", info.html_link_up },
    { "home", "LINK_HOME", info.html_link_home },
  }
  local template = opt("infojs_template", data.infojs_template) -- org-html-infojs-template
  local ptoc = info.with_toc
  local hlevels = info.headline_levels or 3
  local sdepth = hlevels
  local tdepth = type(ptoc) == "number" and math.min(ptoc, hlevels) or hlevels
  local style = {}
  for _, e in ipairs(table_) do
    local val = o:match("%f[%w]" .. e[1] .. ":(%S+)")
    if val == nil then
      val = e[3]
    end
    if e[1] == "path" then
      template = template:gsub("%%SCRIPT_PATH", function()
        return val
      end)
    elseif e[1] == "sdepth" or e[1] == "tdepth" then
      local n = tonumber(val)
      if n and math.floor(n) == n then
        if e[1] == "sdepth" then
          sdepth = math.min(n, sdepth)
        else
          tdepth = math.min(n, tdepth)
        end
      end
    else
      if val == true or val == "t" then
        val = "1"
      elseif val == nil or val == false or val == "nil" then
        val = "0"
      end
      table.insert(style, 1, { e[2], tostring(val) })
    end
  end
  -- the generated TOC goes as deep as the splitting (SDEPTH); TDEPTH only
  -- limits how much of it is shown
  info.with_toc = sdepth
  tdepth = math.min(tdepth, sdepth)
  table.insert(style, 1, { "TOC_DEPTH", tostring(tdepth) })
  local lines = {}
  for _, kv in ipairs(style) do
    lines[#lines + 1] = fmt('org_html_manager.set("%s", "%s");', kv[1], kv[2])
  end
  local a, b = template:find("%MANAGER_OPTIONS", 1, true)
  if a then
    template = template:sub(1, a - 1) .. table.concat(lines, "\n") .. template:sub(b + 1)
    info.html_head_extra = (info.html_head_extra or "") .. "\n" .. template
  end
  return info
end

M.infojs_install = infojs_install

local function inner_template(contents, info)
  local depth = info.with_toc
  return (depth and (M.toc(type(depth) == "number" and depth or nil, info) or "") or "")
    .. contents
    .. (M.footnote_section(info) or "")
end

local function template(contents, info)
  local out = {}
  if not html5_p(info) and xhtml_p(info) then
    local decl = info.html_xml_declaration
    local d
    if type(decl) == "string" then
      d = decl
    elseif type(decl) == "table" then
      d = decl[info.html_extension] or decl.html
    end
    if d and d ~= "" then
      out[#out + 1] = fmt(d, info.html_coding_system or "utf-8") .. "\n"
    end
  end
  out[#out + 1] = (data.doctypes[info.html_doctype] or info.html_doctype) .. "\n"
  local lang = info.language
  if xhtml_p(info) then
    out[#out + 1] = fmt('<html xmlns="http://www.w3.org/1999/xhtml" lang="%s" xml:lang="%s">\n', lang, lang)
  elseif html5_p(info) then
    out[#out + 1] = fmt('<html lang="%s">\n', lang)
  else
    out[#out + 1] = "<html>\n"
  end
  out[#out + 1] = "<head>\n"
  out[#out + 1] = build_meta_info(info)
  out[#out + 1] = build_head(info)
  out[#out + 1] = build_mathjax_config(info)
  out[#out + 1] = "</head>\n<body>\n"
  local up = trim(info.html_link_up or "")
  local home = trim(info.html_link_home or "")
  if not (up == "" and home == "") then
    local f = info.html_home_up_format or data.home_up_format
    local i = 0
    out[#out + 1] = (
      f:gsub("%%s", function()
        i = i + 1
        if i == 1 then
          return up ~= "" and up or home
        end
        return home ~= "" and home or up
      end)
    )
  end
  out[#out + 1] = build_pre_postamble("preamble", info)
  local div = info.html_divs.content
  out[#out + 1] = fmt('<%s id="%s" class="%s">\n', div[1], div[2], info.html_content_class)
  if info.with_title and info.title then
    local fancy = html5_fancy_p(info)
    local sub = ""
    if info.subtitle then
      if fancy then
        sub = fmt('<p class="subtitle" role="doc-subtitle">%s</p>\n', ox.data(info.subtitle, info))
      else
        sub = "\n"
          .. close_tag("br", nil, info)
          .. "\n"
          .. fmt('<span class="subtitle">%s</span>\n', ox.data(info.subtitle, info))
      end
    end
    if fancy then
      out[#out + 1] = fmt('<header>\n<h1 class="title">%s</h1>\n%s</header>', ox.data(info.title, info), sub)
    else
      out[#out + 1] = fmt('<h1 class="title">%s%s</h1>\n', ox.data(info.title, info), sub)
    end
  end
  out[#out + 1] = contents
  out[#out + 1] = fmt("</%s>\n", div[1])
  out[#out + 1] = build_pre_postamble("postamble", info)
  if info.html_klipsify_src then
    out[#out + 1] = "<script>"
      .. (info.html_klipse_selection_script or "")
      .. '</script><script src="'
      .. (info.html_klipse_js or "")
      .. '"></script><link rel="stylesheet" type="text/css" href="'
      .. (info.html_klipse_css or "")
      .. '"/>'
  end
  out[#out + 1] = "</body>\n</html>"
  return table.concat(out)
end

-- Locals the later parts share
shared.infojs_install = infojs_install
shared.inner_template = inner_template
shared.template = template
