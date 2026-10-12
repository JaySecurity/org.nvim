---@mod org.extensions.hugo.backend The `hugo` export back-end (port of ox-hugo)
---
--- Derived from `md` with the Blackfriday changes ox-hugo builds on
--- (fenced code, pipe tables, `[^fn:N]` footnotes, `_italic_`,
--- `~~strike~~`, `<details>` blocks) and ox-hugo's own transcoders:
--- headings with `{#anchor}`s one level down, `{{< figure >}}` for
--- standalone images, `{{< relref >}}` for links to other posts and Org
--- files, attachments copied to the site, `{{< highlight >}}` when code
--- fences are off, paired shortcodes, `#+begin_description`, `#+hugo:
--- more` and the front matter (`org.extensions.hugo.front_matter`) put
--- before the body by a body filter. `org.extensions.hugo.export` drives
--- it (which post, which file).
---
--- This file holds the helpers the parts share (booleans, anchors,
--- references, `#+attr_css` styles) and the back-end definition; it
--- loads the transcoders and filters from hugo/backend/: blocks (markup,
--- blocks, headlines), paragraphs (paragraphs, tables, special blocks),
--- links (links, attachments) and template (table of contents,
--- footnotes, filters).

local ox = require("org.export.ox")
local fm = require("org.extensions.hugo.front_matter")

local M = {}
-- The parts in hugo/backend/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.extensions.hugo.backend"] = M

local fmt = string.format
local nw = ox.nw
local trim = ox.trim

local TRIM_PRE = "<!-- trim-pre -->"
local TRIM_POST = "<!-- trim-post -->"

--- Options of the extension (its defaults when it is not enabled).
local function opts()
  return require("org.extensions").opts("hugo") or require("org.extensions.hugo").defaults
end

--- org-hugo--value-get-true-p: nil, false, "", "nil" (and "false") are false.
---@param v any
---@return boolean
local function truthy(v)
  if v == nil or v == false then
    return false
  end
  if type(v) == "string" then
    local l = vim.trim(v):lower()
    return l ~= "" and l ~= "nil" and l ~= "false"
  end
  return true
end
M.truthy = truthy

--- "true" / "false" for a front matter boolean
--- (org-hugo--front-matter-value-booleanize).
---@param v any
---@return string
local function booleanize(v)
  if v == true then
    return "true"
  end
  local l = type(v) == "string" and vim.trim(v):lower() or nil
  if v == nil or v == false or l == "nil" or l == "false" or l == "no" or l == "" then
    return "false"
  elseif l == "t" or l == "true" or l == "yes" then
    return "true"
  end
  error(fmt("%q needs to represent a boolean value", tostring(v)), 0)
end
M.booleanize = booleanize

---------------------------------------------------------------------------
-- Anchors and references
---------------------------------------------------------------------------

local HTML_ESC = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }

local function encode(s)
  return (s:gsub("[&<>]", HTML_ESC))
end

--- Title of a headline as Markdown (for slugs).
local function md_title(h, info)
  return ox.data_with_backend(h.title or {}, "md", info)
end

--- Anchor of a headline (org-hugo--get-anchor with the default
--- `org-hugo-anchor-functions`): its EXPORT_FILE_NAME (a post inside the
--- post), CUSTOM_ID, the slug of its title, or an MD5 of the title.
---@param h table headline
---@param info table
---@return string
function M.anchor(h, info)
  local props = h.props or {}
  local file = nw(props.EXPORT_FILE_NAME)
  if file then
    local bundle = nw(props.EXPORT_HUGO_BUNDLE)
    if bundle and (file == "index" or file == "_index") then
      return vim.fn.fnamemodify(bundle, ":t:r")
    end
    return vim.fn.fnamemodify(file, ":t:r")
  end
  if nw(props.CUSTOM_ID) then
    return props.CUSTOM_ID
  end
  local title = md_title(h, info)
  local slug = nw(title) and nw(fm.slug(title, true))
  if slug then
    return slug
  end
  return vim.fn.sha256(title or ""):sub(1, 6)
end

