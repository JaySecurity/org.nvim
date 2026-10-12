---@mod org.export.cite.bib Bibliography files
---
--- Reading .bib and CSL-JSON bibliography files (org-bibtex-style parsing
--- of oc-basic.el), with a cache keyed on the file's modification time.
---
--- Part of org.export.cite, which loads it.

local utils = require("org.utils")
local M = require("org.export.cite")
local shared = require("org.export.cite.shared")

local fmt = string.format

---------------------------------------------------------------------------
-- Bibliography files
---------------------------------------------------------------------------

local MONTHS = {
  jan = "January",
  feb = "February",
  mar = "March",
  apr = "April",
  may = "May",
  jun = "June",
  jul = "July",
  aug = "August",
  sep = "September",
  oct = "October",
  nov = "November",
  dec = "December",
}

--- Parse BibTeX/BibLaTeX text. Returns { [key] = entry alist-table }.
function M.parse_bibtex(content)
  local entries = {}
  local strings = {}
  for k, v in pairs(MONTHS) do
    strings[k] = v
  end
  local pos = 1
  local n = #content
  local function skip_ws()
    local ws = content:match("^[%s]*", pos)
    pos = pos + #ws
  end
  local function balanced(open, close)
    -- pos at `open`; returns inner text
    local depth = 0
    local start = pos
    while pos <= n do
      local c = content:sub(pos, pos)
      if c == "\\" then
        pos = pos + 2
      else
        if c == open then
          depth = depth + 1
        elseif c == close then
          depth = depth - 1
          if depth == 0 then
            pos = pos + 1
            return content:sub(start + 1, pos - 2)
          end
        end
        pos = pos + 1
      end
    end
    return content:sub(start + 1)
  end
  local function quoted()
    -- pos at '"'; braces protect inner quotes
    local start = pos + 1
    pos = pos + 1
    local depth = 0
    while pos <= n do
      local c = content:sub(pos, pos)
      if c == "\\" then
        pos = pos + 2
      elseif c == "{" then
        depth = depth + 1
        pos = pos + 1
      elseif c == "}" then
        depth = depth - 1
        pos = pos + 1
      elseif c == '"' and depth <= 0 then
        pos = pos + 1
        return content:sub(start, pos - 2)
      else
        pos = pos + 1
      end
    end
    return content:sub(start)
  end
  local function value()
    local parts = {}
    while true do
      skip_ws()
      local c = content:sub(pos, pos)
      if c == "{" then
        parts[#parts + 1] = balanced("{", "}")
      elseif c == '"' then
        parts[#parts + 1] = quoted()
      else
        local word = content:match("^[^%s,#}%)=]+", pos) or ""
        pos = pos + #word
        if word:match("^%d+$") then
          parts[#parts + 1] = word
        elseif word ~= "" then
          parts[#parts + 1] = strings[word:lower()] or word
        end
      end
      skip_ws()
      if content:sub(pos, pos) == "#" then
        pos = pos + 1
      else
        break
      end
    end
    return table.concat(parts)
  end
  while pos <= n do
    local at = content:find("@", pos, true)
    if not at then
      break
    end
    pos = at + 1
    local etype = content:match("^[%w_%-]+", pos)
    if not etype then
      goto continue
    end
    pos = pos + #etype
    skip_ws()
    local open = content:sub(pos, pos)
    if open ~= "{" and open ~= "(" then
      goto continue
    end
    local close = open == "{" and "}" or ")"
    local lt = etype:lower()
    if lt == "comment" or lt == "preamble" then
      balanced(open, close)
      goto continue
    end
    pos = pos + 1
    if lt == "string" then
      skip_ws()
      local name = content:match("^[^%s=]+", pos) or ""
      pos = pos + #name
      skip_ws()
      if content:sub(pos, pos) == "=" then
        pos = pos + 1
        strings[name:lower()] = value()
      end
      skip_ws()
      if content:sub(pos, pos) == close then
        pos = pos + 1
      end
      goto continue
    end
    do
      skip_ws()
      -- the key ends at a comma or, in a field-less entry, the delimiter
      local key = content:match(close == "}" and "^[^%s,}]+" or "^[^%s,)]+", pos) or ""
      pos = pos + #key
      local entry = { { "id", key }, { "type", etype } }
      while pos <= n do
        skip_ws()
        local c = content:sub(pos, pos)
        if c == "," then
          pos = pos + 1
        elseif c == close then
          pos = pos + 1
          break
        else
          local field = content:match("^[^%s=,}%)]+", pos)
          if not field then
            pos = pos + 1
          else
            pos = pos + #field
            skip_ws()
            if content:sub(pos, pos) == "=" then
              pos = pos + 1
              local v = value():gsub("[ \t\n]+", " ")
              entry[#entry + 1] = { field:lower(), v }
            end
          end
        end
      end
      if key ~= "" then
        entries[key] = entry
      end
    end
    ::continue::
  end
  return entries
end

--- Parse CSL-JSON. Returns { [key] = entry }.
function M.parse_json(content)
  local ok, items = pcall(vim.json.decode, content)
  if not ok or type(items) ~= "table" then
    error("Malformed CSL-JSON bibliography", 0)
  end
  local entries = {}
  for _, item in ipairs(items) do
    local entry = {}
    for field, v in pairs(item) do
      if field == "author" or field == "editor" then
        local names = {}
        for _, p in ipairs(v) do
          names[#names + 1] = (p.family or "") .. " " .. (p.given or "")
        end
        entry[#entry + 1] = { field, table.concat(names, " and ") }
      elseif field == "issued" then
        local date = v["date-parts"] or v.literal or v.raw
        local year
        if type(date) == "table" then
          local y = date[1] and date[1][1]
          year = type(y) == "number" and tostring(y) or y
        elseif type(date) == "string" then
          year = date:match("(%d%d%d%d)") or date
        end
        entry[#entry + 1] = { "year", year }
      else
        entry[#entry + 1] = { field, type(v) == "number" and tostring(v) or v }
      end
    end
    if item.id then
      entries[tostring(item.id)] = entry
    end
  end
  return entries
end

local file_cache = {}

--- Entries of the bibliography file `real` (an absolute name), parsed
--- again only when the file changed. Returns nil when it is unreadable.
function M.read_bibliography_file(real)
  local st = vim.uv.fs_stat(real)
  if not st then
    return nil
  end
  local cached = file_cache[real]
  local mtime = st.mtime.sec * 1e9 + st.mtime.nsec
  if not cached or cached.mtime ~= mtime or cached.size ~= st.size then
    local lines = utils.readfile(real) or {}
    local content = table.concat(lines, "\n")
    local ext = real:match("%.([^./]+)$")
    local entries
    if ext == "json" then
      entries = M.parse_json(content)
    elseif ext == "bib" or ext == "bibtex" then
      entries = M.parse_bibtex(content)
    else
      error(fmt("Unknown bibliography extension: %q", tostring(ext)), 0)
    end
    cached = { mtime = mtime, size = st.size, entries = entries }
    file_cache[real] = cached
  end
  return cached.entries
end

--- Parsed bibliography: list of { file, entries } (org-cite-basic--parse-bibliography).
function M.parse_bibliography(info)
  if info.cite_basic_bibliography then
    return info.cite_basic_bibliography
  end
  local results = {}
  for _, f in ipairs(info.bibliography or {}) do
    local path = M.bibliography_path(f, info)
    local real = utils.realpath(path) or path
    local entries = M.read_bibliography_file(real)
    if entries then
      results[#results + 1] = { real, entries }
    end
  end
  info.cite_basic_bibliography = results
  return results
end

return M
