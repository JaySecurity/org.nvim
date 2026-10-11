-- Inline tasks in agenda views, as Emacs Org 9.8.10 with org-inlinetask
-- loaded (org-inlinetask-min-level 15) shows them. Expected lines are
-- from Emacs.
local config = require("org.config")
local files = require("org.files")

local STARS = string.rep("*", 15)

describe("inline tasks in the agenda", function()
  local path, saved

  --- The entries of the agenda opened by `open` (its "name:" lines),
  --- whitespace squashed.
  local function entries(open)
    open(require("org.agenda"))
    local name = vim.fn.fnamemodify(path, ":t:r")
    local got = {}
    for _, l in ipairs(require("org.agenda.view").build(80).lines) do
      if l:find(name .. ":", 1, true) then
        got[#got + 1] = vim.trim((l:gsub("^%s*[^:]+:%s*", ""):gsub("%s+", " ")))
      end
    end
    vim.cmd("silent! %bwipeout!")
    return got
  end

  local function write(lines)
    vim.fn.writefile(lines, path)
    files.invalidate(path)
  end

  before_each(function()
    path = vim.fn.tempname() .. ".org"
    config.setup({ agenda_files = { path } })
    saved = config.opts.inlinetask_min_level
    config.opts.inlinetask_min_level = 15
  end)

  after_each(function()
    config.opts.inlinetask_min_level = saved
    files.invalidate()
    os.remove(path)
  end)

  it("a tags match lists the inline task, not its END line", function()
    write({ "* Project :work:", STARS .. " TODO Inline", STARS .. " END" })
    eq(
      { "Project :work:", "TODO Inline :work::" },
      entries(function(a)
        a.open_tags("work", false)
      end)
    )
  end)
end)
