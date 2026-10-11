---@mod org.extensions.transclusion.save Saving and exporting without the inserted text
---
--- Inserted text never reaches the file: it is taken out before a write
--- and put back after it (`without_inserted` for writes that skip
--- autocommands, `heal` after a `:noautocmd w`), and an export expands the
--- keywords instead of exporting it twice. Part of
--- org.extensions.transclusion, which loads it.

local keyword = require("org.extensions.transclusion.keyword")
local shared = require("org.extensions.transclusion.shared")
local source = require("org.extensions.transclusion.source")
local utils = require("org.utils")

local M = require("org.extensions.transclusion")

local api = vim.api
local ns_region = M.ns_region
local opts = shared.opts
local valid = shared.valid
local touch = shared.touch
local keep_modified = shared.keep_modified
local undojoin = shared.undojoin
local mark_lines = shared.mark_lines
local gc_marks = shared.gc_marks
local collect = shared.collect
local owned_rows = shared.owned_rows
local delete_rows = shared.delete_rows
local protect = shared.protect
local adopt_gone = shared.adopt_gone

local after_write

-- Take the inserted text out before `buf` is written (all of it, or the
-- part in lines l1..l2 of a partial write).
local function before_write(buf, l1, l2)
  local st = M.buffers[buf]
  if not st or st.saving or not next(st.regions) or not valid(buf) then
    return
  end
  protect(buf)
  adopt_gone(buf)
  local list = collect(buf)
  local saving = { ids = {}, views = {} }
  for _, w in ipairs(vim.fn.win_findbuf(buf)) do
    saving.views[w] = api.nvim_win_call(w, vim.fn.winsaveview)
  end
  keep_modified(buf, function()
    -- every marked line goes, the text of deleted keywords too
    for i = #list, 1, -1 do
      local r = list[i]
      local rows = {}
      for _, row in ipairs(owned_rows(r)) do
        if not st.cache.anchors[row] and (not l1 or (row >= l1 - 1 and row <= l2 - 1)) then
          rows[#rows + 1] = row
        end
      end
      if #rows > 0 then
        delete_rows(buf, rows)
        if not r.gone then
          saving.ids[#saving.ids + 1] = r.id
        end
      end
    end
  end)
  touch(st)
  st.saving = saving
  st.mtime = nil
  -- A write that fails (or is stopped by another autocommand) has no
  -- BufWritePost: put the text back once the write command is over. A
  -- callback can run while autocommands still run (vim.wait in a
  -- formatter): wait until none does.
  local function fallback()
    if M.buffers[buf] ~= st or st.saving ~= saving then
      return
    end
    if vim.fn.state():find("x") then
      vim.defer_fn(fallback, 20)
      return
    end
    after_write(buf)
  end
  vim.schedule(fallback)
end

after_write = function(buf)
  local st = M.buffers[buf]
  if not st or not st.saving or not valid(buf) then
    return
  end
  local saving = st.saving
  st.saving = nil
  local list = collect(buf)
  local left = {}
  for _, r in ipairs(list) do
    left[r.id] = r
  end
  local items = {}
  for _, aid in ipairs(saving.ids) do
    local m = api.nvim_buf_get_extmark_by_id(buf, ns_region, aid, { details = true })
    local data = st.regions[aid]
    if m[1] and not (m[3] and m[3].invalid) and data then
      items[#items + 1] = { row = m[1], id = aid, data = data }
    end
  end
  table.sort(items, function(x, y)
    return x.row > y.row
  end)
  keep_modified(buf, function()
    for _, it in ipairs(items) do
      local kw = api.nvim_buf_get_lines(buf, it.row, it.row + 1, false)[1]
      if kw and keyword.match(kw) then
        -- joined to the removal, so undo doesn't see the save
        undojoin(buf)
        if left[it.id] then
          -- what a partial write left
          delete_rows(buf, owned_rows(left[it.id]))
        end
        api.nvim_buf_set_lines(buf, it.row + 1, it.row + 1, false, it.data.lines)
        mark_lines(buf, it.id, it.row + 1, #it.data.lines)
        gc_marks(buf, it.id)
      end
    end
  end)
  touch(st)
  for w, view in pairs(saving.views) do
    if api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == buf then
      api.nvim_win_call(w, function()
        vim.fn.winrestview(view)
      end)
    end
  end
  local name = api.nvim_buf_get_name(buf)
  st.mtime = name ~= "" and source.stamp(name) or nil
  M.render(buf)
end

--- Run `fn` (a write of `buf`) with the inserted text taken out, and put
--- it back afterwards. For writes that skip autocommands, like
--- `utils.save_buffer`'s `:noautocmd write`.
---@param buf integer
---@param fn function
function M.without_inserted(buf, fn)
  local st = M.buffers[buf]
  if not st or st.saving or not next(st.regions) then
    return fn()
  end
  before_write(buf)
  local ok, a1, a2 = pcall(fn)
  after_write(buf)
  if not ok then
    error(a1, 0)
  end
  return a1, a2
end

--- After a write that skipped autocommands (`:noautocmd w`), the file
--- holds the inserted text: take it out of the file again.
local function heal(buf)
  local st = M.buffers[buf]
  if not st or st.saving or not next(st.regions) or not valid(buf) or vim.bo[buf].modified then
    return
  end
  local name = api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" then
    return
  end
  local mt = source.stamp(name)
  if not mt or mt == st.mtime then
    return
  end
  st.mtime = mt
  local _, map = M.clean_lines(buf)
  if not map then
    return
  end
  local disk = utils.readfile(name)
  if disk and vim.deep_equal(disk, api.nvim_buf_get_lines(buf, 0, -1, false)) then
    -- written again by Vim, so it knows the file it wrote (no "changed
    -- since editing started" warning); autocommands don't nest, so the
    -- text is taken out here
    local ok = pcall(M.without_inserted, buf, function()
      api.nvim_buf_call(buf, function()
        vim.cmd("silent keepalt write")
      end)
    end)
    if ok then
      utils.warn("transclusion: the file was written without autocommands; its inserted text was taken out again")
    end
  end
end

M.heal = heal

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

--- Expand `#+transclude:` keywords of exported lines (an
--- `org.export.hooks` preprocessor). Text inserted in the exported buffer
--- is replaced, not doubled.
---@param lines string[]
---@param ctx table { dir, filename, bufnr }
---@return string[]
function M.export_preprocess(lines, ctx)
  if not opts().export then
    return lines
  end
  local regs = ctx.bufnr and valid(ctx.bufnr) and M.regions(ctx.bufnr) or {}
  local skip
  if #regs > 0 and vim.deep_equal(lines, api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)) then
    lines = M.clean_lines(ctx.bufnr)
  elseif #regs > 0 then
    local inserted = {}
    for _, r in ipairs(regs) do
      inserted[#inserted + 1] = r.data.lines
    end
    skip = function(kw, all)
      for _, ins in ipairs(inserted) do
        if vim.deep_equal(vim.list_slice(all, kw.row + 1, kw.row + #ins), ins) then
          return #ins
        end
      end
      return 0
    end
  end
  local out, errors = source.frame(source.expand, lines, {
    dir = ctx.dir,
    filename = ctx.filename,
    bufnr = ctx.bufnr,
  }, skip)
  for _, e in ipairs(errors) do
    utils.warn("transclusion: " .. tostring(e))
  end
  return out
end

shared.before_write = before_write
shared.after_write = after_write
shared.heal = heal
