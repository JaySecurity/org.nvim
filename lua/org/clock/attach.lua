---@mod org.clock.attach Per-buffer clock setup
---
--- What `org.buffer` sets up for the clock in every org buffer, kept out
--- of org.clock so that opening a file doesn't load it: it loads with the
--- first clock command.

local M = {}

--- Clear the clock display (`clock_display`) on edits
--- (org-remove-highlights-with-change).
---@param bufnr integer
function M.attach(bufnr)
  -- (the namespace org.clock draws the display in)
  local display_ns = vim.api.nvim_create_namespace("org.clock.display")
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertEnter" }, {
    buffer = bufnr,
    group = vim.api.nvim_create_augroup("org.clock.buf." .. bufnr, { clear = true }),
    callback = function()
      if require("org.config").opts.remove_highlights_with_change ~= false then
        vim.api.nvim_buf_clear_namespace(bufnr, display_ns, 0, -1)
      end
    end,
  })
  vim.api.nvim_set_hl(0, "OrgClockSum", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "OrgClockOverlay", { link = "OrgClockSum", default = true })
  vim.api.nvim_set_hl(0, "OrgClockOverlayDots", { link = "NonText", default = true })
end

return M
