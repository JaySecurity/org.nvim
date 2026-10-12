---@mod org.export.html.latex HTML LaTeX environments and fragments
---
--- MathJax, images and verbatim output of LaTeX environments and
--- fragments (org-html-latex-environment, org-html-latex-fragment).
---
--- Part of org.export.html, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local shared = require("org.export.html.shared")

local M = require("org.export.html")

local nw = ox.nw
local fmt = string.format

local T = shared.T
local close_tag = shared.close_tag
local encode = shared.encode
local opt = shared.opt

--- Math environments (org-latex-math-environments-re).
local MATH_ENVS = {
  "equation",
  "eqnarray",
  "math",
  "displaymath",
  "align",
  "gather",
  "multline",
  "flalign",
  "alignat",
  "xalignat",
  "xxalignat",
  "subequations",
  "dmath",
  "dseries",
  "dgroup",
  "darray",
  "dsuspend",
}
function M.math_environment_p(el)
  local env = (el.value or ""):match("^[ \t]*\\begin{([^}]+)}")
  if not env then
    return false
  end
  env = env:gsub("%*$", "")
  for _, e in ipairs(MATH_ENVS) do
    if env == e then
      return true
    end
  end
  return false
end

local function latex_env_numbered_p(el)
  local env = (el.value or ""):match("^[ \t]*\\begin{([^}]+)}") or ""
  return not (env:match("%*$") or env == "displaymath")
end

--- org-html--unlabel-latex-environment: equation -> equation*.
local function unlabel_latex_environment(frag)
  frag = frag:gsub("^([ \t]*\\begin{)([^*}]+)(})", "%1%2*%3", 1)
  local a, b, name = frag:find("\n[ \t]*\\end{([^*}]+)}[ \r\t\n]*$")
  if not a then
    a, b, name = frag:find("^[ \t]*\\end{([^*}]+)}[ \r\t\n]*$")
  end
  if a then
    local s = frag:find("{", a, true)
    frag = frag:sub(1, s) .. name .. "*" .. frag:sub(s + 1 + #name)
  end
  return frag
end

--- org-html-format-latex for a LaTeX image process (dvipng, dvisvgm,
--- imagemagick, ...): the picture is made once in
--- ltximg/<file>_<hash>.<ext> next to the output (org-format-latex); the
--- link relative to it is returned, or nil.
function M.latex_image(frag, process, info)
  local odt = require("org.export.odt")
  local spec = odt.latex_image_process(process)
  if not spec then
    return nil
  end
  local bfn = info.input_file or (vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/latex" .. tostring(vim.uv.hrtime()))
  local ui = (require("org.config").opts.ui or {}).latex_preview or {}
  local imgdir = ui.image_directory or "ltximg/"
  if not imgdir:match("/$") then
    imgdir = imgdir .. "/"
  end
  local prefix = imgdir .. vim.fn.fnamemodify(bfn, ":t:r")
  local cache_dir = vim.fn.fnamemodify(info.output_file or bfn, ":p:h")
  local hash = require("org.babel.sha1").hex(table.concat({ process, info.latex_header or "", frag }, "\0"))
  local ext = spec.image_output_type or "png"
  local linkfile = fmt("%s_%s.%s", prefix, hash, ext)
  local movefile = require("org.utils").is_absolute(imgdir) and linkfile or (cache_dir .. "/" .. linkfile)
  if not vim.uv.fs_stat(movefile) then
    local made = odt.latex_to_image(frag, process, info)
    if not made then
      return nil
    end
    vim.fn.mkdir(vim.fn.fnamemodify(movefile, ":h"), "p")
    vim.uv.fs_copyfile(made, movefile)
    vim.fn.delete(vim.fn.fnamemodify(made, ":h"), "rf")
  end
  return linkfile
end

--- org-format-latex-as-html: the output of
--- `export.html.latex_to_html_convert_command` (org-latex-to-html-convert-command,
--- %i = the fragment), or the fragment when there is no command.
function M.latex_to_html(frag)
  local cmd = opt("latex_to_html_convert_command", nil)
  if not nw(cmd) then
    return frag
  end
  local odt = require("org.export.odt")
  return odt.shell_command_to_string(odt.format_spec(cmd, { i = odt.shellescape(frag) }))
end

--- The <img> of a LaTeX picture; the alt text is the LaTeX source.
local function latex_img(link, frag, attrs, info)
  return M.format_image(link, attrs, info, encode(frag))
end

T["latex-environment"] = function(el, _, info)
  local ptype = info.with_latex
  local frag = table.concat(
    element.remove_indentation(vim.split((el.value:gsub("\n$", "")), "\n", { plain = true })),
    "\n"
  ) .. "\n"
  local label = M.reference(el, info, true)
  if ptype == true or ptype == "mathjax" then
    if nw(label) then
      frag = frag:gsub("^([^\n]*)", function(first)
        return first .. "\n\\label{" .. label .. "}"
      end, 1)
    end
    return frag
  end
  local caption
  if latex_env_numbered_p(el) and M.math_environment_p(el) then
    caption = tostring(ox.get_ordinal(el, info, nil, function(l)
      return M.math_environment_p(l) and latex_env_numbered_p(l)
    end))
  end
  local function wrap(contents)
    return fmt(
      '\n<div%s class="equation-container">\n%s%s\n</div>',
      nw(label) and fmt(' id="%s"', label) or "",
      fmt('<span class="equation">\n%s\n</span>', contents),
      nw(caption) and fmt('\n<span class="equation-label">\n%s\n</span>', caption) or ""
    )
  end
  if require("org.export.odt").latex_image_process(ptype) then
    local src = unlabel_latex_environment(frag)
    local link = M.latex_image(src, ptype, info)
    if not link then
      require("org.utils").warn("LaTeX to image conversion failed (" .. ptype .. ")")
      return nil
    end
    return wrap(latex_img(link, src, ox.read_attribute("attr_html", el), info))
  end
  return wrap(frag)
end

--- $…$ and $$…$$ become \(…\) and \[…\] for MathJax (org-format-latex with
--- mathjax processing).
function M.mathjax_fragment(frag)
  if frag:match("^%$%$") then
    return "\\[" .. frag:sub(3, -3) .. "\\]"
  elseif frag:match("^%$") then
    return "\\(" .. frag:sub(2, -2) .. "\\)"
  end
  return frag
end

--- org-html-with-latex (`tex:` / export.html.with_latex): true or "mathjax"
--- (MathJax), "html" (latex_to_html_convert_command), a LaTeX image
--- process ("dvipng", "dvisvgm", "imagemagick", ...: pictures), anything
--- else (verbatim, false) leaves the LaTeX as it is.
T["latex-fragment"] = function(el, _, info)
  local ptype = info.with_latex
  if ptype == true or ptype == "mathjax" then
    return M.mathjax_fragment(el.value)
  elseif ptype == "html" then
    return M.latex_to_html(el.value)
  elseif require("org.export.odt").latex_image_process(ptype) then
    local link = M.latex_image(el.value, ptype, info)
    if not link then
      require("org.utils").warn("LaTeX to image conversion failed (" .. ptype .. ")")
      return nil
    end
    return latex_img(link, el.value, nil, info)
  end
  return el.value
end

T["line-break"] = function(_, _, info)
  return close_tag("br", nil, info) .. "\n"
end
