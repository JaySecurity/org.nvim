---@mod org.export.cite Citations in export (port of Emacs oc.el export
--- parts and the oc-basic, oc-natbib, oc-biblatex and oc-bibtex processors)
---
--- The engine calls `store` once the export options are known, `process`
--- once the parse tree is complete (citations and #+PRINT_BIBLIOGRAPHY
--- keywords are replaced with the processor's output, as raw strings), and
--- `finalize` on the final output.
---
--- This file holds the configuration, the tree helpers, the generic tools
--- of oc.el and the export interface; the rest loads from org/export/cite/:
--- note (citations in footnotes), bib (bibliography files) and the basic,
--- natbib (with bibtex) and biblatex processors.

local ox = require("org.export.ox")
local element = require("org.export.element")

local M = {}
-- The parts in org/export/cite/ add their functions to this table and
-- require it back, so it must be in package.loaded before they load.
package.loaded["org.export.cite"] = M
local shared = require("org.export.cite.shared")

local fmt = string.format
local nw = ox.nw
local trim = ox.trim

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local function ccfg()
  return (require("org.config").opts.export or {}).cite or {}
end

local function opt(name, default)
  local v = ccfg()[name]
  if v == nil then
    return default
  end
  return v
end

M.DEFAULT_NOTE_RULES = {
  ["en-us"] = { "inside", "outside", "after" },
  fr = { "adaptive", "same", "before" },
}

M.DEFAULT_REGION = {
  af = "za",
  ca = "ad",
  cs = "cz",
  cy = "gb",
  da = "dk",
  el = "gr",
  et = "ee",
  fa = "ir",
  he = "ir",
  ja = "jp",
  km = "kh",
  ko = "kr",
  nb = "no",
  nn = "no",
  sl = "si",
  sr = "rs",
  sv = "se",
  uk = "ua",
  vi = "vn",
  zh = "cn",
}

M.BIBLATEX_STYLES = {
  { "author", "caps", "Citeauthor*", nil, false },
  { "author", "full", "citeauthor", nil, false },
  { "author", "caps-full", "Citeauthor", nil, false },
  { "author", nil, "citeauthor*", nil, false },
  { "locators", "bare", "notecite", nil, false },
  { "locators", "caps", "Pnotecite", nil, false },
  { "locators", "bare-caps", "Notecite", nil, false },
  { "locators", nil, "pnotecite", nil, false },
  { "noauthor", "bare", "cite*", nil, false },
  { "noauthor", nil, "autocite*", nil, false },
  { "nocite", nil, "nocite", nil, true },
  { "text", "caps", "Textcite", "Textcites", false },
  { "text", nil, "textcite", "textcites", false },
  { nil, "bare", "cite", "cites", false },
  { nil, "caps", "Autocite", "Autocites", false },
  { nil, "bare-caps", "Cite", "Cites", false },
  { nil, nil, "autocite", "autocites", false },
}

M.BIBLATEX_SHORTCUTS = {
  a = "author",
  b = "bare",
  bc = "bare-caps",
  c = "caps",
  cf = "caps-full",
  f = "full",
  l = "locators",
  n = "nocite",
  na = "noauthor",
  t = "text",
}

---------------------------------------------------------------------------
-- Tree helpers
---------------------------------------------------------------------------

local function text(s)
  return element.text(s, nil)
end

local function raw(s)
  return { type = "raw", value = s, contents = {}, post_blank = 0 }
end
M.raw = raw

local function index_in(list, node)
  for i, x in ipairs(list or {}) do
    if x == node then
      return i
    end
  end
end

local function insert_before(new, node)
  local list = element.siblings(node)
  local i = index_in(list, node)
  if not i then
    return
  end
  new.parent = node.parent
  table.insert(list, i, new)
end

local function replace_node(old, new)
  local list = element.siblings(old)
  local i = index_in(list, old)
  if i then
    new.parent = old.parent
    list[i] = new
  end
end

local function adopt(parent, node)
  node.parent = parent
  parent.contents = parent.contents or {}
  parent.contents[#parent.contents + 1] = node
end

--- org-cite--set-post-blank
local function set_post_blank(datum, blanks)
  if datum.type == "plain-text" then
    datum.value = datum.value:gsub("[ \t\n]+$", "") .. string.rep(" ", blanks)
  else
    datum.post_blank = blanks
  end
end

local function set_previous_post_blank(datum, blanks, info)
  local prev = ox.get_previous_element(datum, info)
  if prev then
    set_post_blank(prev, blanks)
  end
end
M.set_previous_post_blank = set_previous_post_blank

--- org-cite-concat: flatten strings, nodes and secondary strings.
function M.concat(...)
  local out = {}
  local n = select("#", ...)
  for i = 1, n do
    local d = select(i, ...)
    if d == nil or d == false then
      -- skip
    elseif type(d) == "string" then
      out[#out + 1] = text(d)
    elseif d.type ~= nil then
      out[#out + 1] = d
    else
      for _, x in ipairs(d) do
        if type(x) == "string" then
          out[#out + 1] = text(x)
        else
          out[#out + 1] = x
        end
      end
    end
  end
  return out
end

function M.mapconcat(fn, data, sep)
  if not data or #data == 0 then
    return nil
  end
  local result = M.concat(fn(data[1]))
  for i = 2, #data do
    result = M.concat(result, sep, fn(data[i]))
  end
  return result
end

local function make_node(type, contents)
  local n = { type = type, contents = contents, post_blank = 0 }
  for _, c in ipairs(contents) do
    c.parent = n
  end
  return n
end

function M.emphasize(type, ...)
  return make_node(type, M.concat(...))
end

function M.make_paragraph(...)
  return make_node("paragraph", M.concat(...))
end

--- Emacs `capitalize`: first letter of each word upper case, the rest lower.
local function capitalize_string(s)
  return (s:gsub("([%w\128-\255])([%w\128-\255]*)", function(a, b)
    return a:upper() .. b:lower()
  end))
end

function M.capitalize(str)
  if type(str) == "string" then
    return capitalize_string(str)
  elseif str and str.type == "raw" then
    return raw(capitalize_string(str.value))
  end
  error("must be either a string or raw string object")
end

---------------------------------------------------------------------------
-- Generic tools (oc.el)
---------------------------------------------------------------------------

function M.get_references(citation, keys_only)
  if keys_only then
    local keys = {}
    for i, r in ipairs(citation.contents) do
      keys[i] = r.key
    end
    return keys
  end
  return citation.contents
end

function M.main_affixes(citation)
  local refs = M.get_references(citation)
  local source = #refs == 1 and refs[1] or citation
  return source.prefix, source.suffix
end

local function not_nil(s)
  if s == nil or s == "nil" then
    return nil
  end
  return s
end

--- Style pair { name, variant } of a citation (org-cite-citation-style).
function M.citation_style(citation, info)
  local function separate(s)
    if s == nil then
      return nil, nil
    end
    local a, b = s:match("^(.-)/(.*)$")
    if not a then
      return s, nil
    end
    return a, nw(b)
  end
  local ln, lv = separate(citation.style)
  local ce = info.cite_export
  local gn, gv = separate(type(ce) == "table" and ce[3] or nil)
  if nw(ln) then
    return { not_nil(ln), lv }
  end
  return { not_nil(gn), lv or gv }
end

--- Read a "#+CITE_EXPORT" declaration (org-cite-read-processor-declaration).
function M.read_processor_declaration(s)
  local tokens = {}
  local pos = 1
  while true do
    local ws = s:match("^[ \t]*", pos)
    pos = pos + #ws
    if pos > #s then
      break
    end
    local tok
    if s:sub(pos, pos) == '"' then
      local close = s:find('"', pos + 1, true)
      if not close then
        error(fmt("Invalid cite export processor declaration: %q", s), 0)
      end
      tok = s:sub(pos + 1, close - 1)
      pos = close + 1
    else
      tok = s:match("^[^ \t]+", pos)
      pos = pos + #tok
    end
    tokens[#tokens + 1] = tok
  end
  if #tokens == 0 then
    return nil
  end
  if #tokens > 3 then
    error(fmt("Trailing garbage following cite export processor declaration %q", s), 0)
  end
  return { tokens[1], not_nil(tokens[2]), not_nil(tokens[3]) }
end

--- Processors available for export.
M.processors = {}

local function normalize_triplet(p)
  if type(p) == "string" then
    return { p, nil, nil }
  end
  if type(p) == "table" then
    return { p[1], p[2], p[3] }
  end
end

--- org-cite-store-export-processor
function M.store_export_processor(info)
  local value = info.cite_export
  local processor
  if value == nil or value == "" then
    value = opt("export_processors", { t = { "basic" } })
  end
  if value == false or value == "" then
    processor = nil
  elseif type(value) == "string" then
    processor = M.read_processor_declaration(value)
  elseif type(value) == "table" then
    if value[1] ~= nil and type(value[1]) == "string" then
      -- a single triplet
      processor = normalize_triplet(value)
    else
      local backend = info.back_end
      local candidates = {}
      for key, p in pairs(value) do
        if key ~= "t" and key ~= true and ox.derived_backend_p(backend, key) then
          candidates[#candidates + 1] = { key, p }
        end
      end
      table.sort(candidates, function(a, b)
        if a[1] == b[1] then
          return false
        end
        return ox.derived_backend_p(a[1], b[1])
      end)
      local chosen = candidates[1] and candidates[1][2] or value.t or value[true]
      processor = chosen and normalize_triplet(chosen) or nil
    end
  end
  if processor then
    local name = processor[1]
    if not M.processors[name] then
      error(fmt("Unknown processor %s", name), 0)
    end
    if not M.processors[name].export_citation then
      error(fmt("Processor %s is unable to handle citation export", name), 0)
    end
  end
  info.cite_export = processor
end

--- org-cite-list-bibliography-files: file names as written (relative
--- names are relative to the exported file's directory).
function M.list_bibliography_files(info)
  local files, seen = {}, {}
  local function add(f)
    if f and f ~= "" and not seen[f] then
      seen[f] = true
      files[#files + 1] = f
    end
  end
  for _, v in ipairs((info.keywords or {}).BIBLIOGRAPHY or {}) do
    add((trim(v):gsub('^"(.*)"$', "%1")))
  end
  for _, f in ipairs(opt("global_bibliography", {})) do
    add(f)
  end
  return files
end

--- Absolute name of a bibliography file.
function M.bibliography_path(file, info)
  if file:match("^/") or file:match("^~") or file:match("^%a:[/\\]") then
    return vim.fs.normalize(require("org.utils").expand_vars(file))
  end
  local dir = info.input_file and vim.fn.fnamemodify(info.input_file, ":p:h") or vim.fn.getcwd()
  return vim.fs.normalize(dir .. "/" .. file)
end

function M.store(info)
  info.bibliography = M.list_bibliography_files(info)
  M.store_export_processor(info)
end

function M.bibliography_style(info)
  local ce = info.cite_export
  return type(ce) == "table" and ce[2] or nil
end

--- Parse a string as a property list (org-cite--parse-as-plist).
function M.parse_as_plist(s)
  if s == nil then
    return nil
  end
  local results = {}
  local pos = 1
  local value_flag = false
  local ws = s:match("^[ \t]*", pos)
  pos = pos + #ws
  while pos <= #s do
    local c = s:sub(pos, pos)
    if c == ":" then
      local tok = s:match("^[^ \t]+", pos)
      results[#results + 1] = { keyword = tok }
      pos = pos + #tok
      value_flag = true
    elseif not value_flag then
      local tok = s:match("^[^ \t]*", pos)
      pos = pos + math.max(#tok, 1)
    elseif c == '"' then
      local close = s:find('"', pos + 1, true)
      if close then
        results[#results + 1] = s:sub(pos + 1, close - 1)
        pos = close + 1
      else
        local tok = s:match("^[^ \t]+", pos)
        results[#results + 1] = tok
        pos = pos + #tok
      end
      value_flag = false
    else
      local tok = s:match("^[^ \t]+", pos)
      results[#results + 1] = tok
      pos = pos + #tok
      value_flag = false
    end
    ws = s:match("^[ \t]*", pos)
    pos = pos + #ws
  end
  return results
end

--- Citations of the document in reading order, following footnotes
--- (org-cite-list-citations).
function M.list_citations(info)
  if info.citations then
    return info.citations
  end
  local cites = {}
  local tree = info.parse_tree
  local defs
  local function find_definition(label)
    defs = defs
      or element.map(tree, "footnote-definition", function(d)
        return d
      end, { ignore = info.ignore })
    for _, d in ipairs(defs) do
      if d.label == label then
        return d.contents
      end
    end
  end
  local function search(data)
    if not data then
      return
    end
    element.map(data, { citation = true, ["footnote-reference"] = true }, function(d)
      if d.type == "citation" then
        cites[#cites + 1] = d
      elseif d.fn_type == "inline" then
        -- traversed by map
      else
        search(find_definition(d.label))
      end
    end, { ignore = info.ignore, no_recursion = { ["footnote-definition"] = true }, with_affiliated = true })
  end
  search(tree)
  info.citations = cites
  return cites
end

function M.list_keys(info)
  local keys, seen = {}, {}
  for _, c in ipairs(M.list_citations(info)) do
    for _, r in ipairs(c.contents) do
      if not seen[r.key] then
        seen[r.key] = true
        keys[#keys + 1] = r.key
      end
    end
  end
  return keys
end

--- Stable sort (Emacs `sort`).
local function stable_sort(list, less)
  local out = vim.list_slice(list)
  for i = 2, #out do
    local v = out[i]
    local j = i - 1
    while j >= 1 and less(v, out[j]) do
      out[j + 1] = out[j]
      j = j - 1
    end
    out[j + 1] = v
  end
  return out
end

function M.key_number(key, info, predicate)
  local keys = M.list_keys(info)
  if predicate then
    keys = stable_sort(keys, predicate)
  end
  for i, k in ipairs(keys) do
    if k == key then
      return i
    end
  end
end

function M.inside_footnote_p(citation, strict)
  local fn = element.lineage(citation, { ["footnote-definition"] = true, ["footnote-reference"] = true })
  if not fn then
    return nil
  end
  if strict then
    local c = citation.parent.contents
    if not (#c == 1 and c[1] == citation) then
      return nil
    end
  end
  return fn
end

--- Wrap an anonymous inline footnote around CITATION (org-cite-wrap-citation).
function M.wrap_citation(citation, info)
  local footnote = {
    type = "footnote-reference",
    label = nil,
    fn_type = "inline",
    post_blank = citation.post_blank or 0,
    contents = {},
  }
  set_previous_post_blank(citation, 0, info)
  insert_before(footnote, citation)
  element.extract(citation)
  adopt(footnote, citation)
  return footnote
end

shared.opt = opt
shared.text = text
shared.adopt = adopt
shared.insert_before = insert_before
shared.stable_sort = stable_sort

require("org.export.cite.note")
require("org.export.cite.bib")
require("org.export.cite.basic")
require("org.export.cite.natbib")
require("org.export.cite.biblatex")

---------------------------------------------------------------------------
-- Export interface
---------------------------------------------------------------------------

--- Emacs parses leading blanks after "[cite:" and trailing blanks before
--- "]" as part of the citation markup, not of the affixes.
local function normalize_affixes(citation)
  local ref1 = citation.contents[1]
  local first = citation.prefix and citation.prefix[1] or (ref1 and ref1.prefix and ref1.prefix[1])
  if first and first.type == "plain-text" then
    first.value = first.value:gsub("^[ \t\n]+", "")
    local owner = citation.prefix or citation.contents[1].prefix
    if first.value == "" then
      table.remove(owner, 1)
      if #owner == 0 then
        if citation.prefix then
          citation.prefix = nil
        else
          citation.contents[1].prefix = nil
        end
      end
    end
  end
  local lastref = citation.contents[#citation.contents]
  local owner = citation.suffix or (lastref and lastref.suffix)
  local last = owner and owner[#owner]
  if last and last.type == "plain-text" then
    last.value = last.value:gsub("[ \t\n]+$", "")
    if last.value == "" then
      table.remove(owner, #owner)
      if #owner == 0 then
        if citation.suffix then
          citation.suffix = nil
        else
          lastref.suffix = nil
        end
      end
    end
  end
end

function M.export_citation_now(citation, info)
  local ce = info.cite_export
  if not ce then
    return nil
  end
  local p = M.processors[ce[1]]
  return p.export_citation(citation, M.citation_style(citation, info), info.back_end and info.back_end.name, info)
end

function M.export_bibliography(keyword, info)
  local ce = info.cite_export
  if not ce then
    return nil
  end
  local p = M.processors[ce[1]]
  if not p.export_bibliography then
    return nil
  end
  return p.export_bibliography(
    M.list_keys(info),
    info.bibliography or {},
    M.bibliography_style(info),
    M.parse_as_plist(keyword.value),
    info.back_end,
    info
  )
end

--- org-cite-process-citations + org-cite-process-bibliography
function M.process(info)
  local cites = M.list_citations(info)
  for _, c in ipairs(cites) do
    normalize_affixes(c)
  end
  for _, cite in ipairs(cites) do
    local replacement = M.export_citation_now(cite, info)
    local blanks = cite.post_blank or 0
    if replacement == nil then
      set_previous_post_blank(cite, blanks, info)
    else
      local previous = ox.get_previous_element(cite, info)
      if previous and previous.type == "plain-text" and nw(previous.value) and previous.value:match('"$') then
        set_previous_post_blank(cite, 1, info)
      end
      if type(replacement) == "string" then
        insert_before(raw(trim(replacement) .. string.rep(" ", blanks)), cite)
      elseif replacement.type ~= nil then
        set_post_blank(replacement, blanks)
        insert_before(replacement, cite)
      else
        local last
        for _, d in ipairs(replacement) do
          last = d
          insert_before(d, cite)
        end
        if last then
          set_post_blank(last, blanks)
        end
      end
    end
    element.extract(cite)
  end
  local keywords = element.map(info.parse_tree, "keyword", function(k)
    if k.key == "PRINT_BIBLIOGRAPHY" then
      return k
    end
  end, { ignore = info.ignore })
  for _, keyword in ipairs(keywords) do
    local replacement = M.export_bibliography(keyword, info)
    local blanks = keyword.post_blank or 0
    if replacement == nil then
      set_previous_post_blank(keyword, blanks, info)
      element.extract(keyword)
    elseif type(replacement) == "string" then
      replace_node(keyword, raw((ox.normalize_string(replacement) or "") .. string.rep("\n", blanks)))
    elseif replacement.type ~= nil then
      set_post_blank(replacement, blanks)
      replace_node(keyword, replacement)
    else
      local last
      for _, d in ipairs(replacement) do
        last = d
        insert_before(d, keyword)
      end
      if last then
        set_post_blank(last, blanks)
      end
      element.extract(keyword)
    end
  end
end

--- org-cite-finalize-export
function M.finalize(output, info)
  local ce = info.cite_export
  if not ce then
    return output
  end
  local p = M.processors[ce[1]]
  if not p.export_finalizer then
    return output
  end
  local files = info.bibliography or {}
  return p.export_finalizer(output, M.list_keys(info), files, M.bibliography_style(info), info.back_end, info)
end

--- Transcoder for citations left in the tree: citations are replaced
--- by `process`, so this only happens when no processor applies.
function M.export_citation(el, info, backend)
  return nil
end

-- csl processor (oc-csl.el), see org.export.cite_csl
M.processors.csl = require("org.export.cite_csl")

return M
