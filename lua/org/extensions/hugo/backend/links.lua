---@mod org.extensions.hugo.backend.links Hugo transcoders: links and attachments
---
--- Links (`{{< relref >}}` to other posts and Org files, images,
--- `info:` links to the GNU manuals) and attachments copied to the site.
--- Part of org.extensions.hugo.backend, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local html = require("org.export.html")
local md = require("org.export.markdown")
local shared = require("org.extensions.hugo.backend.shared")

local M = require("org.extensions.hugo.backend")

local T = M.transcoders
local fmt = shared.fmt
local nw = shared.nw
local trim = shared.trim
local opts = shared.opts
local encode = shared.encode
local REF_PREFIX = shared.REF_PREFIX
local named_reference = shared.named_reference
local anchor_name = shared.anchor_name
local target_anchor = shared.target_anchor

---------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------

local EXTERNAL = { http = true, https = true, ftp = true, mailto = true }

--- The `{{< relref >}}` of a link to another post or Org file.
local function relref(ref)
  return fmt('{{< relref "%s" >}}', ref)
end

--- Attributes of #+attr_html above the paragraph of `link`, when it is
--- the paragraph's first link.
local function link_attrs(link, info)
  local parent = element.parent_element(link)
  if not parent then
    return { _keys = {} }
  end
  local first = element.map(parent, "link", function(l)
    return l
  end, { first_match = true, ignore = info.ignore })
  if first ~= link then
    return { _keys = {} }
  end
  return ox.read_attribute("attr_html", parent)
end

--- Description and anchor of a link resolved in this post's tree.
local function internal_link(el, dest, desc, info)
  if dest.type == "headline" then
    local d = nw(desc)
    if not d then
      if ox.numbered_headline_p(dest, info) then
        local nums = {}
        for i, n in ipairs(ox.get_headline_number(dest, info) or {}) do
          nums[i] = tostring(n)
        end
        d = table.concat(nums, ".")
      else
        d = ox.data(dest.title, info)
      end
    end
    return fmt("[%s](#%s)", d, M.anchor(dest, info))
  end
  local d = nw(desc)
  if not d then
    local number = ox.get_ordinal(dest, info, nil, function(e)
      return ox.get_caption(e) ~= nil
    end)
    if type(number) == "number" then
      d = tostring(number)
    elseif type(number) == "table" then
      local parts = {}
      for i, x in ipairs(number) do
        parts[i] = tostring(x)
      end
      d = table.concat(parts, ".")
    end
    if d and opts().link_desc_insert_type then
      local kind = dest.type == "paragraph" and "Figure" or dest.type == "table" and "Table" or "Code Snippet"
      d = ox.translate(kind, "html", info) .. " " .. d
    end
  end
  if not d then
    return nil
  end
  local ref
  if dest.type == "src-block" or dest.type == "table" then
    ref = named_reference(dest) or ox.get_reference(dest, info)
  elseif dest.type == "paragraph" and html.standalone_image_p(dest, info) then
    ref = named_reference(dest, "figure") or ox.get_reference(dest, info)
  elseif dest.type == "target" then
    ref = target_anchor(dest.value)
  else
    ref = ox.get_reference(dest, info)
  end
  _ = el
  return fmt("[%s](#%s)", d, ref)
end

--- A link to a heading, target or name outside this post, through the
--- index of the whole file the driver builds (`info.hugo_index`).
local function outside_link(el, desc, info)
  local index = info.hugo_index
  if not index then
    return nil
  end
  local t = el.link_type
  local entry
  if t == "custom-id" then
    entry = index.custom_id[el.path]
  elseif t == "id" then
    entry = index.id[el.path]
  else
    local path = el.path
    if path:sub(1, 1) == "*" then
      entry = index.title[vim.trim(path:sub(2))]
    else
      entry = index.target[path] or index.name[path] or index.title[path]
    end
  end
  if not entry or not entry.post then
    return nil
  end
  local ref
  if entry.is_post or not entry.anchor or (t == "fuzzy" and el.path:sub(1, 1) ~= "*" and not entry.headline) then
    ref = entry.post
  else
    ref = entry.post .. "#" .. entry.anchor
  end
  local d = nw(desc) or (entry.headline and entry.title) or nil
  return fmt("[%s](%s)", d or relref(ref), relref(ref))
