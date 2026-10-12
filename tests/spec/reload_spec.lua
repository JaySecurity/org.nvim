-- reload_on_change: buffers reload when another program changes their file.
local reload = require("org.reload")
local utils = require("org.utils")

local function write(path, lines)
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
end

describe("reload_on_change", function()
  with_config({ reload_on_change = true })

  local dir, path, warnings, real_warn

  before_each(function()
    dir = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(dir, "p")
    path = dir .. "/notes.org"
    write(path, { "* A", "body a", "** A1", "x", "* B", "body b", "* C", "c" })
    warnings = {}
    real_warn = utils.warn
    utils.warn = function(msg)
      warnings[#warnings + 1] = msg
    end
    reload.debounce = 20
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    -- file system watchers take a moment to start (FSEvents on macOS, and
    -- Neovim 0.13's own 'autoread' watcher): changes made before are missed
    vim.wait(500, function()
      return false
    end, 10)
  end)

  after_each(function()
    utils.warn = real_warn
    reload.debounce = 200
    vim.cmd("silent! %bwipeout!")
    reload.stop()
    vim.fn.delete(dir, "rf")
  end)

  local function wait_lines(buf, n)
    return vim.wait(5000, function()
      return vim.api.nvim_buf_line_count(buf) == n
    end, 10)
  end

  it("watches the directory of the buffer's file", function()
    eq(1, reload.watch_count())
    vim.cmd("bwipeout!")
    eq(0, reload.watch_count())
  end)

  it("reloads an unmodified buffer written by another program", function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    local before = reload.stats.reloads
    write(path, { "* A", "body a", "** A1", "x", "* B", "body b", "* C", "c", "* D from the phone" })
    ok(wait_lines(buf, 9))
    eq("* D from the phone", buf_lines(buf)[9])
    eq(before + 1, reload.stats.reloads)
    eq(false, vim.bo[buf].modified)
    eq({ 7, 0 }, vim.api.nvim_win_get_cursor(0))
    eq({}, warnings)
    -- the reload is undoable
    vim.cmd("silent undo")
    eq(8, vim.api.nvim_buf_line_count(buf))
  end)

  it("reloads with 'autoread' off too", function()
    local buf = vim.api.nvim_get_current_buf()
    vim.o.autoread = false
    local okw, err = pcall(function()
      write(path, { "* Only line" })
      ok(wait_lines(buf, 1))
      eq({ "* Only line" }, buf_lines(buf))
      eq({}, warnings)
    end)
    vim.o.autoread = true
    assert(okw, err)
  end)

  it("keeps closed folds across the reload", function()
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd("5foldclose")
    eq(5, vim.fn.foldclosed(5))
    -- a line added above moves the fold down
    write(path, { "#+title: Notes", "* A", "body a", "** A1", "x", "* B", "body b", "* C", "c" })
    ok(wait_lines(buf, 9))
    eq(6, vim.fn.foldclosed(6))
    eq(-1, vim.fn.foldclosed(2))
  end)

  it("sees a save that writes a temporary file and renames it", function()
    local buf = vim.api.nvim_get_current_buf()
    local tmp = dir .. "/.notes.org.tmp"
    write(tmp, { "* Renamed over" })
    assert(vim.uv.fs_rename(tmp, path))
    ok(wait_lines(buf, 1))
    eq({ "* Renamed over" }, buf_lines(buf))
    -- still watched after the rename: a second change is seen too
    write(path, { "* Renamed over", "* Again" })
    ok(wait_lines(buf, 2))
  end)

  it("keeps a modified buffer and warns", function()
    local buf = vim.api.nvim_get_current_buf()
    -- (Neovim 0.13+ watches 'autoread' buffers itself and asks, W12)
    vim.bo[buf].autoread = false
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "* A edited here" })
    write(path, { "* Changed elsewhere" })
    ok(vim.wait(5000, function()
      return #warnings > 0
    end, 10))
    ok(warnings[1]:find("notes.org changed on disk; your unsaved changes are kept", 1, true))
    eq("* A edited here", buf_lines(buf)[1])
    eq(8, vim.api.nvim_buf_line_count(buf))
    ok(vim.bo[buf].modified)
    -- once per change
    reload.check(buf)
    eq(1, #warnings)
  end)

  it("keeps the folds when Neovim's own 'autoread' watcher reloads first", function()
    local buf = vim.api.nvim_get_current_buf()
    -- org looks later than Neovim (0.13+) does, or Neovim reloads on focus
    reload.debounce = 3000
    vim.cmd("5foldclose")
    write(path, { "#+title: Notes", "* A", "body a", "** A1", "x", "* B", "body b", "* C", "c" })
    if not pcall(vim.api.nvim_get_autocmds, { group = "nvim.autoread" }) then
      -- (older Neovim: what its FocusGained check does)
      vim.wait(100, function()
        return false
      end, 10)
      vim.cmd("checktime")
    end
    ok(wait_lines(buf, 9))
    eq(6, vim.fn.foldclosed(6))
    eq(-1, vim.fn.foldclosed(2))
  end)

  it("leaves a modified buffer to Neovim's own 'autoread' watcher (0.13+)", function()
    if not pcall(vim.api.nvim_get_autocmds, { group = "nvim.autoread" }) then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local seen = 0
    vim.api.nvim_create_autocmd("FileChangedShell", {
      buffer = buf,
      callback = function()
        seen = seen + 1
        vim.v.fcs_choice = ""
      end,
    })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "* A edited here" })
    write(path, { "* Changed elsewhere" })
    ok(vim.wait(5000, function()
      return seen > 0
    end, 10))
    vim.wait(400, function()
      return false
    end, 10)
    eq({}, warnings)
    eq("* A edited here", buf_lines(buf)[1])
  end)

  it("does not reload or warn after its own saves", function()
    local buf = vim.api.nvim_get_current_buf()
    local before = reload.stats.reloads
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "* A saved by org" })
    ok(utils.save_buffer(buf))
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "typed after the save" })
    vim.cmd("silent write")
    -- edits typed right after a save, before the events arrive
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "** typed again" })
    vim.wait(400, function()
      return false
    end, 10)
    reload.check(buf)
    eq(before, reload.stats.reloads)
    eq({}, warnings)
    eq("** typed again", buf_lines(buf)[3])
  end)

  it("does nothing when reload_on_change is off", function()
    local buf = vim.api.nvim_get_current_buf()
    require("org.config").opts.reload_on_change = false
    -- (Neovim 0.13+ reloads 'autoread' buffers itself)
    vim.bo[buf].autoread = false
    local before = reload.stats.reloads
    write(path, { "* Changed elsewhere" })
    vim.wait(400, function()
      return false
    end, 10)
    reload.check(buf)
    eq(before, reload.stats.reloads)
    eq(8, vim.api.nvim_buf_line_count(buf))
    -- a buffer opened while it is off is not watched
    vim.cmd("bwipeout!")
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    eq(0, reload.watch_count())
  end)
end)
