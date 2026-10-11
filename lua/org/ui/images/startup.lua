---@mod org.ui.images.startup Previews on opening a buffer
---
--- Whether a buffer starts with its link or LaTeX previews shown, kept
--- out of org.ui.images so that opening a file without them doesn't load
--- it.

local config = require("org.config")

local M = {}

--- `#+STARTUP` words of the buffer in order: the last of a pair wins.
---@param bufnr integer
---@return boolean|nil links, boolean|nil latex
function M.startup(bufnr)
  local links = (config.opts.ui.images or {}).startup
  local latex = (config.opts.ui.latex_preview or {}).startup
  local settings = require("org.files").get_buffer(bufnr).settings.keywords.STARTUP or {}
  for _, words in ipairs(settings) do
    for w in words:lower():gmatch("%S+") do
      if w == "inlineimages" or w == "linkpreviews" then
        links = true
      elseif w == "noinlineimages" or w == "nolinkpreviews" then
        links = false
      elseif w == "latexpreview" then
        latex = true
      elseif w == "nolatexpreview" then
        latex = false
      end
    end
  end
  return links, latex
end

--- Called for every org buffer: org.ui.images shows the startup previews
--- (org-startup-with-link-previews, org-startup-with-latex-preview).
---@param bufnr integer
function M.setup_buffer(bufnr)
  local links, latex = M.startup(bufnr)
  if links or latex then
    require("org.ui.images").setup_buffer(bufnr)
  end
end

return M
