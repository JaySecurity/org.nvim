---@mod org.export.cite.basic The basic citation processor
---
--- Port of oc-basic.el: author-year and numeric citations and the
--- bibliography, for every back-end.
---
--- Part of org.export.cite, which loads it.

local ox = require("org.export.ox")
local M = require("org.export.cite")
local shared = require("org.export.cite.shared")

local fmt = string.format
local opt, stable_sort = shared.opt, shared.stable_sort
local raw = M.raw

---------------------------------------------------------------------------
-- basic processor (oc-basic.el)
---------------------------------------------------------------------------

local basic = {}

local function latex_p(info)
  return ox.derived_backend_p(info.back_end, "latex")
end

function basic.get_entry(key, info)
  for _, f in ipairs(M.parse_bibliography(info)) do
    local e = f[2][key]
    if e then
      return e
    end
  end
end

local function assq(entry, field)
  for _, kv in ipairs(entry) do
    if kv[1] == field then
      return kv[2]
    end
  end
end

--- Field value: a string, a raw string (LaTeX back-ends) or nil.
function basic.get_field(field, entry_or_key, info, want_raw)
  local entry = entry_or_key
  if type(entry_or_key) == "string" then
    entry = basic.get_entry(entry_or_key, info)
  end
  local value = entry and assq(entry, field)
  if value ~= nil and type(value) ~= "string" then
    error(fmt("Non-string bibliography field value: %s", vim.inspect(value)), 0)
  end
  if value and not want_raw and latex_p(info) then
    return raw(value)
  end
  return value
end

