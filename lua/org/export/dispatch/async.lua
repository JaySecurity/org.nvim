---@mod org.export.dispatch.async Asynchronous export
---
--- Exports in a separate Neovim process (org-export-async-start), their
--- results going to the export stack.
---
--- Part of org.export, which loads it.

local utils = require("org.utils")
local shared = require("org.export.dispatch.shared")

local M = require("org.export")

local FILETYPES = shared.FILETYPES
local cfg = shared.cfg
local open_scratch = shared.open_scratch

--- Lua source for a value (strings, numbers, booleans and tables; functions
--- and other values are left out), for the configuration of the
--- asynchronous export process.
local function serialize(v, seen)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    return tostring(v)
  elseif t ~= "table" or v == vim.NIL then
    return "nil"
  end
  seen = seen or {}
  if seen[v] then
    return "nil"
  end
  seen[v] = true
  local parts = {}
  for k, x in pairs(v) do
    local kt = type(k)
    if (kt == "string" or kt == "number") and type(x) ~= "function" then
      local val = serialize(x, seen)
      if val ~= "nil" then
        local keystr = kt == "number" and ("[" .. k .. "]") or string.format("[%q]", k)
        parts[#parts + 1] = keystr .. "=" .. val
      end
    end
  end
  seen[v] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end
M._serialize = serialize

--- The script run by the export process: set up org.nvim with the
--- session's options (without Lua functions, like the -Q Emacs of
--- org-export-async-start), answer no to every prompt (Babel blocks that
--- need a confirmation keep their results), export and write the result.
local CHILD_SCRIPT = [[
local job = dofile(_G.arg[1])
vim.opt.rtp:prepend(job.root)
vim.opt.swapfile = false
package.path = job.lua_dir .. "/?.lua;" .. job.lua_dir .. "/?/init.lua;" .. package.path
local utils = require("org.utils")
utils.input = function() return nil end
utils.input_complete = function() return nil end
utils.confirm = function() return false end
utils.notify = function() end
local errors = {}
utils.error = function(msg) errors[#errors + 1] = tostring(msg) end
vim.fn.input = function() return "" end
vim.fn.confirm = function() return 0 end
vim.ui.select = function(_, _, cb) cb(nil) end
-- the compilers run with the shell of the Neovim that started the export
-- (--clean would fall back to cmd.exe on Windows)
for name, value in pairs(job.shell or {}) do
  pcall(vim.api.nvim_set_option_value, name, value, {})
end
require("org").setup(job.config)
if job.init_file and job.init_file ~= "" then
  dofile(vim.fn.expand(job.init_file))
end
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, job.lines)
if job.filename then
  pcall(vim.api.nvim_buf_set_name, buf, job.filename)
end
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = "org"
local export = require("org.export")
local result = {}
local ok, err = pcall(function()
  if job.to_buffer then
    result.text = export.to_string(job.format, {
      bufnr = buf,
      filename = job.filename,
      subtree_line = job.subtree_line,
      body_only = job.body_only,
    })
    result.filetype = job.filetype
  else
    result.output = export.export(job.format, {
      bufnr = buf,
      subtree_line = job.subtree_line,
      body_only = job.body_only,
      output = job.output,
      async = false,
    })
  end
end)
if not ok then
  result.error = tostring(err)
elseif not result.text and not result.output then
  result.error = #errors > 0 and table.concat(errors, "\n") or "no output"
end
-- what the compiler (or converter) printed, for the stack and the error
local last = package.loaded["org.export.process"] and require("org.export.process").last_output
if last then
  result.log = last.text
  result.log_name = last.name
end
local f = assert(io.open(job.result, "wb"))
f:write("return " .. export._serialize(result))
f:close()
]]