--- Prefixes of named element anchors (org-blackfriday--get-ref-prefix).
local REF_PREFIX = {
  figure = "figure--",
  radio = "org-radio--",
  ["src-block"] = "code-snippet--",
  table = "table--",
  target = "org-target--",
}

--- Anchor from a `#+name` (org-blackfriday--get-reference), or nil.
---@param el table
---@param kind? string
---@return string|nil
local function named_reference(el, kind)
  local name = el.name
  if not nw(name) then
    return nil
  end
  local prefix = REF_PREFIX[kind or el.type] or ("org-" .. el.type .. "--")
  for _, p in ipairs({ "code__", "tab__", "table__", "img__", "fig__", "figure__", "__" }) do
    if name:sub(1, #p) == p then
      name = name:sub(#p + 1)
      break
    end
  end
  return prefix .. name:gsub("[_/]", "-")
end

--- A valid anchor name (org-blackfriday--valid-html-anchor-name).
local function anchor_name(s)
  return (s:gsub("^%.", ""):gsub("[^%w%-_:%.]", "-"))
end

--- Anchor of a `<<target>>` (org-blackfriday--get-target-anchor).
local function target_anchor(value)
  if value:sub(1, 1) == "." then
    return anchor_name(value)
  end
  return REF_PREFIX.target .. anchor_name(value)
end
M.target_anchor = target_anchor

---------------------------------------------------------------------------
-- Transcoders
---------------------------------------------------------------------------

--- CSS of #+attr_css (org-blackfriday--make-css-property-string).
local function css_string(el)
  local a = ox.read_attribute("attr_css", el)
  local parts = {}
  for _, k in ipairs(a._keys) do
    if a[k] ~= nil then
      parts[#parts + 1] = fmt("%s: %s; ", k, (encode(a[k]):gsub('"', "&quot;")))
    end
  end
  return table.concat(parts, " ")
end

--- A <style> for the first #+attr_html class of `el` from its #+attr_css
--- (org-blackfriday--get-style-str).
local function style_string(el)
  local class = ox.read_attribute("attr_html", el, "class")
  local first = class and class:match("%S+")
  local css = first and css_string(el) or ""
  if nw(css) then
    return fmt("<style>.%s { %s }</style>\n\n", first, css)
  end
  return ""
end

local T = {}

M.transcoders = T

local shared = require("org.extensions.hugo.backend.shared")
shared.REF_PREFIX = REF_PREFIX
shared.TRIM_POST = TRIM_POST
shared.TRIM_PRE = TRIM_PRE
shared.anchor_name = anchor_name
shared.css_string = css_string
shared.encode = encode
shared.fmt = fmt
shared.named_reference = named_reference
shared.nw = nw
shared.opts = opts
shared.style_string = style_string
shared.target_anchor = target_anchor
shared.trim = trim
shared.truthy = truthy

require("org.extensions.hugo.backend.blocks")
require("org.extensions.hugo.backend.paragraphs")
require("org.extensions.hugo.backend.links")
require("org.extensions.hugo.backend.template")

M.backend = ox.define_backend("hugo", {
  parent = "md",
  transcoders = T,
  options = function()
    local o = opts()
    return {
      { "with_toc", nil, "toc", o.with_toc },
      { "section_numbers", nil, "num", o.with_section_numbers },
      { "author", "AUTHOR", nil, ox.user_full_name(), "newline" },
      { "creator", "CREATOR", nil, ox.creator_string() .. " + hugo" },
      { "with_smart_quotes", nil, "'", false },
      { "with_special_strings", nil, "-", false },
      { "with_sub_superscript", nil, "^", "{}" },
      { "hugo_with_locale", "HUGO_WITH_LOCALE", nil, nil },
      { "hugo_front_matter_format", "HUGO_FRONT_MATTER_FORMAT", nil, o.front_matter_format or "toml" },
      { "hugo_level_offset", "HUGO_LEVEL_OFFSET", nil, "1" },
      { "hugo_preserve_filling", "HUGO_PRESERVE_FILLING", nil, o.preserve_filling },
      { "hugo_delete_trailing_ws", "HUGO_DELETE_TRAILING_WS", nil, o.delete_trailing_ws },
      { "hugo_section", "HUGO_SECTION", nil, o.section },
      { "hugo_bundle", "HUGO_BUNDLE", nil, nil },
      { "hugo_base_dir", "HUGO_BASE_DIR", nil, o.base_dir },
      { "hugo_content_folder", "HUGO_BASE_CONTENT_FOLDER", nil, o.content_folder },
      { "hugo_code_fence", "HUGO_CODE_FENCE", nil, true },
      { "hugo_use_code_for_kbd", "HUGO_USE_CODE_FOR_KBD", nil, o.use_code_for_kbd },
      { "hugo_prefer_hyphen_in_tags", "HUGO_PREFER_HYPHEN_IN_TAGS", nil, o.prefer_hyphen_in_tags },
      { "hugo_allow_spaces_in_tags", "HUGO_ALLOW_SPACES_IN_TAGS", nil, o.allow_spaces_in_tags },
      { "hugo_auto_set_lastmod", "HUGO_AUTO_SET_LASTMOD", nil, o.auto_set_lastmod },
      { "hugo_custom_front_matter", "HUGO_CUSTOM_FRONT_MATTER", nil, nil, "space" },
      { "hugo_front_matter_key_replace", "HUGO_FRONT_MATTER_KEY_REPLACE", nil, nil, "space" },
      { "hugo_date_format", "HUGO_DATE_FORMAT", nil, o.date_format },
      { "hugo_paired_shortcodes", "HUGO_PAIRED_SHORTCODES", nil, o.paired_shortcodes, "space" },
      { "html_container", "HTML_CONTAINER", nil, o.container_element },
      { "html_container_class", "HTML_CONTAINER_CLASS", nil, "" },
      { "html_container_nested", "HTML_CONTAINER_NESTED", nil, nil },
      -- front matter
      { "hugo_aliases", "HUGO_ALIASES", nil, nil, "space" },
      { "hugo_audio", "HUGO_AUDIO", nil, nil },
      { "date", "DATE", nil, nil },
      { "description", "DESCRIPTION", nil, nil },
      { "hugo_draft", "HUGO_DRAFT", nil, nil },
      { "hugo_expirydate", "HUGO_EXPIRYDATE", nil, nil },
      { "hugo_headless", "HUGO_HEADLESS", nil, nil },
      { "hugo_images", "HUGO_IMAGES", nil, nil, "newline" },
      { "hugo_iscjklanguage", "HUGO_ISCJKLANGUAGE", nil, nil },
      { "hugo_keywords", "KEYWORDS", nil, nil, "newline" },
      { "hugo_layout", "HUGO_LAYOUT", nil, nil },
      { "hugo_lastmod", "HUGO_LASTMOD", nil, nil },
      { "hugo_linktitle", "HUGO_LINKTITLE", nil, nil },
      { "hugo_locale", "HUGO_LOCALE", nil, nil },
      { "hugo_markup", "HUGO_MARKUP", nil, nil },
      { "hugo_menu", "HUGO_MENU", nil, nil, "space" },
      { "hugo_menu_override", "HUGO_MENU_OVERRIDE", nil, nil, "space" },
      { "hugo_outputs", "HUGO_OUTPUTS", nil, nil, "space" },
      { "hugo_publishdate", "HUGO_PUBLISHDATE", nil, nil },
      { "hugo_series", "HUGO_SERIES", nil, nil, "newline" },
      { "hugo_slug", "HUGO_SLUG", nil, nil },
      { "hugo_tags", "HUGO_TAGS", nil, nil, "newline" },
      { "hugo_categories", "HUGO_CATEGORIES", nil, nil, "newline" },
      { "hugo_resources", "HUGO_RESOURCES", nil, nil, "space" },
      { "hugo_type", "HUGO_TYPE", nil, nil },
      { "hugo_url", "HUGO_URL", nil, nil },
      { "hugo_videos", "HUGO_VIDEOS", nil, nil, "newline" },
      { "hugo_weight", "HUGO_WEIGHT", nil, nil, "space" },
    }
  end,
  filters = {
    options = { shared.options_filter },
    body = { shared.body_filter },
  },
})

return M
