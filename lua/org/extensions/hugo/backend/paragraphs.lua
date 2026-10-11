---@mod org.extensions.hugo.backend.paragraphs Hugo transcoders: paragraphs, tables, special blocks
---
--- Paragraphs (standalone images as figures, `#+hugo: more`), tables,
--- special blocks (HTML5 elements, `<details>`, paired shortcodes,
--- `#+begin_description`) and the `#+attr_html` div wrapper. Part of
--- org.extensions.hugo.backend, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local html = require("org.export.html")
local md = require("org.export.markdown")
local fm = require("org.extensions.hugo.front_matter")
local shared = require("org.extensions.hugo.backend.shared")

local M = require("org.extensions.hugo.backend")

local T = M.transcoders
local fmt = shared.fmt
local nw = shared.nw
local trim = shared.trim
local TRIM_PRE = shared.TRIM_PRE
local TRIM_POST = shared.TRIM_POST
local opts = shared.opts
local truthy = shared.truthy
local encode = shared.encode
local named_reference = shared.named_reference
local css_string = shared.css_string
local style_string = shared.style_string
local escape_shortcodes = shared.escape_shortcodes
local caption_div = shared.caption_div

---------------------------------------------------------------------------
-- Paragraphs and tables
---------------------------------------------------------------------------

--- Wrap in a div when the element has #+attr_html attributes
--- (org-blackfriday--div-wrap-maybe).
local function div_wrap(el, contents)
  local a = ox.read_attribute("attr_html", el)
  if el.type == "paragraph" then
    for _, k in ipairs({ "target", "rel", "src", "alt", "height", "width", "caption" }) do
      a[k] = nil
    end
  end
  local s = html.attribute_string(a)
  if not nw(s) then
    return contents
  end
  return style_string(el) .. fmt("<div %s>\n\n%s\n</div>", s, contents)
end

--- Is the post in Chinese or Japanese (org-hugo--lang-cjk-p)?
local function cjk_p(info)
  local l = nw(info.hugo_locale) or vim.env.LANGUAGE or vim.env.LC_ALL or vim.env.LANG or ""
  local two = l:sub(1, 2)
  return two == "zh" or two == "ja"
end