function basic.shorten_names(names)
  local s, is_raw
  if type(names) == "string" then
    s = names
  elseif names and names.type == "raw" then
    s = names.value
    is_raw = true
  end
  if not s then
    return nil
  end
  local out = {}
  for _, name in ipairs(vim.split(s, " and ", { plain = true })) do
    if #name == 1 then
      out[#out + 1] = ""
    else
      out[#out + 1] = vim.split(name, ", ", { plain = true })[1]
    end
  end
  local r = table.concat(out, ", ")
  return is_raw and raw(r) or r
end

function basic.number_to_suffix(n)
  local result = {}
  while true do
    table.insert(result, 1, n % 26)
    n = math.floor(n / 26)
    if n == 0 then
      break
    elseif n < 27 then
      table.insert(result, 1, n - 1)
      break
    elseif n == 27 then
      table.insert(result, 1, 0)
      table.insert(result, 1, 0)
      break
    end
  end
  local chars = {}
  for i, x in ipairs(result) do
    chars[i] = string.char(97 + x)
  end
  return table.concat(chars)
end

function basic.get_author(entry_or_key, info, want_raw)
  return basic.get_field("author", entry_or_key, info, want_raw)
    or basic.get_field("editor", entry_or_key, info, want_raw)
end

function basic.get_year(entry_or_key, info, no_suffix)
  local author = basic.get_author(entry_or_key, info, true)
  local year = basic.get_field("year", entry_or_key, info, true)
  if not year then
    local date = basic.get_field("date", entry_or_key, info, true)
    if type(date) == "string" then
      year = date:match("^(%d%d%d%d)%f[%D]") or date:match("^(%d%d%d%d)$")
    end
  end
  local key = type(entry_or_key) == "string" and entry_or_key or assq(entry_or_key, "id")
  info.cite_basic_author_date_cache = info.cite_basic_author_date_cache or {}
  local cache = info.cite_basic_author_date_cache
  local ck = tostring(author) .. "\0" .. tostring(year)
  local hit = cache[ck]
  if not hit then
    -- the alist only ever holds the first key (like Emacs)
    cache[ck] = { { key, "" } }
    return year
  end
  local suffix
  for _, kv in ipairs(hit) do
    if kv[1] == key then
      suffix = kv[2]
    end
  end
  suffix = suffix or basic.number_to_suffix(#hit - 1)
  if no_suffix then
    return year
  end
  return (year or "") .. suffix
end

--- Parse LaTeX fragments and entities in strings nested in objects, then
--- drop remaining braces (org-cite-basic--print-bibtex-string).
function basic.print_bibtex_string(data, info)
  if latex_p(info) then
    return data
  end
  local R = { ["latex-fragment"] = true, entity = true }
  local function walk(list, nested)
    local i = 1
    while i <= #list do
      local x = list[i]
      if x.type == "plain-text" and nested then
        local parsed = info.parser:parse_objects(x.value, R, x.parent)
        for _, p in ipairs(parsed) do
          p.parent = x.parent
          if p.type == "plain-text" then
            p.value = p.value:gsub("[{}]", "")
          end
        end
        table.remove(list, i)
        for k, p in ipairs(parsed) do
          table.insert(list, i + k - 1, p)
        end
        i = i + #parsed
      else
        if x.type ~= "plain-text" and x.contents then
          walk(x.contents, true)
        end
        i = i + 1
      end
    end
  end
  walk(data, false)
  return data
end

function basic.key_number(key, info)
  return M.key_number(key, info, basic.field_less_p(opt("basic_sorting_field", "author"), info))
end

function basic.print_entry(entry, style, info)
  local author = basic.get_author(entry, info)
  local title = basic.get_field("title", entry, info)
  local from = basic.get_field("publisher", entry, info)
    or basic.get_field("journal", entry, info)
    or basic.get_field("institution", entry, info)
    or basic.get_field("school", entry, info)
  local data
  if style == "plain" then
    local year = basic.get_year(entry, info, true)
    data = M.concat(basic.shorten_names(author), ". ", title, from and M.concat(", ", from), ", ", year, ".")
  elseif style == "numeric" then
    local n = basic.key_number(assq(entry, "id"), info)
    local year = basic.get_year(entry, info, true)
    data = M.concat(
      fmt("[%d] ", n),
      author,
      ", ",
      M.emphasize("italic", title),
      from and M.concat(", ", from),
      ", ",
      year,
      "."
    )
  else
    local year = basic.get_year(entry, info)
    data = M.concat(author, " (", year, "). ", M.emphasize("italic", title), from and M.concat(", ", from), ".")
  end
  return basic.print_bibtex_string(data, info)
end

function basic.format_author_year(citation, format_cite, format_ref, info)
  return ox.data(
    format_cite(
      citation.prefix,
      M.mapconcat(function(ref)
        local k = ref.key
        return format_ref(ref.prefix, basic.get_author(k, info) or "??", basic.get_year(k, info) or "????", ref.suffix)
      end, M.get_references(citation), opt("basic_author_year_separator", ", ")),
      citation.suffix
    ),
    info
  )
end

function basic.citation_numbers(citation, info)
  local numbers = {}
  for _, k in ipairs(M.get_references(citation, true)) do
    numbers[#numbers + 1] = basic.key_number(k, info)
  end
  table.sort(numbers)
  local last = table.remove(numbers, 1)
  local result = { tostring(last) }
  while #numbers > 0 do
    local current = table.remove(numbers, 1)
    local nxt = numbers[1]
    if nxt and current == last + 1 and current == nxt - 1 then
      if result[#result] ~= "-" then
        result[#result + 1] = "-"
      end
    elseif result[#result] == "-" then
      result[#result + 1] = tostring(current)
    else
      result[#result + 1] = fmt(", %d", current)
    end
    last = current
  end
  return table.concat(result)
end

function basic.field_less_p(field, info)
  if not field then
    return nil
  end
  return function(a, b)
    local x = basic.get_field(field, a, info, true) or "nil"
    local y = basic.get_field(field, b, info, true) or "nil"
    return x:lower() < y:lower()
  end
end

function basic.export_citation(citation, style, _, info)
  local name, variant = style[1], style[2]
  local function has_variant(t)
    if t == "bare" then
      return variant == "bare" or variant == "bare-caps" or variant == "b" or variant == "bc"
    end
    return variant == "caps" or variant == "bare-caps" or variant == "c" or variant == "bc"
  end
  if name == "author" or name == "a" then
    local caps = variant == "caps" or variant == "c"
    return basic.format_author_year(citation, function(p, c, s)
      return M.concat(p, c, s)
    end, function(prefix, author, _, suffix)
      return M.concat(prefix, caps and M.capitalize(author) or author, suffix)
    end, info)
  elseif name == "noauthor" or name == "na" then
    local bare = has_variant("bare")
    return basic.format_author_year(citation, function(prefix, contents, suffix)
      return M.concat(not bare and "(" or nil, prefix, contents, suffix, not bare and ")" or nil)
    end, function(prefix, _, year, suffix)
      return M.concat(prefix, year, suffix)
    end, info)
  elseif name == "nocite" or name == "n" then
    return nil
  elseif name == "text" or name == "note" or name == "t" or name == "ft" then
    if (name == "note" or name == "ft") and not M.inside_footnote_p(citation) then
      M.adjust_note(citation, info)
      M.wrap_citation(citation, info)
    end
    local bare, caps = has_variant("bare"), has_variant("caps")
    return basic.format_author_year(citation, function(p, c, s)
      return M.concat(p, c, s)
    end, function(p, a, y, s)
      return M.concat(p, caps and M.capitalize(a) or a, bare and " " or " (", y, not bare and ")" or nil, s)
    end, info)
  elseif name == "numeric" or name == "nb" then
    local prefix, suffix = M.main_affixes(citation)
    return ox.data(M.concat("(", prefix, basic.citation_numbers(citation, info), suffix, ")"), info)
  end
  local bare, caps = has_variant("bare"), has_variant("caps")
  return basic.format_author_year(citation, function(p, c, s)
    return M.concat(not bare and "(" or nil, p, c, s, not bare and ")" or nil)
  end, function(p, a, y, s)
    return M.concat(p, caps and M.capitalize(a) or a, ", ", y, s)
  end, info)
end

function basic.export_bibliography(keys, _, style, _, backend, info)
  local entries = {}
  local sorted = keys
  local pred = basic.field_less_p(opt("basic_sorting_field", "author"), info)
  if pred then
    sorted = stable_sort(keys, pred)
  end
  for _, k in ipairs(sorted) do
    local e = basic.get_entry(k, info)
    if e then
      entries[#entries + 1] = e
    end
  end
  local out = {}
  for _, entry in ipairs(entries) do
    out[#out + 1] = ox.data(
      M.make_paragraph(
        ox.derived_backend_p(backend, "latex") and raw("\\noindent\n") or nil,
        basic.print_entry(entry, style, info)
      ),
      info
    )
  end
  return table.concat(out, "\n")
end

M.basic = basic
M.processors.basic = {
  export_citation = basic.export_citation,
  export_bibliography = basic.export_bibliography,
  -- { { style, shortcuts... }, { variant, shortcuts... }... } (:cite-styles)
  cite_styles = {
    { { "author", "a" }, { "caps", "c" } },
    { { "noauthor", "na" }, { "bare", "b" } },
    { { "nocite", "n" } },
    { { "note", "ft" }, { "bare-caps", "bc" }, { "caps", "c" } },
    { { "numeric", "nb" } },
    { { "text", "t" }, { "bare-caps", "bc" }, { "caps", "c" } },
    { { "nil" }, { "bare", "b" }, { "bare-caps", "bc" }, { "caps", "c" } },
  },
}

return M
