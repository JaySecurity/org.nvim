---@mod org.extensions.cli.save Guarding files and saving them
---
--- A file a running Neovim has unsaved changes in is refused (`guard`),
--- modified buffers are saved through the write hooks (`save_all`) and a
--- running Neovim is told, and org.nvim's own messages become failures.
--- Part of org.extensions.cli.run, which loads it.

local shared = require("org.extensions.cli.shared")

local M = require("org.extensions.cli.run")

local fail = M.fail
local state = shared.state
local arg_path = M.arg_path
local short_path = M.short_path

-- Tell a running Neovim (with the cli extension on) that files changed:
-- it watches this file, rereads changed files and the clock
-- (org.clock.sync).
local function touch_stamp()
  pcall(function()
    local path = require("org.extensions.cli").stamp_path()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fh = io.open(path, "wb")
    if fh then
      fh:write(tostring(vim.uv.hrtime()) .. "\n")
      fh:close()
    end
  end)
end

--- Swap files a Neovim editing `path` would have ('directory').
local function swap_files(path)
  local full = arg_path(path)
  local tail = vim.fn.fnamemodify(full, ":t")
  local head = vim.fn.fnamemodify(full, ":h")
  local win = vim.fn.has("win32") == 1
  local out = {}
  for _, d in ipairs(vim.split(vim.o.directory, ",", { trimempty = true })) do
    local percent = d:match("//$") or d:match("\\\\$")
    local dir = d:gsub("[/\\]+$", "")
    local base
    if dir == "." or dir == "" then
      dir, base = head, "." .. tail
    elseif percent then
      base = full:gsub(win and "[/\\:]" or "/", "%%")
    else
      base = tail
    end
    for _, ext in ipairs({ ".swp", ".swo", ".swn" }) do
      out[#out + 1] = dir .. "/" .. base .. ext
    end
  end
  return out
end

--- Fail with `file_busy` when a running Neovim has unsaved changes in
--- `path` (its swap file says so), unless --force.
---@param path string
---@param flags table
function M.guard(path, flags)
  if not path or flags.force then
    return
  end
  local me = vim.fn.getpid()
  for _, sw in ipairs(swap_files(path)) do
    if vim.uv.fs_stat(sw) then
      local ok, info = pcall(vim.fn.swapinfo, sw)
      if ok and type(info) == "table" and not info.error and info.dirty == 1 and info.pid ~= me then
        local alive = info.pid and info.pid > 0 and vim.uv.kill(info.pid, 0) == 0
        if alive then
          fail(
            string.format(
              "%s has unsaved changes in a running Neovim (pid %d); save it there or use --force",
              path,
              info.pid
            ),
            "file_busy",
            { file = arg_path(path), pid = info.pid, swap = sw }
          )
        end
      end
    end
  end
end

--- Save every modified buffer (through utils.save_buffer: the write hooks
--- run) and tell a running Neovim. None is written unless all can be:
--- no file has unsaved changes in a running Neovim, and no write hook
--- refuses one (org-crypt without the passphrase it would ask for).
function M.save_all(flags)
  local utils = require("org.utils")
  local hooks = require("org.write_hooks")
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.api.nvim_buf_get_name(b) ~= "" then
      if state.dirty_before[b] then
        -- the session's user has unsaved changes there: the change is in
        -- the buffer, saved when they save it
        vim.notify(
          short_path(vim.api.nvim_buf_get_name(b)) .. " has unsaved changes in Neovim; the change is not saved yet",
          vim.log.levels.WARN
        )
      else
        bufs[#bufs + 1] = b
      end
    end
  end
  local function failed(b, e)
    -- a prompt a hook couldn't ask (a passphrase) is the reason
    M.check_prompted()
    local name = vim.api.nvim_buf_get_name(b)
    fail("could not save " .. name .. ": " .. tostring(e), "failed", { file = name })
  end
  for _, b in ipairs(bufs) do
    M.guard(vim.api.nvim_buf_get_name(b), flags or {})
  end
  -- The pre-write hooks of every buffer run before any file is written.
  -- What they change (entries org-crypt encrypts) stays for the write;
  -- the post hooks undo the rest, as after a failed write.
  for _, b in ipairs(bufs) do
    local ok, e, run = hooks.run_pre(b, "save_buffer")
    if not ok then
      failed(b, e)
    end
    hooks.run_post(run, false)
  end
  for _, b in ipairs(bufs) do
    local ok, e = utils.save_buffer(b)
    if not ok then
      failed(b, e)
    end
    state.touched = true
  end
  if state.touched then
    touch_stamp()
  end
end

--- Fail with `input_needed` when a prompt was refused during the command.
function M.check_prompted()
  if state.prompted then
    fail(
      "interactive input needed (" .. state.prompted .. "); not available in the CLI",
      "input_needed",
      { prompt = state.prompted }
    )
  end
end

--- Fail with org.nvim's own warnings and errors as the message.
function M.fail_with_messages(default, ecode)
  M.check_prompted()
  local msgs = {}
  for _, m in ipairs(state.messages) do
    if m.level >= vim.log.levels.WARN then
      msgs[#msgs + 1] = m.msg
    end
  end
  fail(#msgs > 0 and msgs[#msgs] or default, ecode or "failed", { messages = msgs })
end

--- Forget the messages so far (fail_with_messages reports the ones a
--- step adds).
function M.mark_messages()
  state.messages = {}
end

shared.touch_stamp = touch_stamp
