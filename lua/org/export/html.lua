---@mod org.export.html HTML back-end (port of Emacs ox-html.el)
---
--- This file holds the configuration and the escaping, attribute, anchor
--- and headline helpers the whole back-end shares; the rest loads from
--- org/export/html/: code (fontified source code), toc (table of
--- contents, lists of tables and listings, footnotes), template, transcode
--- (plain text and markup), headline (sections, headlines, items), latex
--- (LaTeX environments and fragments), link (links and images), blocks
--- (paragraphs, lists, blocks), table (tables and the last transcoders)
--- and backend (options, the back-end, M.render).

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")
local data = require("org.export.html_data")

local M = {}
-- The parts in org/export/html/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.export.html"] = M

M.extension = "html"

local function hcfg()
  return (require("org.config").opts.export or {}).html or {}
end

local function opt(name, default)
  local v = hcfg()[name]
  if v == nil then
    return default
  end
  return v
end

local nw = ox.nw

--- org-html-klipse-selection-script
local KLIPSE_SELECTION_SCRIPT = [[window.klipse_settings = {selector_eval_html: '.src-html',
                             selector_eval_js: '.src-js',
                             selector_eval_python_client: '.src-python',
                             selector_eval_scheme: '.src-scheme',
                             selector: '.src-clojure',
                             selector_eval_ruby: '.src-ruby'};]]
