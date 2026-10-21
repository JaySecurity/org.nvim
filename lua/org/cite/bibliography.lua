---@mod org.cite.bibliography Bibliography of a buffer
---
--- The bibliography files of a buffer (org-cite-list-bibliography-files),
--- reading them, and the basic processor's key and entry helpers
--- (oc-basic.el). Part of org.cite, which loads it.

local utils = require("org.utils")
local shared = require("org.cite.shared")

local M = require("org.cite")
local basic = M.basic
local opt = shared.opt

local function strip_quotes(s)
  return (s:gsub('^%s*"(.*)"%s*$', "%1"))
end

local function absolute(f, dir)
  f = utils.expand_vars(f)
  if f:match("^/") or f:match("^%a:[/\\]") then
    return vim.fs.normalize(f)
  end
  return vim.fs.normalize(dir .. "/" .. f)
end

--- Absolute names of the bibliography files of the buffer: its
--- #+BIBLIOGRAPHY keywords (setup files included) and
--- `export.cite.global_bibliography`.
function M.bibliography_files(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local dir = name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
  local out, seen = {}, {}
  local function add(f)
    if f and not seen[f] then
      seen[f] = true
      out[#out + 1] = f
    end
  end
  local ok, file = pcall(require("org.files").get_buffer, bufnr)
  if ok and file then
    for _, e in ipairs(file.settings.keyword_entries or {}) do
      if e.key == "BIBLIOGRAPHY" and e.value ~= "" then
        local base = dir
        if e.filename and e.filename ~= "" and e.filename ~= name then
          base = vim.fn.fnamemodify(e.filename, ":p:h")
        end
        add(absolute(strip_quotes(e.value), base))
      end
    end
  end
  for _, f in ipairs(opt("global_bibliography", {})) do
    add(absolute(f, dir))
  end
  return out
end

--- org-cite-basic--parse-bibliography outside export: a list of
--- { file, entries }, last file first (like Emacs); unreadable or
--- malformed files are skipped.
function M.parse_bibliography(bufnr)
  local cite = require("org.export.cite")
  local results = {}
  for _, f in ipairs(M.bibliography_files(bufnr)) do
    local real = utils.realpath(f) or f
    local ok, entries = pcall(cite.read_bibliography_file, real)
    if ok and entries then
      table.insert(results, 1, { real, entries })
    end
  end
  return results
end

--- org-cite-basic--all-keys
function basic.all_keys(bib)
  local keys, seen = {}, {}
  for _, f in ipairs(bib) do
    local ks = vim.tbl_keys(f[2])
    table.sort(ks)
    for _, k in ipairs(ks) do
      if not seen[k] then
        seen[k] = true
        keys[#keys + 1] = k
      end
    end
  end
  return keys
end

--- org-cite-basic--get-entry
function basic.get_entry(bib, key)
  for _, f in ipairs(bib) do
    if f[2][key] then
      return f[2][key], f[1]
    end
  end
end

local function field(entry, name)
  for _, kv in ipairs(entry or {}) do
    if kv[1] == name then
      if kv[2] ~= nil and type(kv[2]) ~= "string" then
        error(string.format("Non-string bibliography field value: %s", vim.inspect(kv[2])), 0)
      end
      return kv[2]
    end
  end
end
basic.field = field

--- Year of an entry without disambiguation suffix (org-cite-basic--get-year).
function basic.year(entry)
  local year = field(entry, "year")
  if not year then
    local date = field(entry, "date")
    if type(date) == "string" then
      year = date:match("^(%d%d%d%d)%f[%D]") or date:match("^(%d%d%d%d)$")
    end
  end
  return year
end

--- truncate-string-to-width STR WIDTH nil ?\s
local function fit(s, width)
  local out, w = {}, 0
  for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
    local cw = vim.fn.strdisplaywidth(ch)
    if w + cw > width then
      break
    end
    out[#out + 1] = ch
    w = w + cw
  end
  return table.concat(out) .. string.rep(" ", width - w)
end

--- org-cite-basic--key-completion-table: { { display, key }... } sorted
--- by display string, or nil when the bibliography has no entry.
function basic.completion_table(bib)
  local width = opt("basic_author_column_end", 25)
  local sep = opt("basic_column_separator", "  ")
  local map, displays = {}, {}
  for _, f in ipairs(bib) do
    for key, entry in pairs(f[2]) do
      local author = field(entry, "author") or field(entry, "editor")
      local d = (author and fit((author:gsub(" and ", "; ")), width) or string.rep(" ", width))
        .. sep
        .. string.format("%4s", basic.year(entry) or "")
        .. sep
        .. (field(entry, "title") or "")
      if map[d] == nil then
        displays[#displays + 1] = d
      end
      map[d] = key
    end
  end
  if #displays == 0 then
    return nil
  end
  table.sort(displays)
  local out = {}
  for i, d in ipairs(displays) do
    out[i] = { d, map[d] }
  end
  return out
end

--- Levenshtein distance (org-string-distance).
function M.string_distance(a, b)
  local la, lb = vim.fn.strchars(a), vim.fn.strchars(b)
  if la == 0 then
    return lb
  elseif lb == 0 then
    return la
  end
  local ca, cb = vim.fn.split(a, "\\zs"), vim.fn.split(b, "\\zs")
  local prev = {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    local cur = { [0] = i }
    for j = 1, lb do
      local cost = ca[i] == cb[j] and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[lb]
end

--- org-cite-basic--close-keys
function basic.close_keys(key, keys)
  local max = opt("basic_max_key_distance", 2)
  local out = {}
  for _, k in ipairs(keys) do
    if M.string_distance(k, key) <= max then
      out[#out + 1] = k
    end
  end
  return out
end
