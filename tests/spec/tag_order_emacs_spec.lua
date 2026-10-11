-- The order of a headline's tags, as Emacs Org 9.8.10's org-get-tags
-- builds it: file tags, the ancestors' tags from the top, then the own
-- ones as written; a tag found more than once is kept at its last (most
-- local) place: (nreverse (delete-dups (nreverse ...))). The agenda shows
-- that list with "::" between the inherited and the own tags
-- (org-agenda-fix-displayed-tags). Expected lines are from Emacs.
local config = require("org.config")
local files = require("org.files")
local parser = require("org.parser")

local LINES = {
  "#+FILETAGS: :ft:x:",
  "* A :x:a:b:",
  "** B :b:c:a:",
  "*** C :work:",
  "** D :c:work:c:",
}

local function headline(file, title)
  for _, hl in ipairs(file.headlines) do
    if hl.title == title then
      return hl
    end
  end
end

describe("tag order (org-get-tags)", function()
  local path

  before_each(function()
    path = vim.fn.tempname() .. ".org"
    vim.fn.writefile(LINES, path)
    config.setup({ agenda_files = { path } })
    files.invalidate(path)
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    os.remove(path)
  end)

  it("keeps a repeated tag at its most local place", function()
    local file = parser.parse(LINES, path)
    -- ft x | x a b | b c a -> ft x b c a
    eq({ "ft", "x", "b", "c", "a" }, headline(file, "B"):get_tags())
    eq({ "ft", "x" }, headline(file, "B"):get_inherited_tags())
    eq({ "ft", "x", "b", "c", "a", "work" }, headline(file, "C"):get_tags())
    -- ft x | x a b | c work c -> ft x a b work c
    eq({ "ft", "x", "a", "b", "work", "c" }, headline(file, "D"):get_tags())
    eq({ "ft", "x", "a", "b" }, headline(file, "D"):get_inherited_tags())
    -- own tags only: as written
    eq({ "c", "work", "c" }, headline(file, "D"):get_tags({ inherited = false }))
  end)

  it("shows inherited tags, then the own ones in a tags match", function()
    require("org.agenda").open_tags("work", false)
    local lines = require("org.agenda.view").build(80).lines
    local name = vim.fn.fnamemodify(path, ":t:r")
    local got = {}
    for _, l in ipairs(lines) do
      if l:find(name .. ":", 1, true) then
        got[#got + 1] = vim.trim(l:gsub("^%s*[^:]+:%s*", ""):gsub("%s+", " "))
      end
    end
    eq({ "C :ft:x:b:c:a::work:", "D :ft:x:a:b::work:c:" }, got)
  end)
end)