local trim = ox.trim
local fmt = string.format

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- org-html-encode-plain-text
local function encode(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
M.encode_plain_text = encode
M.escape = function(s)
  return (encode(s):gsub('"', "&quot;"))
end

local function xhtml_p(info)
  return (info.html_doctype or ""):lower():find("xhtml", 1, true) ~= nil
end
M.xhtml_p = xhtml_p

local function html5_p(info)
  local dt = (info.html_doctype or ""):lower()
  return dt == "html5" or dt == "xhtml5" or dt == "<!doctype html>"
end
M.html5_p = html5_p

local function html5_fancy_p(info)
  return info.html_html5_fancy and html5_p(info)
end

local function close_tag(tag, attr, info)
  return "<" .. tag .. ((attr and nw(" " .. attr)) and (" " .. attr) or "") .. (xhtml_p(info) and " />" or ">")
end
M.close_tag = close_tag

--- Attribute string from an ordered attribute table (read_attribute).
local function attribute_string(attrs)
  local out = {}
  for _, k in ipairs(attrs._keys or {}) do
    local v = attrs[k]
    if v ~= nil then
      out[#out + 1] = fmt('%s="%s"', k, (encode(v):gsub('"', "&quot;")))
    end
  end
  return table.concat(out, " ")
end
M.attribute_string = attribute_string

local function set_attr(attrs, key, value)
  if attrs[key] == nil and not vim.tbl_contains(attrs._keys, key) then
    attrs._keys[#attrs._keys + 1] = key
  end
  attrs[key] = value
  return attrs
end

local function has_attr(attrs, key)
  return vim.tbl_contains(attrs._keys, key)
end

--- org-html--reference
function M.reference(datum, info, named_only)
  local t = datum.type
  local custom = (t == "headline" or t == "inlinetask") and datum.props and datum.props.CUSTOM_ID
  local user = custom
    or ((t == "radio-target" or t == "target") and datum.value)
    or datum.name
    or (datum.props and datum.props.ID and ("ID-" .. datum.props.ID))
  if user and (info.html_prefer_user_labels or custom) then
    return user
  end
  if named_only and not (t == "headline" or t == "inlinetask" or t == "radio-target" or t == "target") and not user then
    return nil
  end
  return ox.get_reference(datum, info)
end

local function translate(s, info)
  return ox.translate(s, "html", info)
end

local function fix_class_name(k)
  return (k:gsub("[^a-zA-Z0-9_]", "_"))
end

local function anchor(id, desc, attributes, info)
  local name = info.html_allow_name_attribute_in_anchors and id
  local a = (id and fmt(' id="%s"', id) or "") .. (name and fmt(' name="%s"', name) or "") .. (attributes or "")
  return fmt("<a%s>%s</a>", a, desc or "")
end

local function todo_html(todo, info)
  if not todo then
    return nil
  end
  local done = info.todo_done and info.todo_done(todo)
  return fmt(
    '<span class="%s %s%s">%s</span>',
    done and "done" or "todo",
    info.html_todo_kwd_class_prefix or "",
    fix_class_name(todo),
    todo
  )
end

local function priority_html(priority)
  return priority and fmt('<span class="priority">[%s]</span>', priority) or nil
end

local function tags_html(tags, info)
  if not tags or #tags == 0 then
    return nil
  end
  local parts = {}
  for _, t in ipairs(tags) do
    parts[#parts + 1] = fmt('<span class="%s">%s</span>', (info.html_tag_class_prefix or "") .. fix_class_name(t), t)
  end
  return fmt('<span class="tag">%s</span>', table.concat(parts, "&nbsp;"))
end

--- org-html-format-headline-default-function
function M.format_headline(todo, _todo_type, priority, text, tags, info)
  local t = todo_html(todo, info)
  local p = priority_html(priority)
  local g = tags_html(tags, info)
  return (t and (t .. " ") or "")
    .. (p and (p .. " ") or "")
    .. (text or "")
    .. (g and "&nbsp;&nbsp;&nbsp" or "")
    .. (g or "")
end

local function format_headline(info, ...)
  local f = hcfg().format_headline_function
  if type(f) == "function" then
    return f(...)
  end
  return M.format_headline(...)
end

local function format_timestamp(ts, info)
  local fancy = html5_fancy_p(info)
  local tag = fancy and "time" or "span"
  local attrs = 'class="timestamp"'
  if fancy then
    -- org-html-datetime-formats: { date-only, date-and-time }
    local formats = opt("datetime_formats", { "%F", "%FT%T" })
    local f = ox.timestamp_has_time_p(ts) and formats[2] or formats[1]
    attrs = attrs .. fmt(' datetime="%s"', ox.format_timestamp(ts, f))
  end
  local s = fmt("<%s %s>%s</%s>", tag, attrs, M.plain_text(ox.timestamp_translate(ts), info), tag)
  return (s:gsub("%-%-", "&ndash;"))
end
M.format_timestamp = format_timestamp

--- Checkbox markup (org-html-checkbox-types).
local CHECKBOXES = {
  unicode = { on = "&#x2611;", off = "&#x2610;", trans = "&#x2610;" },
  ascii = { on = "<code>[X]</code>", off = "<code>[&nbsp;]</code>", trans = "<code>[-]</code>" },
  html = {
    on = "<input type='checkbox' checked='checked' />",
    off = "<input type='checkbox' />",
    trans = "<input type='checkbox' />",
  },
}

-- Locals the parts below share
local shared = require("org.export.html.shared")
shared.hcfg = hcfg
shared.opt = opt
shared.KLIPSE_SELECTION_SCRIPT = KLIPSE_SELECTION_SCRIPT
shared.encode = encode
shared.xhtml_p = xhtml_p
shared.html5_p = html5_p
shared.html5_fancy_p = html5_fancy_p
shared.close_tag = close_tag
shared.attribute_string = attribute_string
shared.set_attr = set_attr
shared.has_attr = has_attr
shared.translate = translate
shared.anchor = anchor
shared.format_headline = format_headline
shared.format_timestamp = format_timestamp
shared.CHECKBOXES = CHECKBOXES

require("org.export.html.code")
require("org.export.html.toc")
require("org.export.html.template")
require("org.export.html.transcode")
require("org.export.html.headline")
require("org.export.html.latex")
require("org.export.html.link")
require("org.export.html.blocks")
require("org.export.html.table")
require("org.export.html.backend")

return M
