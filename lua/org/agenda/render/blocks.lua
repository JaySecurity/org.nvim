---@mod org.agenda.render.blocks What agenda and list blocks share
---
--- The sorting strategy of a block, its item filters and its header
--- (org-agenda--insert-overriding-header). Part of org.agenda.render,
--- which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

--- The sorting strategy of a block type.
local function sorting_for(block, kind)
  local acfg = config.opts.agenda
  local s = block.sorting or acfg.sorting
  if type(s) == "table" and not vim.islist(s) then
    s = s[kind] or s.agenda
  end
  if type(s) == "table" and vim.islist(s) and #s > 0 then
    return s
  end
  local defaults = {
    agenda = { "habit-down", "time-up", "urgency-down", "category-keep" },
    todo = { "urgency-down", "category-keep" },
    tags = { "urgency-down", "category-keep" },
    search = { "category-keep" },
  }
  return defaults[kind] or { "time-up", "category-keep", "urgency-down" }
end
M.sorting_for = sorting_for

--- The item predicate of a block: the runtime filters (`ctx.filter`) and
--- the block's own `filter(item)`, which is given the item as
--- |org-api-agenda| shapes it and returns true to keep it. A `filter`
--- that errors keeps the item, like a failing `skip`.
---@param block table
---@param ctx table
---@return (fun(it: table): boolean)|nil
function M.block_filter(block, ctx)
  local own, base = block.filter, ctx.filter
  if type(own) ~= "function" then
    return base
  end
  local to_api = require("org.api.agenda")._item
  return function(it)
    if base and not base(it) then
      return false
    end
    local ok, keep = pcall(own, to_api(it))
    return not ok or keep and true or false
  end
end

local function filter_list(list, ctx)
  if not ctx.filter then
    return list
  end
  local out = {}
  for _, it in ipairs(list) do
    if ctx.filter(it) then
      out[#out + 1] = it
    end
  end
  return out
end

--- Insert a block header (org-agenda--insert-overriding-header): a
--- string, "" for none, or a function returning the header.
local function insert_header(b, block, default)
  local h = block.header
  if h == nil then
    for _, l in ipairs(type(default) == "table" and default or { default }) do
      if type(l) == "table" then
        b:add(l)
      else
        b:text(l, "OrgAgendaHeader")
      end
    end
  elseif h == "" then
    return
  elseif type(h) == "function" then
    local s = h()
    for _, l in ipairs(vim.split(tostring(s or ""), "\n", { trimempty = true })) do
      b:text(l, "OrgAgendaHeader")
    end
  else
    for _, l in ipairs(vim.split(tostring(h), "\n", { trimempty = true })) do
      b:text(l, "OrgAgendaHeader")
    end
  end
end

shared.sorting_for = sorting_for
shared.filter_list = filter_list
shared.insert_header = insert_header

return M