--- Export in the background (dispatcher `a`, `export.in_background`,
--- `:Org export FORMAT async`): like org-export-async-start, a separate
--- Neovim process exports a copy of the buffer with the session's options
--- (`export.async_init_file`, a Lua file, runs there first) and the result
--- (a file, or a buffer for "as buffer" exports) goes to the export stack
--- instead of being shown. The buffer and the options are copied when the
--- export starts, so editing meanwhile changes nothing. While it runs, the
--- stack entry shows the output of the process ("*Org Export Process*")
--- and can be cancelled; after a failure it keeps that output. Visible-only
--- exports run in this Neovim, right after the dispatcher closes, with
--- their compiler or converter in the background.
function M.export_async(format, opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  opts.bufnr = (opts.bufnr == nil or opts.bufnr == 0) and vim.api.nvim_get_current_buf() or opts.bufnr
  if opts.subtree and not opts.subtree_line then
    opts.subtree_line = vim.api.nvim_win_get_cursor(0)[1]
  end
  local spec = M.FORMATS[format]
  local backend = spec and spec[1] or format
  local entry = M.stack_add(nil, backend, true)
  utils.notify("Initializing asynchronous export process")
  local function finish(result, err)
    M.stack_finish(entry, result, err)
    if result and opts.open and type(result) == "string" then
      vim.ui.open(result)
    end
  end
  if not opts.visible_only then
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local src = vim.api.nvim_buf_get_name(opts.bufnr)
    local job = {
      root = require("org.version").root(),
      lua_dir = require("org.version").lua_dir(),
      config = require("org.config").opts,
      init_file = cfg().async_init_file,
      shell = {
        shell = vim.o.shell,
        shellcmdflag = vim.o.shellcmdflag,
        shellquote = vim.o.shellquote,
        shellxquote = vim.o.shellxquote,
        shellredir = vim.o.shellredir,
        shellpipe = vim.o.shellpipe,
      },
      lines = vim.api.nvim_buf_get_lines(opts.bufnr, 0, -1, false),
      filename = src ~= "" and src or nil,
      format = format,
      subtree_line = opts.subtree_line,
      body_only = opts.body_only,
      output = opts.output,
      to_buffer = opts.to_buffer,
      filetype = spec and FILETYPES[spec[1]] or nil,
      result = dir .. "/result.lua",
    }
    local jobfile, script = dir .. "/job.lua", dir .. "/run.lua"
    local ok = pcall(function()
      local f = assert(io.open(jobfile, "wb"))
      f:write("return " .. serialize(job))
      f:close()
      f = assert(io.open(script, "wb"))
      f:write(CHILD_SCRIPT)
      f:close()
    end)
    local cmd = { vim.v.progpath, "--clean", "--headless", "-n", "-i", "NONE", "-l", script, jobfile }
    local process = require("org.export.process")
    local proc
    local function done(run)
      local okr, r = pcall(dofile, job.result)
      vim.fn.delete(dir, "rf")
      if run.cancelled then
        return finish(nil)
      end
      if okr and type(r) == "table" and r.log and r.log ~= "" then
        -- the output of the compiler that ran there, here too
        process.append(run.log_buf, r.log)
        if r.log_name then
          local buf = process.log_buffer(r.log_name)
          process.append(buf, r.log)
        end
      end
      if not okr or type(r) ~= "table" or r.error then
        local msg = okr and type(r) == "table" and r.error or vim.trim(run:text())
        if msg == "" then
          msg = "Process exited abnormally (" .. tostring(run.code) .. ")"
        end
        utils.error("Asynchronous export failed: " .. msg)
        return finish(nil, msg)
      end
      if r.text then
        local name = backend == "org" and "Org ORG Export" or ("Org " .. backend:upper() .. " Export")
        local buf = open_scratch(r.text, r.filetype, name, true)
        M.last_buffer = buf
        utils.notify("Asynchronous export finished: " .. vim.api.nvim_buf_get_name(buf))
        return finish(buf)
      end
      local out = vim.fn.fnamemodify(r.output, ":p")
      utils.notify("Asynchronous export finished: " .. out)
      finish(out)
    end
    if ok then
      local cwd = src ~= "" and vim.fn.fnamemodify(src, ":p:h") or nil
      ok, proc = pcall(process.run, { cmd }, { cwd = cwd, log_buffer = "*Org Export Process*" }, done)
    end
    if ok and proc then
      entry.process, entry.source, entry.kill_log = proc, proc.log_buf, true
      M.stack_refresh()
      return entry
    end
  end
  -- in this Neovim, right after the dispatcher (visible-only needs the folds)
  opts.hidden = true
  opts.async = true
  opts.interactive = nil -- output is not copied from asynchronous exports
  opts.stack_entry = entry
  opts.on_done = function(result, err)
    M.stack_finish(entry, result, err)
  end
  vim.schedule(function()
    local ok, res, proc = pcall(M.export, format, opts)
    if proc then
      return -- a compiler or converter runs: opts.on_done finishes the entry
    end
    if not ok or not res then
      if not ok then
        utils.error("Export failed: " .. tostring(res))
      end
      M.stack_finish(entry, nil)
    elseif res == "buffer" then
      M.stack_finish(entry, M.last_buffer)
    else
      M.stack_finish(entry, vim.fn.fnamemodify(res, ":p"))
    end
  end)
  return entry
end