local function process_paragraph(el, contents, info)
  local s = contents or ""
  if cjk_p(info) then
    -- join lines of CJK text without a space
    s = s:gsub("([\128-\255])[ \t]*\n[ \t]*([\192-\255])", "%1%2")
  end
  if not truthy(info.hugo_preserve_filling) then
    local words = {}
    for w in s:gmatch("%S+") do
      words[#words + 1] = w
    end
    s = table.concat(words, " ") .. "\n"
  end
  s = s:gsub("(%[%^[^%]]+%])[ \t]*(%.+)", "%1%2")
  s = s:gsub("[ \t]+(%[%^[^%]]+%])", "&nbsp;%1")
  return md.transcoders.paragraph(el, s)
end

T.paragraph = function(el, contents, info)
  local parent = el.parent
  if parent and parent.type == "item" then
    -- (org-blackfriday-separate-elements) no blank line before a block
    local nxt = ox.get_next_element(el, info)
    if nxt and (nxt.type == "src-block" or nxt.type == "example-block") then
      el.post_blank = 0
    end
  end
  if parent and parent.type == "item" and not ox.get_previous_element(el, info) then
    local nxt = ox.get_next_element(el, info)
    local after = nxt and ox.get_next_element(nxt, info)
    if not after and (not nxt or nxt.type == "plain-list") then
      return process_paragraph(el, contents, info)
    end
  end
  if html.standalone_image_p(el, info) then
    local ref = named_reference(el, "figure")
    return (ref and fmt('<a id="%s"></a>\n\n', ref) or "") .. (contents or "")
  end
  local label = nw(el.name) and fmt('<a id="%s"></a>\n\n', ox.get_reference(el, info)) or ""
  return div_wrap(el, label .. process_paragraph(el, contents, info))
end

T.table = function(el, _, info)
  if el.table_type == "table.el" then
    return html.transcoders.table(el, nil, info)
  end
  local rows = {}
  local special = ox.table_has_special_column_p(el)
  local align = {}
  for _, r in ipairs(el.contents) do
    if r.row_type == "standard" then
      if ox.table_row_is_special_p(r, info) then
        local cells = r.contents
        for c = (special and 2 or 1), #cells do
          local v = cells[c].contents
          local txt = v and #v == 1 and v[1].type == "plain-text" and v[1].value or nil
          local a = txt and txt:match("^<([lrc])%d*>$")
          if a then
            align[c - (special and 1 or 0)] = a
          end
        end
      elseif not info.ignore[r] then
        local cells = {}
        for c, cell in ipairs(r.contents) do
          if not info.ignore[cell] and not (special and c == 1) then
            cells[#cells + 1] = (ox.data(cell.contents, info):gsub("|", "\\|"))
          end
        end
        rows[#rows + 1] = cells
      end
    end
  end
  if #rows == 0 then
    return nil
  end
  local ncols, widths = 0, {}
  for _, r in ipairs(rows) do
    ncols = math.max(ncols, #r)
    for c, v in ipairs(r) do
      widths[c] = math.max(widths[c] or 0, vim.fn.strdisplaywidth(v))
    end
  end
  local function line(cells)
    local parts = {}
    for c = 1, ncols do
      local v = cells[c] or ""
      local cell = "| " .. v .. string.rep(" ", math.max(0, (widths[c] or 0) - vim.fn.strdisplaywidth(v))) .. " "
      if #cell < 3 then
        cell = cell .. string.rep(" ", 3 - #cell)
      end
      parts[#parts + 1] = cell
    end
    return table.concat(parts) .. "|"
  end
  local function rule()
    local parts = {}
    for c = 1, ncols do
      local w = math.max(1, widths[c] or 0) + 2
      local seg = string.rep("-", w)
      local a = align[c]
      if a == "l" or a == "c" then
        seg = ":" .. seg:sub(2)
      end
      if a == "r" or a == "c" then
        seg = seg:sub(1, -2) .. ":"
      end
      parts[#parts + 1] = "|" .. seg
    end
    return table.concat(parts) .. "|"
  end
  local out = {}
  if #rows == 1 then
    out[#out + 1] = line({})
    out[#out + 1] = rule()
    out[#out + 1] = line(rows[1])
  else
    out[#out + 1] = line(rows[1])
    out[#out + 1] = rule()
    for i = 2, #rows do
      out[#out + 1] = line(rows[i])
    end
  end
  local ref = named_reference(el, "table")
  local anchor = ref and fmt('<a id="%s"></a>\n', ref) or ""
  local caption, num = caption_div(el, "table", ref, info)
  local a = ox.read_attribute("attr_html", el)
  local class = nw(a.class) or ("table-" .. (num and tostring(num) or "nocaption"))
  local css = css_string(el)
  local pre, post = "", ""
  if nw(css) then
    pre = fmt("<style>.%s table { %s }</style>\n\n", class:match("%S+"), css)
  end
  if nw(a.class) or nw(css) then
    pre = pre .. fmt('<div class="ox-hugo-table %s">\n', class)
  end
  if pre ~= "" then
    post = "\n</div>\n"
  end
  local blank = (pre .. anchor .. caption) ~= "" and "\n" or ""
  return pre .. anchor .. caption .. blank .. table.concat(out, "\n") .. "\n" .. post
end

---------------------------------------------------------------------------
-- Special blocks
---------------------------------------------------------------------------

--- org-blackfriday-html5-inline-elements
local HTML5_INLINE = {
  "abbr",
  "audio",
  "bdi",
  "bdo",
  "button",
  "canvas",
  "cite",
  "data",
  "datalist",
  "del",
  "dfn",
  "embed",
  "iframe",
  "input",
  "ins",
  "kbd",
  "label",
  "map",
  "mark",
  "meter",
  "noscript",
  "object",
  "output",
  "picture",
  "progress",
  "q",
  "ruby",
  "s",
  "samp",
  "script",
  "select",
  "slot",
  "small",
  "span",
  "svg",
  "template",
  "textarea",
  "time",
  "u",
  "var",
  "video",
}
local HTML5_BLOCK = {
  "article",
  "aside",
  "audio",
  "canvas",
  "details",
  "figcaption",
  "figure",
  "footer",
  "header",
  "menu",
  "meter",
  "nav",
  "output",
  "progress",
  "section",
  "summary",
  "video",
}

local function block_type_props(btype)
  local props = opts().special_block_type_properties or {}
  return props[btype] or {}
end

--- The Org source of a block's contents (for `raw` blocks).
local function raw_contents(el)
  return element.interpret(el.contents or {})
end

--- org-blackfriday-special-block: <details>/<summary>, HTML5 elements,
--- else a <div> (or <span> with trimming) with the type as class.
local function blackfriday_special(el, contents, info, trim_pre, trim_post)
  local btype = el.block_type
  local inline = vim.tbl_contains(HTML5_INLINE, btype)
  local block = vim.tbl_contains(HTML5_BLOCK, btype)
  local fancy = inline or block or btype == "details" or btype == "summary"
  local a = ox.read_attribute("attr_html", el)
  if not fancy then
    if a.class then
      a.class = a.class .. " " .. btype
    else
      a._keys[#a._keys + 1] = "class"
      a.class = btype
    end
  end
  if nw(el.name) and a.id == nil then
    a._keys[#a._keys + 1] = "id"
    a.id = el.name
  end
  local parts = {}
  for _, k in ipairs(a._keys) do
    local v = a[k]
    if v ~= nil then
      if (btype == "details" and k == "open") or v == "t" then
        if truthy(v) then
          parts[#parts + 1] = k
        end
      else
        parts[#parts + 1] = fmt('%s="%s"', k, (encode(v):gsub('"', "&quot;")))
      end
    end
  end
  local attr = #parts > 0 and (" " .. table.concat(parts, " ")) or ""
  contents = trim(contents or "")
  if btype == "details" then
    local div = '<div class="details">'
    local s, e = contents:find("<summary>.-</summary>")
    if s then
      contents = contents:sub(1, e) .. "\n" .. div .. contents:sub(e + 1)
    else
      contents = div .. "\n\n" .. contents
    end
    contents = contents .. "\n</div>"
    return fmt("<%s%s>\n%s\n</%s>", btype, attr, contents, btype)
  elseif btype == "summary" then
    local h = ox.data_with_backend(el.contents or {}, "html", info)
    h = h:gsub("</?p>", ""):gsub("\n\n+", "\n\n")
    return fmt("<%s%s>%s</%s>", btype, attr, trim(h), btype)
  elseif inline then
    return fmt("%s<%s%s>%s</%s>%s", trim_pre, btype, attr, contents, btype, trim_post)
  elseif block then
    return fmt("%s<%s%s>\n\n%s\n\n</%s>%s", trim_pre, btype, attr, contents, btype, trim_post)
  end
  if trim_pre ~= "" or trim_post ~= "" then
    return fmt("%s<span%s>%s</span>%s", trim_pre, attr, contents, trim_post)
  end
  return fmt("%s<div%s>\n\n%s\n\n</div>%s", trim_pre, attr, contents, trim_post)
end

--- The paired shortcode of `btype` in HUGO_PAIRED_SHORTCODES ("%name" for
--- shortcodes with Markdown contents), or nil.
local function paired_shortcode(btype, info)
  local str = info.hugo_paired_shortcodes
  if not nw(str) then
    return nil
  end
  for sc in str:gmatch("%S+") do
    if sc == btype or sc == "%" .. btype then
      return sc
    end
  end
  return nil
end

T["special-block"] = function(el, contents, info)
  local btype = el.block_type
  local tprops = block_type_props(btype)
  local header = {}
  for _, h in ipairs(el.header or {}) do
    for _, kv in ipairs(fm.parse_arguments(h)) do
      header[kv[1]] = kv[2]
    end
  end
  local function pick(key)
    if header[key] ~= nil then
      return header[key]
    end
    return tprops[key]
  end
  local trim_pre = truthy(pick("trim-pre")) and TRIM_PRE or ""
  local last = ox.get_next_element(el, info) == nil
  -- like ox-hugo, the default for trim-post is the type's :trim-pre
  local tp = header["trim-post"]
  if tp == nil then
    tp = tprops["trim-pre"]
  end
  local trim_post = (not last and truthy(tp)) and TRIM_POST or ""
  if #(el.contents or {}) == 0 then
    -- an empty block is left out
    return nil
  end
  if tprops.raw then
    contents = raw_contents(el)
  end
  contents = trim(contents or "")
  local a = ox.read_attribute("attr_html", el)
  if btype == "tikzjax" then
    local s = '<script type="text/tikz">\n  \\begin{tikzpicture}\n' .. contents .. "\n\\end{tikzpicture}\n</script>"
    if nw(a.caption) then
      s = "<figure>\n" .. s .. fmt("\n<figcaption>%s</figcaption>\n</figure>", a.caption)
    end
    return s
  elseif btype == "description" then
    info.description = escape_shortcodes(contents, "md")
    info.hugo_description_block = true
    return nil
  end
  local sc = paired_shortcode(btype, info)
  if sc then
    local raw_attr = el.attr_shortcode
    local args
    if raw_attr then
      local joined = table.concat(raw_attr, " ")
      if joined:match("^%s*:") then
        args = html.attribute_string(ox.read_attribute("attr_shortcode", el))
      else
        args = joined
      end
    end
    args = nw(args) and (" " .. args .. " ") or " "
    local ch_open, ch_close = "<", ">"
    if sc:sub(1, 1) == "%" then
      ch_open, ch_close = "%", "%"
    end
    local open = fmt("%s{{%s %s%s%s}}", trim_pre, ch_open, btype, args, ch_close)
    local close = fmt("{{%s /%s %s}}%s", ch_open, btype, ch_close, trim_post)
    return open .. "\n" .. contents .. "\n" .. close
  end
  return blackfriday_special(el, contents, info, trim_pre, trim_post)
end

shared.div_wrap = div_wrap
