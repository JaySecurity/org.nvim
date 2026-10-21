---@mod org.agenda.render.list List blocks
---
--- The TODO, tags, search and stuck project blocks and the extra block
--- types of `M.sources`, with their headers and hints. Part of
--- org.agenda.render, which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local items_mod = require("org.agenda.items")
local utils = require("org.utils")
local shared = require("org.agenda.render.shared")

local M = require("org.agenda.render")

local filter_list = shared.filter_list
local insert_header = shared.insert_header
local sorting_for = shared.sorting_for

--- The key of an agenda mapping for hints (first lhs).
local function key_of(name, default)
  local maps = (config.opts.mappings or {}).agenda or {}
  local lhs = config.lhs_list(maps[name])[1]
  return lhs or default
end

--- Wrap `words` after `start` so lines fit `width` (the TODO list hint).
local function wrapped_hint(start, words, width)
  local lines = {}
  local cur = start
  for _, w in ipairs(words) do
    if utils.width(cur) + utils.width(w) + 1 > width and cur ~= start then
      lines[#lines + 1] = cur
      cur = string.rep(" ", 21)
    end
    cur = cur .. " " .. w
  end
  lines[#lines + 1] = cur
  return lines
end

--- Render a list block (todo / tags / search / stuck).
function M.list_block(b, block, ctx)
  local t = block.type
  local list, sorting
  local kind
  local header
  local lopts = { restrict = ctx.restrict, skip = block.skip, block = block, archives = ctx.archives }
  local presorted = false
  local redo = key_of("redo", "r")
  if t == "todo" then
    kind = "todo"
    local kws = block.keywords
    if type(kws) == "string" then
      kws = vim.split(kws, "[|%s]+", { trimempty = true })
    end
    if not kws and block.match and block.match ~= "" then
      kws = vim.split(block.match, "[|%s]+", { trimempty = true })
    end
    list = items_mod.todo(ctx.files, kws, lopts)
    local sel = (kws and #kws > 0) and table.concat(kws, "|") or "ALL"
    header = { { { "Global list of TODO items of type: ", "OrgAgendaHeader" }, { sel, "OrgAgendaFilter" } } }
    if not ctx.multi then
      local words = { "(0)[ALL]" }
      for i, n in ipairs(ctx.todo_names or {}) do
        words[#words + 1] = string.format("(%d)%s", i, n)
      end
      local start = string.format("Press ‘N %s’ (e.g. ‘0 %s’) to search again:", redo, redo)
      for _, l in ipairs(wrapped_hint(start, words, ctx.width)) do
        header[#header + 1] = { { l, "OrgAgendaHint" } }
      end
    end
  elseif t == "tags" or t == "tags_todo" then
    kind = "tags"
    local pred, err = require("org.agenda.search").try_compile(block.match or "")
    if not pred then
      b:text("Invalid match: " .. tostring(err), "ErrorMsg")
      return
    end
    list = items_mod.tags(ctx.files, pred, t == "tags_todo", lopts)
    header = { { { "Headlines with TAGS match: ", "OrgAgendaHeader" }, { block.match or "", "OrgAgendaFilter" } } }
    if not ctx.multi then
      header[#header + 1] = { { string.format("Press ‘1 %s’ to search again", redo), "OrgAgendaHint" } }
    end
  elseif t == "search" then
    kind = "search"
    local query = (block.todo_only and "!" or "") .. (block.match or "")
    local pred = require("org.agenda.search").compile_text(query, block)
    list = items_mod.search(ctx.files, pred, lopts)
    header = { { { "Search words: ", "OrgAgendaHeader" }, { block.match or "", "OrgAgendaFilter" } } }
    if not ctx.multi then
      header[#header + 1] = {
        {
          string.format(
            "Press ‘%s’, ‘%s’ to add/sub word, ‘%s’, ‘%s’ to add/sub regexp, ‘1 %s’ for a fresh search",
            key_of("query_add", "["),
            key_of("query_subtract", "]"),
            key_of("query_add_re", "{"),
            key_of("query_subtract_re", "}"),
            redo
          ),
          "OrgAgendaHint",
        },
      }
    end
  elseif t == "stuck" then
    kind = "tags"
    local ok, res = pcall(items_mod.stuck, ctx.files, lopts)
    if not ok then
      b:text(tostring(res), "ErrorMsg")
      return
    end
    list = res
    header = "List of stuck projects: "
  elseif M.sources[t] then
    local ok, res = pcall(M.sources[t], block, ctx, lopts)
    if not ok or res.error then
      b:text(tostring(ok and res.error or res), "ErrorMsg")
      return
    end
    list, kind, header, presorted = res.items, res.kind or "tags", res.header, res.sorted and not block.sorting
  else
    b:text("Unknown agenda block type: " .. tostring(t), "ErrorMsg")
    return
  end
  sorting = sorting_for(block, kind)
  insert_header(b, block, header)
  list = filter_list(list, ctx)
  if kind == "todo" or kind == "tags" then
    local ts_kind = items_mod.list_timestamp_kind(sorting) or false
    for _, it in ipairs(list) do
      items_mod.set_list_timestamp(it, sorting, ts_kind)
    end
  end
  if not presorted then
    items_mod.sort(list, sorting)
  end
  list = M.apply_limits(list, kind, ctx)
  local lctx = vim.tbl_extend("force", ctx, { kind = kind, block = block })
  local function add(it)
    it.level_str = string.rep(" ", it.level or 0)
    M.add_item(b, it, lctx)
  end
  if M.grouper and M.grouper(b, list, block, lctx, add) then
    return
  end
  for _, it in ipairs(list) do
    add(it)
  end
end

return M
