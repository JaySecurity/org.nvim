---@mod org.export.html.code HTML source code
---
--- Fontified code (htmlize), its CSS and the code lines of blocks
--- (org-html-format-code, org-html-do-format-code).
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local fmt = string.format

local encode = shared.encode
local hcfg = shared.hcfg
local opt = shared.opt

---------------------------------------------------------------------------
-- Code
---------------------------------------------------------------------------

--- Colour `code` like org-html-fontify-code with htmlize: tree-sitter
--- captures become <span class="PREFIXface"> (org-html-htmlize-output-type
--- "css", PREFIX = org-html-htmlize-font-prefix) or <span style="...">
--- with the colours of the highlight groups ("inline-css"). Plain text
--- without a language, with the output type false, or when the language
--- has no tree-sitter parser (Emacs: no major mode).
function M.htmlize(code, lang)
  local ty = opt("htmlize_output_type", "inline-css")
  if not lang or not ty then
    return encode(code)
  end
  local F = require("org.export.fontify")
  local runs = F.runs(code, lang)
  if not runs then
    return encode(code)
  end
  local prefix = opt("htmlize_font_prefix", "org-")
  local tslang = F.ts_lang(lang)
  local styles = {}
  local out = {}
  for i, line in ipairs(runs) do
    local parts = {}
    for _, r in ipairs(line) do
      local text = encode(r[1])
      local face = r[2] and F.face(r[2])
      if face and ty == "css" then
        text = fmt('<span class="%s%s">%s</span>', prefix, face, text)
      elseif face then
        local style = styles[r[2]]
        if style == nil then
          style = table.concat(F.css_specs(F.hl("@" .. r[2], tslang)), " ")
          styles[r[2]] = style
        end
        if style ~= "" then
          text = fmt('<span style="%s">%s</span>', style, text)
        end
      end
      parts[#parts + 1] = text
    end
    out[i] = table.concat(parts)
  end
  return table.concat(out, "\n")
end

local function fontify(code, lang)
  local hl = hcfg().fontify
  if lang and type(hl) == "function" then
    local ok, r = pcall(hl, code, lang)
    if ok and r then
      return r
    end
  end
  return M.htmlize(code, lang)
end

--- The stylesheet of the htmlize classes (org-html-htmlize-generate-css):
--- a <style> element with one rule per face, coloured like the highlight
--- groups of the current colour scheme, to copy into a CSS file for
--- `htmlize_output_type = "css"`.
function M.htmlize_css()
  local F = require("org.export.fontify")
  local prefix = opt("htmlize_font_prefix", "org-")
  -- one rule per face, from the first capture giving it
  local rules = {}
  for _, f in ipairs(F.FACES) do
    local face = f[2]
    if face and rules[face] == nil then
      local specs = F.css_specs(F.hl("@" .. f[1]))
      rules[face] = #specs > 0 and { "@" .. f[1], specs } or false
    end
  end
  for face, r in pairs(rules) do
    if not r then
      rules[face] = nil
    end
  end
  local names = vim.tbl_keys(rules)
  table.sort(names)
  local normal = F.hl("Normal")
  local out = { '<style type="text/css">', "    <!--", "      body {" }
  out[#out + 1] = fmt("        color: %s;", normal.fg and fmt("#%06x", normal.fg) or "#000000")
  out[#out + 1] = fmt("        background-color: %s;", normal.bg and fmt("#%06x", normal.bg) or "#ffffff")
  out[#out + 1] = "      }"
  for _, face in ipairs(names) do
    out[#out + 1] = fmt("      .%s%s {", prefix, face)
    out[#out + 1] = fmt("        /* %s */", rules[face][1])
    for _, s in ipairs(rules[face][2]) do
      out[#out + 1] = "        " .. s
    end
    out[#out + 1] = "      }"
  end
  vim.list_extend(out, {
    "",
    "      a {",
    "        color: inherit;",
    "        background-color: inherit;",
    "        font: inherit;",
    "        text-decoration: inherit;",
    "      }",
    "      a:hover {",
    "        text-decoration: underline;",
    "      }",
    "    -->",
    "</style>",
  })
  return out
end

--- Show the htmlize stylesheet in a "*html*" buffer
--- (org-html-htmlize-generate-css).
function M.htmlize_generate_css()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") == "*html*" then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
  local lines = M.htmlize_css()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(buf, "*html*")
  vim.bo[buf].filetype = "html"
  -- next to an unsaved buffer that can't be hidden: in a split
  require("org.utils").set_current_buf(buf)
  return buf
end

function M.do_format_code(code, lang, refs, retain_labels, num_start, wrap_lines)
  local lines = vim.split(code, "\n", { plain = true })
  local num_fmt = num_start and ("%" .. #tostring(#lines + num_start) .. "d: ") or nil
  code = fontify(code, lang)
  return ox.format_code(code, function(loc, num, ref)
    local s = (num_start and fmt('<span class="linenr">%s</span>', fmt(num_fmt, num)) or "")
      .. (wrap_lines and fmt("<code%s>%s</code>", num_start and fmt(' data-ox-html-linenr="%s"', num) or "", loc) or loc)
      .. ((ref and retain_labels) and fmt(" (%s)", ref) or "")
    if ref then
      return fmt('<span id="coderef-%s" class="coderef-off">%s</span>', ref, s)
    end
    return s
  end, num_start, refs)
end

function M.format_code_of(el, info)
  local code, refs = ox.unravel_code(el)
  return M.do_format_code(code, el.language, refs, el.retain_labels, ox.get_loc(el, info), info.html_wrap_src_lines)
end

local function textarea_block(el)
  local code = ox.unravel_code(el)
  local attr = ox.read_attribute("attr_html", el)
  local _, count = code:gsub("\n", "")
  return fmt(
    '<p>\n<textarea cols="%s" rows="%s">\n%s</textarea>\n</p>',
    attr.width or 80,
    attr.height or (count + 1),
    code
  )
end

-- Locals the later parts share
shared.fontify = fontify
shared.textarea_block = textarea_block
