-- Opening the first org file in a new Neovim: what `setup()` and the
-- first `:edit` load and how long they take. Run in a Neovim of its own,
-- so nothing is loaded before it:
--
--   nvim --clean --headless -l tests/helpers/first_open.lua <root> <file.org>
--
-- prints one line of JSON: { setup_ms, open_ms, setup_modules, modules }
-- (the org.* modules loaded after setup() and after the file is open and
-- drawn, sorted). Used by tests/spec/first_open_spec.lua (the modules),
-- perf_budgets_spec.lua (the times) and scripts/bench.lua.
local root, file = _G.arg[1], _G.arg[2]
vim.opt.rtp:prepend(root)
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.env.ORG_NVIM_SERVER = "none"

local function org_modules()
  local out = {}
  for name in pairs(package.loaded) do
    if name == "org" or name:sub(1, 4) == "org." then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function ms(t)
  return (vim.uv.hrtime() - t) / 1e6
end

vim.cmd("runtime plugin/org.lua")
local t = vim.uv.hrtime()
require("org").setup({
  -- (no background parse or watchers: they start after the timing anyway)
  agenda = { index = { background = false, watch = false } },
})
local setup_ms = ms(t)
local setup_modules = org_modules()

t = vim.uv.hrtime()
vim.cmd.edit(vim.fn.fnameescape(file))
vim.cmd("redraw")
local open_ms = ms(t)
assert(vim.bo.filetype == "org", "not opened as org: " .. vim.bo.filetype)

io.stdout:write(vim.json.encode({
  setup_ms = setup_ms,
  open_ms = open_ms,
  setup_modules = setup_modules,
  modules = org_modules(),
}) .. "\n")
vim.cmd("qa!")
