---@mod org.cite.attach Per-buffer citation setup
---
--- What `org.buffer` sets up for citations in every org buffer, kept out
--- of org.cite so that opening a file doesn't load it: the decoration
--- provider that highlights citations (org-cite-activate) loads org.cite
--- only when a `[cite` is in view.

local M = {}

--- Lines around the ones drawn (and around the cursor) that are read to
--- find the citations spanning them.
M.MAX_SPAN = 40

local ns = vim.api.nvim_create_namespace("org.cite")
local attached = {}
local current

--- Is there a `[cite` in rows [top - MAX_SPAN, bot + MAX_SPAN] (0-based)?
local function cite_in_view(bufnr, top, bot)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local first = math.max(0, top - M.MAX_SPAN)
  local last = math.min(count - 1, bot + M.MAX_SPAN)
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)) do
    if l:find("[cite", 1, true) then
      return true
    end
  end
  return false
end

vim.api.nvim_set_decoration_provider(ns, {
  on_win = function(_, _, bufnr, toprow, botrow)
    if not attached[bufnr] then
      return false
    end
    current = nil
    if not cite_in_view(bufnr, toprow, botrow) then
      return false
    end
    local ok, rows = pcall(function()
      return require("org.cite").marks(bufnr, toprow, botrow)
    end)
    current = ok and rows or nil
    return current ~= nil and next(current) ~= nil
  end,
  on_line = function(_, _, bufnr, row)
    local marks = current and current[row]
    if not marks then
      return
    end
    for _, m in ipairs(marks) do
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, m[1], {
        end_col = m[2],
        hl_group = m[3],
        priority = m[4],
        ephemeral = true,
      })
    end
  end,
})

--- Activate citations in an org buffer (called for every org buffer).
---@param bufnr integer
function M.attach(bufnr)
  attached[bufnr] = true
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      attached[bufnr] = nil
    end,
  })
end

return M
