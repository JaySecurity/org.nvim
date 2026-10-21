---@mod org.export.dispatch.region Converting a region in place
---
--- Replace a region by its body-only export (org-export-replace-region-by).
---
--- Part of org.export, which loads it.

local utils = require("org.utils")

local M = require("org.export")

---------------------------------------------------------------------------
-- Convert region in place (org-export-replace-region-by)
---------------------------------------------------------------------------

--- Replace the selected Org text by its body-only export
--- (org-html-convert-region-to-html, org-latex-convert-region-to-latex,
--- org-md-convert-region-to-md, org-ascii-convert-region-to-ascii / -utf8,
--- org-texinfo-convert-region-to-texinfo and their org-export-region-to-*
--- aliases). The region is exported on its own, like a temporary Org
--- buffer. `range` = { line1, line2 } (linewise, from `:[range]`),
--- otherwise the Visual selection.
---@param format string html|latex|md|ascii|utf8|texinfo|...
---@param range? integer[]
function M.convert_region(format, range)
  local bufnr = vim.api.nvim_get_current_buf()
  local srow, scol, erow, ecol, mode
  if range then
    srow, erow, mode = range[1], range[2], "V"
  else
    local m = vim.fn.mode()
    if m ~= "v" and m ~= "V" and m ~= "\22" then
      utils.warn("No active region to replace")
      return false
    end
    srow, scol, erow, ecol, mode = utils.visual_range()
    utils.exit_visual()
  end
  if mode == "v" then
    local last = vim.api.nvim_buf_get_lines(bufnr, erow - 1, erow, false)[1] or ""
    local erow0, ecol0, eol = erow - 1, nil, false
    if ecol > #last then
      -- `v$`: the selection takes the end of the line too
      eol = true
      if erow < vim.api.nvim_buf_line_count(bufnr) then
        erow0, ecol0 = erow, 0
      else
        ecol0 = #last
      end
    else
      -- the end column is inclusive and points at the start of a (multibyte) character
      ecol0 = utils.char_end(last, ecol)
    end
    local parts = vim.api.nvim_buf_get_text(bufnr, srow - 1, scol - 1, erow0, ecol0, {})
    if eol and parts[#parts] == "" then
      parts[#parts] = nil
    end
    local out = M.to_string(format, {
      lines = parts,
      body_only = true,
      -- like the buffer text Emacs exports, the last line has no newline
      no_final_newline = not eol,
    })
    vim.api.nvim_buf_set_text(bufnr, srow - 1, scol - 1, erow0, ecol0, vim.split(out, "\n", { plain = true }))
  else
    local lines = vim.api.nvim_buf_get_lines(bufnr, srow - 1, erow, false)
    local out = M.to_string(format, { lines = lines, body_only = true })
    local new = out == "" and {} or vim.split((out:gsub("\n$", "")), "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, srow - 1, erow, false, new)
  end
  return true
end

for _, f in ipairs({ "html", "latex", "md", "ascii", "utf8", "texinfo" }) do
  M["convert_region_to_" .. f] = function()
    return M.convert_region(f)
  end
  M["export_region_to_" .. f] = function(_, opts)
    return M.convert_region_command(f, opts)
  end
end

--- :[range]Org convert_region {format} (the `org-export-region-to-*`
--- commands); without a range, the last Visual selection.
function M.convert_region_command(args, opts)
  local format = vim.trim(args or "")
  if format == "" then
    utils.warn("Usage: :[range]Org convert_region html|latex|md|ascii|utf8|texinfo|...")
    return
  end
  if not M.FORMATS[format] then
    utils.error("Unknown export format: " .. format)
    return
  end
  local range
  if opts and opts.range and opts.range > 0 then
    range = { opts.line1, opts.line2 }
  else
    local s, e = vim.fn.line("'<"), vim.fn.line("'>")
    if s == 0 or e == 0 then
      utils.warn("No active region to replace")
      return
    end
    range = { s, e }
  end
  return M.convert_region(format, range)
end
