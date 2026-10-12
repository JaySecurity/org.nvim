---@mod org.export.html.blocks HTML paragraphs, lists and blocks
---
--- From node-property to superscript: paragraphs, plain lists, quote,
--- special and source blocks.
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local nw = ox.nw
local trim = ox.trim
local fmt = string.format

local T = shared.T
local anchor = shared.anchor
local attribute_string = shared.attribute_string
local format_timestamp = shared.format_timestamp
local has_attr = shared.has_attr
local has_caption = shared.has_caption
local html5_fancy_p = shared.html5_fancy_p
local set_attr = shared.set_attr
local textarea_block = shared.textarea_block
local translate = shared.translate
local wrap_image = shared.wrap_image

T["node-property"] = function(el)
  return fmt("%s:%s", el.key, el.value and (" " .. el.value) or "")
end

T.paragraph = function(el, contents, info)
  local parent = el.parent
  local ptype = parent and parent.type
  local attrs = attribute_string(ox.read_attribute("attr_html", el))
  local extra = (ptype == "footnote-definition" or ptype == "org-data") and ' class="footpara"' or ""
  if ptype == "item" and not ox.get_previous_element(el, info) then
    local followers = ox.get_next_element(el, info, 2)
    if #followers <= 1 and (followers[1] == nil or followers[1].type == "plain-list") then
      return contents
    end
  end
  if M.standalone_image_p(el, info) then
    local raw = ox.data(ox.get_caption(el), info)
    local caption = raw
    if nw(raw) then
      local img = element.map(el, "link", function(x)
        return x
      end, { first_match = true })
      local pred = function(x)
        return x.caption ~= nil
      end
      local n = ox.get_ordinal(img, info, nil, function(x)
        return M.standalone_image_p(x, info, pred)
      end)
      caption = '<span class="figure-number">'
        .. (translate("Figure %d:", info):gsub("%%d", tostring(n)))
        .. " </span>"
        .. raw
    end
    return wrap_image(contents, info, caption, M.reference(el, info))
  end
  return fmt("<p%s%s>\n%s</p>", nw(attrs) and (" " .. attrs) or "", extra, contents or "")
end

T["plain-list"] = function(el, contents)
  local t = ({ ordered = "ol", unordered = "ul", descriptive = "dl" })[el.list_type]
  local attrs = ox.read_attribute("attr_html", el)
  local class = trim("org-" .. t .. " " .. (attrs.class or ""))
  set_attr(attrs, "class", class)
  return fmt("<%s %s>\n%s</%s>", t, attribute_string(attrs), contents or "", t)
end

T["plain-text"] = function(text, info, node)
  return M.plain_text(text, info, node)
end

T.planning = function(el, _, info)
  local parts = {}
  for _, kv in ipairs({ { "CLOSED:", el.closed }, { "DEADLINE:", el.deadline }, { "SCHEDULED:", el.scheduled } }) do
    if kv[2] then
      parts[#parts + 1] = fmt('<span class="timestamp-kwd">%s</span> %s ', kv[1], format_timestamp(kv[2], info))
    end
  end
  return fmt('<p><span class="timestamp-wrapper">%s</span></p>', trim(table.concat(parts)))
end

T["property-drawer"] = function(_, contents)
  if nw(contents) then
    return fmt('<pre class="example">\n%s</pre>', contents)
  end
end

T["quote-block"] = function(el, contents, info)
  local ref = M.reference(el, info, true)
  local attrs = ox.read_attribute("attr_html", el)
  if ref and not has_attr(attrs, "id") then
    set_attr(attrs, "id", ref)
  end
  local a = attribute_string(attrs)
  return fmt("<blockquote%s>\n%s</blockquote>", nw(a) and (" " .. a) or "", contents or "")
end

T["radio-target"] = function(el, text, info)
  return anchor(M.reference(el, info), text, nil, info)
end

local HTML5_ELEMENTS = {
  article = 1,
  aside = 1,
  audio = 1,
  canvas = 1,
  details = 1,
  figcaption = 1,
  figure = 1,
  footer = 1,
  header = 1,
  menu = 1,
  meter = 1,
  nav = 1,
  output = 1,
  progress = 1,
  section = 1,
  summary = 1,
  video = 1,
}

T["special-block"] = function(el, contents, info)
  local btype = el.block_type
  local fancy = html5_fancy_p(info) and HTML5_ELEMENTS[btype]
  local attrs = ox.read_attribute("attr_html", el)
  if not fancy then
    local class = attrs.class
    set_attr(attrs, "class", class and (class .. " " .. btype) or btype)
  end
  contents = contents or ""
  local ref = M.reference(el, info)
  if ref and not has_attr(attrs, "id") then
    set_attr(attrs, "id", ref)
  end
  local a = attribute_string(attrs)
  local str = nw(a) and (" " .. a) or ""
  if fancy then
    return fmt("<%s%s>\n%s</%s>", btype, str, contents, btype)
  end
  return fmt("<div%s>\n%s\n</div>", str, contents)
end

T["src-block"] = function(el, _, info)
  if ox.read_attribute("attr_html", el, "textarea") then
    return textarea_block(el)
  end
  local lang = el.language
  local code = M.format_code_of(el, info)
  local lbl = M.reference(el, info, true)
  local label = lbl and fmt(' id="%s"', lbl) or ""
  local caption = ox.get_caption(el)
  local cap = ""
  if caption then
    local n = ox.get_ordinal(el, info, nil, has_caption)
    cap = fmt(
      '<label class="org-src-name">%s%s</label>',
      fmt('<span class="listing-number">%s </span>', (translate("Listing %d:", info):gsub("%%d", tostring(n)))),
      trim(ox.data(caption, info))
    )
  end
  local klipse = info.html_klipsify_src
    and vim.tbl_contains({ "javascript", "js", "ruby", "scheme", "clojure", "php", "html" }, lang)
  if klipse then
    return fmt(
      '<div class="org-src-container">\n%s%s\n</div>',
      cap,
      fmt(
        '<pre><code class="src src-%s"%s%s>%s</code></pre>',
        lang or "",
        label,
        lang == "html" and ' data-editor-type="html"' or "",
        code
      )
    )
  end
  return fmt(
    '<div class="org-src-container">\n%s%s\n</div>',
    cap,
    -- Emacs formats a missing language as "nil"
    fmt('<pre class="src src-%s"%s><code>%s</code></pre>', lang or "nil", label, code)
  )
end

T["statistics-cookie"] = function(el)
  return fmt("<code>%s</code>", el.value)
end

T.subscript = function(_, contents)
  return fmt("<sub>%s</sub>", contents or "")
end

T.superscript = function(_, contents)
  return fmt("<sup>%s</sup>", contents or "")
end
