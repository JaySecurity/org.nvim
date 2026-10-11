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

  -- org-agenda-get-timestamps skips what org-before-first-heading-p says
  -- is before the first heading, and that doesn't count inline tasks;
  -- date ranges (org-agenda-get-blocks) and planning still show
  it("an inline task before the first heading gets no timestamp entries", function()
    write({
      STARS .. " TODO Task :work:",
      "SCHEDULED: <2026-10-01 Thu>",
      "<2026-09-30 Wed>--<2026-10-02 Fri>",
      "<%%(diary-float t 4 1)>",
      "<2026-10-01 Thu>",
      STARS .. " END",
      "* H",
    })
    eq(
      {
        "(1/3): TODO Task :work:",
        "Scheduled: TODO Task :work:",
        "(2/3): TODO Task :work:",
        "(3/3): TODO Task :work:",
      },
      entries(function(a)
        a.open_agenda({ span = "week", anchor = require("org.date").read_date("2026-09-28"):days() })
      end)
    )
  end)

  it("an inline task under a heading keeps its timestamp entries", function()
    write({
      "* H",
      STARS .. " TODO Task :work:",
      "<2026-10-01 Thu>",
      STARS .. " END",
    })
    eq(
      { "TODO Task :work:" },
      entries(function(a)
        a.open_agenda({ span = "week", anchor = require("org.date").read_date("2026-09-28"):days() })
      end)
    )
  end)
end)
