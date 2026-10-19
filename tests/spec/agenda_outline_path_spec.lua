-- The outline path echoed after a line motion in the agenda
-- (org-agenda-show-outline-path, issue #277). Expected strings come from an
-- Emacs Org 9.8.10 probe: (org-display-outline-path V nil nil t) at each
-- entry's marker of (org-todo-list), V being t and `title'.
local config = require("org.config")
local utils = require("org.utils")
local view = require("org.agenda.view")
local agenda = require("org.agenda")

local dir = utils.realpath((function()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end)())

local function open(files, opts)
  local paths = {}
  for name, lines in pairs(files) do
    local p = dir .. "/" .. name
    utils.writefile(p, lines)
    local b = utils.find_buffer(p)
    if b then
      vim.api.nvim_buf_delete(b, { force = true })
    end
    paths[#paths + 1] = p
  end
  table.sort(paths)
  config.setup(vim.tbl_deep_extend("force", { agenda_files = paths, org_directory = dir }, opts or {}))
  config.opts.clock.persist = false
  agenda.open_todo()
end

local function text(chunks)
  local parts = {}
  for _, c in ipairs(chunks) do
    parts[#parts + 1] = c[1]
  end
  return table.concat(parts)
end

--- The echoed path of every entry, in agenda order.
local function paths(mode, width)
  local out = {}
  local lines = vim.api.nvim_buf_get_lines(view.state.buf, 0, -1, false)
  for lnum = 1, #lines do
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    local item = view.item_at_cursor()
    if item and item.headline then
      out[#out + 1] = text(view.outline_path_chunks(item, mode, width or 200))
    end
  end
  return out
end

local files = {
  ["a.org"] = {
    "* Project Alpha",
    "** Phase one",
    "*** TODO Write spec",
    "*** TODO Review spec",
    "* Project Beta",
    "** TODO Ship it",
    "* TODO Top level",
  },
  ["t.org"] = {
    "#+TITLE: My Doc",
    "* Project Gamma",
    "** TODO Plan",
  },
}

describe("agenda outline path", function()
  after_each(function()
    pcall(vim.cmd, "silent! only")
  end)

  it("prepends the file name and leaves out the entry's own heading", function()
    open(files)
    eq({
      "a.org/Project Alpha/Phase one",
      "a.org/Project Alpha/Phase one",
      "a.org/Project Beta",
      "a.org",
      "t.org/Project Gamma",
    }, paths(true))
  end)

  it('uses the #+TITLE with "title", else the file name', function()
    open(files, { agenda = { show_outline_path = "title" } })
    eq({
      "a.org/Project Alpha/Phase one",
      "a.org/Project Alpha/Phase one",
      "a.org/Project Beta",
      "a.org",
      "My Doc/Project Gamma",
    }, paths("title"))
  end)

  it("gives each heading its level face", function()
    open(files)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    for lnum = 1, vim.api.nvim_buf_line_count(view.state.buf) do
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      local item = view.item_at_cursor()
      if item and item.headline and item.headline.level == 3 then
        eq({
          { "a.org" },
          { "/" },
          { "Project Alpha", "OrgHeadlineLevel1" },
          { "/" },
          { "Phase one", "OrgHeadlineLevel2" },
        }, view.outline_path_chunks(item, true, 200))
        return
      end
    end
    error("no level 3 entry")
  end)

  it("cuts a long path with .. like org-format-outline-path", function()
    open(files)
    -- (org-format-outline-path '("Project Alpha" "Phase one") 20 "a.org")
    eq("a.org/Project Alph..", paths(true, 20)[1])
    eq("a.org/", paths(true, 6)[1])
  end)

  it("echoes after a line motion only", function()
    open(files)
    local echoed = {}
    local orig_echo, orig_uis = vim.api.nvim_echo, vim.api.nvim_list_uis
    vim.api.nvim_echo = function(chunks)
      echoed[#echoed + 1] = text(chunks)
    end
    vim.api.nvim_list_uis = function()
      return { {} }
    end
    local ok_run, err = pcall(function()
      local first
      for lnum = 1, vim.api.nvim_buf_line_count(view.state.buf) do
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        local item = view.item_at_cursor()
        if item and item.headline then
          first = lnum
          break
        end
      end
      vim.api.nvim_win_set_cursor(0, { first - 1, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.state.buf })
      echoed = {}
      vim.api.nvim_win_set_cursor(0, { first, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.state.buf })
      eq({ "a.org/Project Alpha/Phase one" }, echoed)
      -- a motion along the same line echoes nothing again
      vim.api.nvim_win_set_cursor(0, { first, 4 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.state.buf })
      eq(1, #echoed)
      vim.api.nvim_win_set_cursor(0, { first + 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = view.state.buf })
      eq({ "a.org/Project Alpha/Phase one", "a.org/Project Beta" }, echoed)
    end)
    vim.api.nvim_echo, vim.api.nvim_list_uis = orig_echo, orig_uis
    if not ok_run then
      error(err, 0)
    end
  end)
end)
