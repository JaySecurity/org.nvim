---@mod org.agenda.render.view Rendering a whole view
---
--- The blocks of a view one after the other, each with its options in
--- effect (the let-bound options of an Emacs custom command). Part of
--- org.agenda.render, which loads it.

-- Not compiled by the JIT, like org.agenda.render (see the comment there).
if jit then
  jit.off(true, true)
end

local config = require("org.config")
local date = require("org.date")

local M = require("org.agenda.render")

-- Block keys that are not agenda options (or are handled by the block).
local BLOCK_KEYS = {
  type = true,
  match = true,
  keywords = true,
  header = true,
  span = true,
  start_day = true,
  files = true,
  skip = true,
  filter = true,
  sorting = true,
  todo_only = true,
  stuck_projects = true,
}

-- Agenda options whose default is nil.
local NIL_OPTIONS = {
  -- a global option a block may override (org-deadline-warning-days)
  deadline_warning_days = true,
  scheduled_delay_days = true,
  start_day = true,
  format_date = true,
  hide_tags_regexp = true,
  default_appointment_duration = true,
  cmp_user_defined = true,
  max_entries = true,
  max_todos = true,
  max_tags = true,
  max_effort = true,
  overriding_columns_format = true,
  clock_report_header = true,
  auto_exclude_function = true,
  export_html_style = true,
  skip_function_global = true,
  day_face_function = true,
  diary_sexp_prefix = true,
}

--- Run `fn` with the agenda options set on `block` in effect, like the
--- let-bound options of an Emacs custom command.
function M.with_block_options(block, fn)
  local acfg = config.opts.agenda
  local defaults = config.defaults.agenda
  local saved = {}
  for k, v in pairs(block) do
    if not BLOCK_KEYS[k] and (defaults[k] ~= nil or NIL_OPTIONS[k]) then
      saved[k] = { acfg[k] }
      if type(v) == "table" and type(acfg[k]) == "table" and not vim.islist(v) and not vim.islist(acfg[k]) then
        acfg[k] = vim.tbl_deep_extend("force", acfg[k], v)
      else
        acfg[k] = v
      end
    end
  end
  local ok, err = pcall(fn)
  for k, v in pairs(saved) do
    acfg[k] = v[1]
  end
  if not ok then
    error(err, 0)
  end
end

--- Render a whole view (list of blocks).
---@param view { blocks: table[], multi?: boolean }
---@param ctx table (see agenda_block); `files_for(block)` returns files
function M.view(view, ctx)
  local b = M.builder()
  local acfg = config.opts.agenda
  local info = {}
  local multi = view.multi or #view.blocks > 1
  for i, block in ipairs(view.blocks) do
    if i > 1 and not acfg.compact_blocks and acfg.block_separator ~= false then
      local sep = acfg.block_separator or "─"
      b:text("")
      if vim.fn.strchars(sep) > 1 then
        b:text(sep, "OrgAgendaBlockSeparator")
      else
        b:text(string.rep(sep, math.max(ctx.width - 1, 10)), "OrgAgendaBlockSeparator")
      end
    end
    b.block_starts = b.block_starts or {}
    b.block_starts[#b.block_starts + 1] = #b.lines + 1
    local bctx = vim.tbl_extend("force", ctx, { files = ctx.files_for(block), multi = multi })
    bctx.filter = M.block_filter(block, ctx)
    M.with_block_options(block, function()
      if block.type == "agenda" then
        local anchor = ctx.anchor
        local align = ctx.align
        local start_day = block.start_day or acfg.start_day
        if not ctx.anchor_set and start_day then
          local sd = date.read_date(start_day)
          if sd then
            -- org-agenda-list still aligns 7 and 14 day spans
            anchor = sd:days()
          end
        end
        bctx.anchor = anchor
        bctx.align = align
        bctx.span = ctx.span_set and ctx.span or block.span or ctx.span
        info[i] = M.agenda_block(b, block, bctx)
      else
        M.list_block(b, block, bctx)
      end
    end)
  end
  b.info = info
  return b
end

return M
