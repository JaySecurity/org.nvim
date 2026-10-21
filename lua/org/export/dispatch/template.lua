---@mod org.export.dispatch.template The default export template
---
--- Insert the export keywords with their defaults
--- (org-export-insert-default-template).
---
--- Part of org.export, which loads it.

local utils = require("org.utils")
local shared = require("org.export.dispatch.shared")

local M = require("org.export")

local ox = shared.ox

---------------------------------------------------------------------------
-- Default template (org-export-insert-default-template)
---------------------------------------------------------------------------

local function elisp_print(v)
  if v == true then
    return "t"
  elseif v == false or v == nil then
    return "nil"
  elseif type(v) == "number" then
    return tostring(v)
  elseif type(v) == "table" then
    local parts = {}
    for _, x in ipairs(v) do
      parts[#parts + 1] = type(x) == "string" and ('"' .. x .. '"') or elisp_print(x)
    end
    return "(" .. (v.negate and ("not" .. (#parts > 0 and " " or "")) or "") .. table.concat(parts, " ") .. ")"
  end
  return tostring(v)
end
M.elisp_print = elisp_print

--- Insert the export keywords with their default values at the cursor line
--- (org-export-insert-default-template). With `subtree`, set EXPORT_*
--- properties on the current headline instead. `backend` selects the
--- option set ("default" = generic options).
---@param opts? { subtree?: boolean, backend?: string }
function M.insert_template(opts)
  opts = opts or {}
  local backend = opts.backend or "default"
  local o = ox()
  local options = {}
  if backend == "odt" then
    require("org.export.odt")
  end
  if backend ~= "default" then
    local b = o.get_backend(backend)
    if not b then
      utils.error("Unknown export back-end: " .. backend)
      return
    end
    options = o.all_options(b)
    if #options == 0 then
      options = {}
    end
    -- only the back-end's own options (org-export-backend-options)
    local own = b.options
    if type(own) == "function" then
      own = own()
    end
    options = own or {}
  else
    options = o.global_options()
  end
  local items, keywords = {}, {}
  local seen_opt, seen_kw = {}, {}
  for _, entry in ipairs(options) do
    local keyword, option = entry[2], entry[3]
    local value = entry[4]
    if type(value) == "function" then
      value = value()
    end
    if keyword then
      if not seen_kw[keyword] then
        seen_kw[keyword] = true
        if entry[5] == "split" and type(value) == "table" then
          value = table.concat(value, " ")
        end
        keywords[#keywords + 1] = { keyword, value }
      end
    elseif option then
      if not seen_opt[option] then
        seen_opt[option] = true
        items[#items + 1] = { option, value }
      end
    end
  end
  table.sort(items, function(a, b)
    return a[1] < b[1]
  end)
  local option_strings = {}
  for _, it in ipairs(items) do
    option_strings[#option_strings + 1] = it[1] .. ":" .. elisp_print(it[2])
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  local function kw_value(key, value)
    if key == "DATE" then
      return value or require("org.date").today():to_string()
    elseif key == "TITLE" then
      return value or (name ~= "" and vim.fn.fnamemodify(name, ":t:r") or vim.fn.bufname(bufnr))
    end
    if type(value) == "table" then
      return ""
    end
    return value
  end
  if opts.subtree then
    local edit = require("org.edit")
    local b, _, hl = edit.resolve_headline()
    if not hl then
      utils.warn("No subtree to set export options for")
      return
    end
    if #option_strings > 0 then
      edit.set_property(b, hl.line, "EXPORT_OPTIONS", table.concat(option_strings, " "))
    end
    for _, kv in ipairs(keywords) do
      local v = kw_value(kv[1], kv[2])
      edit.set_property(b, hl.line, "EXPORT_" .. kv[1], v ~= nil and tostring(v) or "")
    end
    return
  end
  local out = {}
  local fill = (vim.bo[bufnr].textwidth > 0 and vim.bo[bufnr].textwidth) or 70
  local i = 1
  while i <= #option_strings do
    local line = "#+options:"
    local width = 10
    while i <= #option_strings and (width + #option_strings[i] + 1) < fill do
      line = line .. " " .. option_strings[i]
      width = width + #option_strings[i] + 1
      i = i + 1
    end
    if line == "#+options:" then
      line = line .. " " .. option_strings[i]
      i = i + 1
    end
    out[#out + 1] = line
  end
  for _, kv in ipairs(keywords) do
    local v = kw_value(kv[1], kv[2])
    v = v ~= nil and tostring(v) or ""
    out[#out + 1] = "#+" .. kv[1]:lower() .. ":" .. (v:match("%S") and (" " .. v) or "")
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(bufnr, row - 1, row - 1, false, out)
  return out
end