end

--- Anchor of the place a search option finds in an Org file
--- (org-hugo--search-and-get-anchor): a post's slug, or "#anchor".
local function search_anchor(file, search, info)
  local lines = require("org.utils").readfile(file)
  if not lines then
    error(fmt("Unable to open Org file `%s'", file), 0)
  end
  local index = require("org.extensions.hugo.export").link_index(lines, file, info)
  local entry
  if search:sub(1, 1) == "#" then
    entry = index.custom_id[search:sub(2)]
  elseif search:sub(1, 1) == "*" then
    entry = index.title[vim.trim(search:sub(2))]
  else
    entry = index.target[search] or index.name[search] or index.title[search]
  end
  if not entry or not entry.anchor then
    return ""
  end
  if entry.is_post then
    return entry.anchor
  end
  return "#" .. entry.anchor
end

local function image_link(el, desc, info)
  local parent = el.parent
  local useful = (parent and parent.type == "link") and parent.parent or parent
  local a = useful and ox.read_attribute("attr_html", useful) or { _keys = {} }
  local caption
  local pe = element.parent_element(el)
  local cap = pe and ox.get_caption(pe)
  if cap then
    caption = nw(ox.data(cap, info))
  end
  caption = caption or nw(a.caption)
  if caption then
    local num = ox.get_ordinal(useful, info, nil, function(e)
      return ox.get_caption(e) ~= nil or ox.read_attribute("attr_html", e, "caption") ~= nil
    end)
    caption = fmt(
      '<span class="figure-number">%s %s: </span>%s',
      ox.translate("Figure", "html", info),
      tostring(type(num) == "table" and num[#num] or num or 1),
      caption
    )
  end
  local raw = el.path
  local external = EXTERNAL[el.link_type]
  local path = external and raw or M.attachment(raw, info)
  local source = external and (el.link_type .. ":" .. path) or path
  local standalone = useful and useful.type == "paragraph" and html.standalone_image_p(useful, info)
  local nattrs = 0
  for _, k in ipairs(a._keys) do
    if a[k] ~= nil then
      nattrs = nattrs + 1
    end
  end
  _ = desc
  if not standalone then
    if nattrs == 0 or (a.alt and nattrs == 1) then
      return fmt("![%s](%s)", a.alt or "", source)
    end
    a.target, a.rel = nil, nil
    return html.format_image(source, a, info)
  end
  local params = {
    { "src", source },
    { "alt", a.alt },
    { "caption", caption and caption:gsub('"', '\\"') or nil },
    { "link", a.link },
    { "title", a.title },
    { "class", a.class },
    { "attr", a.attr },
    { "attrlink", a.attrlink },
    { "width", a.width },
    { "height", a.height },
    { "target", a.target },
    { "rel", a.rel },
  }
  local parts = {}
  for _, p in ipairs(params) do
    if p[2] ~= nil then
      parts[#parts + 1] = fmt('%s="%s"', p[1], p[2])
    end
  end
  return "{{< figure " .. table.concat(parts, " ") .. " >}}"
end

T.link = function(el, desc, info)
  local t = el.link_type
  desc = (desc ~= nil and desc ~= "") and desc or nil
  local custom = ox.custom_protocol_maybe(el, desc, "md", info)
  if custom then
    return custom
  end
  if t == "custom-id" or t == "id" or t == "fuzzy" then
    local ok, dest = pcall(t == "fuzzy" and ox.resolve_fuzzy_link or ox.resolve_id_link, el, info)
    if ok and dest and dest.type ~= "plain-text" then
      return internal_link(el, dest, desc, info)
    end
    local out = outside_link(el, desc, info)
    if out then
      return out
    end
    if t == "id" then
      local loc = require("org.extensions.hugo.export").find_id(el.path, info)
      if loc then
        local ref = loc.anchor and (loc.is_post and loc.anchor or (loc.ref .. "#" .. loc.anchor)) or loc.ref
        return fmt("[%s](%s)", desc or relref(ref), relref(ref))
      end
    end
    if ok and dest and dest.type == "plain-text" then
      local p = dest.value:gsub("%.[Oo][Rr][Gg]$", ".md")
      return desc and fmt("[%s](%s)", desc, p) or fmt("<%s>", p)
    end
    error(dest, 0)
  end
  if ox.inline_image_p(el, html.inline_image_rules) then
    return image_link(el, desc, info)
  end
  if t == "info" then
    return M.info_link(el.path, desc)
  end
  if t == "coderef" or t == "radio" then
    if t == "radio" then
      local dest = ox.resolve_radio_link(el, info)
      if not dest then
        return desc
      end
      return fmt("[%s](#%s)", desc or "", REF_PREFIX.radio .. anchor_name(dest.value))
    end
    return md.transcoders.link(el, desc, info)
  end
  local path
  local params = ""
  if EXTERNAL[t] then
    local a = link_attrs(el, info)
    local parts = {}
    for _, k in ipairs({ "title", "style", "referrerpolicy", "media", "target", "rel", "sizes", "type" }) do
      if a[k] ~= nil then
        parts[#parts + 1] = fmt('%s="%s"', k, a[k])
      end
    end
    params = table.concat(parts, " ")
    path = t .. ":" .. html.url_encode(el.path)
  elseif t == "file" then
    local p = el.path:gsub("^file://", "")
    if p:lower():match("%.org$") then
      local ref = vim.fn.fnamemodify(p, ":t:r")
      local anchor = ""
      if nw(el.search_option) then
        local base = info.input_file and vim.fn.fnamemodify(info.input_file, ":p:h") or vim.fn.getcwd()
        anchor = search_anchor(require("org.utils").expand(p, base), el.search_option, info)
      end
      if nw(anchor) and anchor:sub(1, 1) ~= "#" then
        path = relref(anchor)
      elseif nw(ref) or nw(anchor) then
        path = relref(ref .. anchor)
      else
        path = ""
      end
    else
      path = M.attachment(p, info)
    end
  else
    path = el.path
  end
  if desc and desc:match("^{{<%s*figure%s+") and not desc:match("^{{<%s*figure%s+.*link=") then
    return (desc:gsub("%s*>}}$", function(m)
      return fmt(' link="%s"', path) .. m
    end))
  elseif desc and nw(params) then
    return fmt('<a href="%s" %s>%s</a>', encode(path), params, desc)
  elseif desc then
    if not path:match("^{{< relref ") and path:match("%s") then
      path = "<" .. path .. ">"
    end
    return fmt("[%s](%s)", desc, path)
  elseif nw(params) then
    local p = encode(path)
    return fmt('<a href="%s" %s>%s</a>', p, params, (p:gsub(":", "&colon;")))
  elseif path:match("^{{< relref ") then
    return fmt("[%s](%s)", path, path)
  elseif nw(path) then
    return "<" .. path .. ">"
  end
  return ""
end

--- Emacs manuals on gnu.org (org-info-emacs-documents).
local EMACS_MANUALS = {}
for _, m in ipairs({
  "ada-mode",
  "auth",
  "autotype",
  "bovine",
  "calc",
  "ccmode",
  "cl",
  "dbus",
  "dired-x",
  "ebrowse",
  "ede",
  "ediff",
  "edt",
  "efaq",
  "efaq-w32",
  "eglot",
  "eieio",
  "eintr",
  "elisp",
  "emacs",
  "emacs-gnutls",
  "emacs-mime",
  "epa",
  "erc",
  "ert",
  "eshell",
  "eudc",
  "eww",
  "flymake",
  "forms",
  "gnus",
  "htmlfontify",
  "idlwave",
  "ido",
  "info",
  "mairix-el",
  "message",
  "mh-e",
  "modus-themes",
  "newsticker",
  "nxml-mode",
  "octave-mode",
  "org",
  "pcl-cvs",
  "pgg",
  "rcirc",
  "reftex",
  "remember",
  "sasl",
  "sc",
  "semantic",
  "ses",
  "sieve",
  "smtpmail",
  "speedbar",
  "srecode",
  "todo-mode",
  "tramp",
  "transient",
  "url",
  "use-package",
  "vhdl-mode",
  "vip",
  "viper",
  "vtable",
  "widget",
  "wisent",
  "woman",
}) do
  EMACS_MANUALS[m] = true
end

--- GNU software with manuals on gnu.org (org-hugo-info-gnu-software).
local GNU_SOFTWARE = {}
for name in
  ([[
3dldf 8sync a2ps acct acm adns alive anubis apl archimedes aris artanis aspell auctex autoconf
autoconf-archive autogen automake avl ballandpaddle barcode bash bayonne bazaar bc behistun bfd
binutils bison bool bpel2owfn c-graph ccaudio ccd2cue ccide ccrtp ccscript cflow cgicc chess cim
classpath classpathx clisp combine commoncpp complexity config consensus coreutils cpio cppi
cssc cursynth dap datamash dc ddd ddrescue dejagnu denemo dia dico diction diffutils direvent
djgpp dominion dr-geo easejs ed edma electric emacs emacs-muse emms enscript epsilon fdisk
ferret findutils fisicalab foliot fontopia fontutils freedink freefont freeipmi freetalk fribidi
g-golf gama garpd gawk gcal gcc gcide gcl gcompris gdb gdbm gengen gengetopt gettext gforth
ggradebook ghostscript gift gimp glean global glpk glue gmediaserver gmp gnash gnat gnats
gnatsweb gnowsys gnu-c-manual gnu-crypto gnu-pw-mgr gnuae gnuastro gnubatch gnubg gnubiff gnubik
gnucap gnucash gnucobol gnucomm gnudos gnufm gnugo gnuit gnujdoc gnujump gnukart gnulib gnumach
gnumed gnumeric gnump3d gnun gnunet gnupg gnupod gnuprologjava gnuradio gnurobots gnuschool
gnushogi gnusound gnuspeech gnuspool gnustandards gnustep gnutls gnutrition gnuzilla goptical
gorm gpaint gperf gprolog grabcomics greg grep gretl groff grub gsasl gsegrafix gsl gslip gsrc
gss gtick gtypist guile guile-cv guile-dbi guile-gnome guile-ncurses guile-opengl guile-rpc
guile-sdl guix gurgle gv gvpe gwl gxmessage gzip halifax health hello help2man hp2xx html-info
httptunnel hurd hyperbole icecat idutils ignuit indent inetutils inklingreader intlfonts jacal
jami java-getopt jel jitter jtw jwhois kawa kopi leg less libc libcdio libdbh liberty-eiffel
libextractor libffcall libgcrypt libiconv libidn libjit libmatheval libmicrohttpd libredwg
librejs libsigsegv libtasn1 libtool libunistring libxmi lightning lilypond lims linux-libre
liquidwar6 lispintro lrzsz lsh m4 macchanger mailman mailutils make marst maverik mc mcron mcsim
mdk mediagoblin melting mempool mes metaexchange metahtml metalogic-inference mifluz mig
miscfiles mit-scheme moe motti mpc mpfr mpria mtools nana nano nano-archimedes ncurses nettle
network ocrad octave oleo oo-browser orgadoc osip panorama parallel parted pascal patch paxutils
pcb pem pexec pies pipo plotutils poke polyxmass powerguru proxyknife pspp psychosynth pth
pythonwebkit qexo quickthreads r radius rcs readline recutils reftex remotecontrol rottlog rpge
rush sather scm screen sed serveez sharutils shepherd shishi shmm shtool sipwitch slib smalltalk
social solfege spacechart spell sqltutor src-highlite ssw stalkerfs stow stump superopt swbis
sysutils taler talkfilters tar termcap termutils teseq teximpatient texinfo texmacs time tramp
trans-coord trueprint unifont units unrtf userv uucp vc-dwim vcdimager vera vmgen wb wdiff
websocket4j webstump wget which womb xaos xboard xlogmaster xmlat xnee xorriso zile
]]):gmatch("%S+")
do
  GNU_SOFTWARE[name] = true
end

--- An `info:` link as a link to the manual on the web
--- (org-hugo--org-info-export): Org's on orgmode.org, Emacs' on gnu.org.
---@param path string
---@param desc string|nil
---@return string
function M.info_link(path, desc)
  local manual, node = path:match("^([^#:]*)[#:]:?(.*)$")
  manual = manual or path
  node = (node and node ~= "") and node or "Top"
  local title = fmt('Emacs Lisp: (info \\"(%s) %s\\")', manual, node)
  if not desc then
    local cap = manual:sub(1, 1):upper() .. manual:sub(2):lower()
    desc = node == "Top" and (cap .. " Info") or fmt("%s Info: %s", cap, node)
  end
  local function node_url()
    if node == "Top" then
      return "index.html"
    end
    local parts = {}
    for _, c in ipairs(vim.fn.split((node:gsub("[ \t\n\r]+", " ")), "\\zs")) do
      if c == " " then
        parts[#parts + 1] = "-"
      elseif c:match("^[%w]$") then
        parts[#parts + 1] = c
      else
        parts[#parts + 1] = fmt("_%04x", vim.fn.char2nr(c))
      end
    end
    local n = table.concat(parts)
    if n:match("^%d") then
      n = "g_t" .. n
    end
    return n .. ".html"
  end
  local link
  if manual:lower() == "org" then
    link = "https://orgmode.org/manual/" .. node_url()
  elseif EMACS_MANUALS[manual] then
    link = fmt("https://www.gnu.org/software/emacs/manual/html_node/%s/%s", manual, node_url())
  elseif GNU_SOFTWARE[manual] then
    link = fmt("https://www.gnu.org/software/%s/manual/html_node/%s", manual, node_url())
  else
    link = manual .. ".html"
  end
  return fmt('[%s](%s "%s")', desc, link, title)
end

---------------------------------------------------------------------------
-- Attachments
---------------------------------------------------------------------------

local function realpath(p)
  return vim.uv.fs_realpath(p) or vim.fs.normalize(p)
end

local function copy_if_newer(src, dest)
  local s = vim.uv.fs_stat(src)
  local d = vim.uv.fs_stat(dest)
  if d and s and d.mtime.sec >= s.mtime.sec then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
  local ok, err = vim.uv.fs_copyfile(src, dest)
  if not ok then
    error(fmt("Cannot copy %s to %s: %s", src, dest, tostring(err)), 0)
  end
end

--- Copy a linked local file to the site and return its path there
--- (org-hugo--attachment-rewrite-maybe): files already under `static/`
--- or the bundle keep their path; a path with `/static/` in it goes to
--- the same place under the site's static dir; in a page bundle files
--- go into the bundle; others go to `static/<static_subdir>/`. Files
--- whose extension is not in `copy_extensions`, or that do not exist,
--- keep their path.
---@param path string
---@param info table
---@return string
function M.attachment(path, info)
  local base = info.hugo_base_dir_abs
  if not base then
    return path
  end
  local src_dir = info.input_file and vim.fn.fnamemodify(info.input_file, ":p:h") or vim.fn.getcwd()
  local unhex = path:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  local file = require("org.utils").expand(unhex, src_dir)
  local ext = vim.fn.fnamemodify(unhex, ":e"):lower()
  local allowed = false
  for _, e in ipairs(opts().copy_extensions or {}) do
    if e:lower() == ext then
      allowed = true
    end
  end
  local static = base .. "/static"
  local bundle = info.hugo_bundle_dir
  local dest_dir = bundle or static
  if vim.fn.isdirectory(static) == 0 then
    error(fmt("Please create the %s directory", static), 0)
  end
  if not (allowed and vim.uv.fs_stat(file) and vim.fn.isdirectory(dest_dir) == 1) then
    return path
  end
  local real = realpath(file)
  local real_dest = realpath(dest_dir)
  if real:sub(1, #real_dest + 1) == real_dest .. "/" then
    return "/" .. real:sub(#real_dest + 2)
  end
  local rel
  local s = real:find("/static/", 1, true)
  if s then
    dest_dir = static
    rel = real:sub(s + 8)
  elseif bundle then
    local name = vim.fn.fnamemodify(bundle, ":t")
    local content = realpath(base .. "/" .. (info.hugo_content_folder or "content"))
    if realpath(bundle) == content then
      name = "_home"
    end
    local b = real:find("/" .. name .. "/", 1, true)
    local srcd = realpath(src_dir) .. "/"
    if b then
      rel = real:sub(b + #name + 2)
    elseif real:sub(1, #srcd) == srcd then
      rel = real:sub(#srcd + 1)
    else
      rel = vim.fn.fnamemodify(unhex, ":t")
    end
  else
    rel = (opts().static_subdir or "ox-hugo") .. "/" .. vim.fn.fnamemodify(unhex, ":t")
  end
  copy_if_newer(real, dest_dir .. "/" .. rel)
  if bundle and dest_dir == bundle then
    return rel
  end
  return "/" .. rel
end

shared.copy_if_newer = copy_if_newer
