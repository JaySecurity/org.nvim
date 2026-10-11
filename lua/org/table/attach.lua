---@mod org.table.attach Per-buffer table setup
---
--- What `org.buffer` sets up for tables in every org buffer, kept out of
--- org.table so that opening a file doesn't load the table editor: it
--- loads when a table is aligned, typed into or edited.

local M = {}

local function is_table_line(line)
  return line ~= nil and line:match("^%s*|") ~= nil
end

--- `table_header_line_p`, `#+STARTUP: align / shrink`, typing into fields
--- and realigning on InsertLeave (`table_automatic_realign`).
---@param bufnr integer
function M.attach(bufnr)
  local config = require("org.config").opts
  if config.table_header_line_p then
    require("org.table.follow").header_line_mode(bufnr, true)
  end
  local startup = require("org.files").get_buffer(bufnr).settings.startup or {}
  -- #+STARTUP: align / noalign (org-startup-align-all-tables)
  local align = startup.align or (config.startup_align_all_tables and not startup.noalign)
  local shrink = startup.shrink or (config.startup_shrink_all_tables and not startup.noshrink)
  if align or shrink then
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        if align then
          require("org.table").align_all(bufnr)
        end
        if shrink then
          require("org.table.shrink").shrink_all(bufnr)
        end
      end
    end)
  end
  require("org.table.typing").attach(bufnr)
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = bufnr,
    group = vim.api.nvim_create_augroup("org.table." .. bufnr, { clear = true }),
    callback = function()
      if vim.api.nvim_get_current_buf() ~= bufnr then
        return
      end
      if require("org.config").opts.table_automatic_realign == false then
        return
      end
      local line = vim.api.nvim_get_current_line()
      if is_table_line(line) then
        local tbl = require("org.table")
        local info = tbl.at_cursor()
        if info and not vim.deep_equal(tbl.render(info.tbl), info.lines) then
          tbl.align()
        end
      end
    end,
  })
end

return M
