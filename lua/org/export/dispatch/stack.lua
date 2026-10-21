---@mod org.export.dispatch.stack The export stack
---
--- Results of background exports (org-export-stack) and the buffer that
--- shows them.
---
--- Part of org.export, which loads it.

local utils = require("org.utils")

local M = require("org.export")

---------------------------------------------------------------------------
-- Asynchronous export and the export stack (org-export-stack)
---------------------------------------------------------------------------

--- Export results of background exports, newest first:
--- { source = path|bufnr|nil, backend = name, time = seconds,
---   running = bool, status = nil|"exit"|"signal", process = the running
---   process (org.export.process) }.
--- While an export runs, and after it failed, its source is the buffer
--- with the output of its process.
M.stack_contents = {}

local STACK_NAME = "*Org Export Stack*"

local function stack_live(entry)
  if entry.running then
    return true
  end
  if type(entry.source) == "number" then
    return vim.api.nvim_buf_is_valid(entry.source)
  end
  return type(entry.source) == "string" and vim.uv.fs_stat(entry.source) ~= nil
end

--- Add a result to the stack, dropping entries with the same source
--- (org-export-add-to-stack). Returns the new entry.
function M.stack_add(source, backend, running)
  local new = { source = source, backend = backend, time = os.time(), running = running or nil }
  local keep = { new }
  for _, e in ipairs(M.stack_contents) do
    if source == nil or e.source ~= source then
      keep[#keep + 1] = e
    end
  end
  M.stack_contents = keep
  M.stack_refresh()
  return new
end

--- Mark a running entry as finished with its result (a file or a buffer).
--- Without a result the export failed or was cancelled: the entry stays
--- with the output of its process (Emacs keeps the process buffer of an
--- export that "exited abnormally"), or goes when there is none.
---@param entry table
---@param source? string|integer
---@param err? string
function M.stack_finish(entry, source, err)
  if not entry or entry.finished then
    return
  end
  entry.finished = true
  local running_source = entry.source
  local log = entry.running and type(running_source) == "number" and running_source or nil
  if source == nil then
    local cancelled = entry.process and entry.process.cancelled
    if log and vim.api.nvim_buf_is_valid(log) then
      if err and not cancelled then
        require("org.export.process").append(log, "\n" .. err .. "\n")
      end
      entry.running, entry.time = nil, os.time()
      entry.status = cancelled and "signal" or "exit"
    else
      M.stack_contents = vim.tbl_filter(function(e)
        return e ~= entry
      end, M.stack_contents)
    end
  else
    -- the result goes on top (org-export-add-to-stack), also when the
    -- entry was removed or the stack cleared while the export ran
    local keep = { entry }
    for _, e in ipairs(M.stack_contents) do
      if e ~= entry and e.source ~= source then
        keep[#keep + 1] = e
      end
    end
    M.stack_contents = keep
    entry.source, entry.running, entry.status, entry.time = source, nil, nil, os.time()
    -- the buffer of the export process goes, as in Emacs (a compiler's
    -- output buffer, such as "*Org PDF LaTeX Output*", stays)
    if log and entry.kill_log and log ~= source and vim.api.nvim_buf_is_valid(log) then
      pcall(vim.api.nvim_buf_delete, log, { force = true })
    end
  end
  M.stack_refresh()
end

--- Put a process an export left running (a PDF compilation, an ODT
--- conversion) on the stack, where it can be viewed and cancelled. An
--- asynchronous export (`opts.stack_entry`) keeps its own entry, which
--- gets the process; otherwise a new entry is returned, for
--- |M.stack_job_done|.
---@param proc? org.export.Process
---@param backend string
---@param opts? table export options
---@return table? entry
function M.stack_job(proc, backend, opts)
  if not proc then
    return nil
  end
  local entry = opts and opts.stack_entry
  if entry then
    entry.process = proc
    entry.source = proc.log_buf or entry.source
    M.stack_refresh()
    return nil
  end
  entry = M.stack_add(proc.log_buf, backend, true)
  entry.process = proc
  return entry
end

--- The background part of an export is done: finish its stack entry and
--- call `opts.on_done(result, err)`.
function M.stack_job_done(entry, opts, result, err)
  if entry then
    M.stack_finish(entry, result, err)
  end
  if opts and opts.on_done then
    opts.on_done(result, err)
  end
end

local function stack_source_name(e)
  if e.source == nil then
    return ""
  end
  if type(e.source) == "number" then
    local name = vim.api.nvim_buf_get_name(e.source)
    return vim.bo[e.source].buftype == "nofile" and vim.fn.fnamemodify(name, ":t") or name
  end
  return e.source
end

--- Rows of the stack buffer (org-export--stack-generate): number, back-end,
--- age ("H:MM"; while the export runs "run", after it failed "exit", after
--- it was cancelled "signal", like Emacs' process status) and source.
--- Unavailable sources (deleted files, wiped buffers) are removed first.
function M.stack_lines()
  M.stack_contents = vim.tbl_filter(stack_live, M.stack_contents)
  local out = {}
  for i, e in ipairs(M.stack_contents) do
    local age
    if e.running then
      age = "run"
    elseif e.status then
      age = e.status
    else
      local secs = math.max(0, os.time() - e.time)
      age = string.format("%d:%02d", math.floor(secs / 3600), math.floor(secs % 3600 / 60))
    end
    out[#out + 1] = string.format("%-4s %-12s %-6s %s", tostring(i), e.backend or "", age, stack_source_name(e))
  end
  return out
end

local function stack_buffer()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") == STACK_NAME then
      return b
    end
  end
end

--- Redraw the stack buffer, when it exists (org-export-stack-refresh).
function M.stack_refresh()
  local buf = stack_buffer()
  if not buf then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.stack_lines())
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Remove every entry from the stack (org-export-stack-clear). Running
--- exports go on and come back when they are done.
function M.stack_clear()
  M.stack_contents = {}
  M.stack_refresh()
end

local function stack_entry_at_point()
  local e = M.stack_contents[vim.api.nvim_win_get_cursor(0)[1]]
  if not e then
    utils.warn("Source unavailable, please refresh buffer")
  end
  return e
end

--- Remove the entry at the cursor from the stack (org-export-stack-remove);
--- the file or buffer itself is kept, and a running export goes on.
function M.stack_remove(entry)
  entry = entry or stack_entry_at_point()
  if not entry then
    return
  end
  M.stack_contents = vim.tbl_filter(function(e)
    return e ~= entry
  end, M.stack_contents)
  M.stack_refresh()
end

--- Cancel a running export: the entry at the cursor in the stack buffer,
--- elsewhere the newest running one. Its process is killed with the
--- processes it started; the entry stays, as "signal", with the output.
---@param entry? table
---@return boolean cancelled
function M.stack_cancel(entry)
  if not entry then
    if vim.api.nvim_get_current_buf() == stack_buffer() then
      entry = stack_entry_at_point()
    else
      for _, e in ipairs(M.stack_contents) do
        if e.running and e.process then
          entry = e
          break
        end
      end
    end
  end
  if not (entry and entry.running and entry.process and entry.process:cancel()) then
    utils.warn("No running export to cancel")
    return false
  end
  utils.notify("Export cancelled")
  return true
end

--- View the result at the cursor (org-export-stack-view): a buffer (the
--- output of a running or failed export too) is shown in another window,
--- a file is opened like a file link (org-open-file: `links.file_apps`,
--- HTML and PDF with the system opener), or in Neovim when `in_nvim`,
--- like C-u in Emacs.
function M.stack_view(entry, in_nvim)
  entry = entry or stack_entry_at_point()
  if not entry or entry.source == nil then
    return
  end
  if type(entry.source) == "number" then
    vim.cmd("wincmd p")
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, entry.source)
  else
    require("org.links").open_file(entry.source, { app = in_nvim and "vim" or nil })
  end
end

--- Show the export stack (org-export-stack): results of the exports run in
--- the background. <CR>/v view, d remove, x cancel, C clear, g refresh,
--- q quit.
function M.stack_show()
  local buf = stack_buffer()
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, STACK_NAME)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "orgexportstack"
    local function map(lhs, fn)
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
    end
    map("<CR>", function()
      M.stack_view(nil, vim.v.count > 0)
    end)
    map("v", function()
      M.stack_view(nil, vim.v.count > 0)
    end)
    map("d", function()
      M.stack_remove()
    end)
    map("x", function()
      M.stack_cancel()
    end)
    map("C", M.stack_clear)
    map("g", M.stack_refresh)
    map("<Space>", "j")
    map("q", "<Cmd>close<CR>")
    map("<Esc>", "<Cmd>close<CR>")
  end
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    vim.cmd("botright split")
    vim.api.nvim_win_set_buf(0, buf)
    win = vim.api.nvim_get_current_win()
  else
    vim.api.nvim_set_current_win(win)
  end
  vim.wo[win].winbar = string.format("%-4s %-12s %-6s %s", "#", "Backend", "Age", "Source")
  M.stack_refresh()
  utils.notify('Type "q" or <Esc> to quit, "g" to refresh, "x" to cancel')
  return buf
end
