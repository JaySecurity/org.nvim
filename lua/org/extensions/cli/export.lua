---@mod org.extensions.cli.export The export command
---
--- `org export FILE BACKEND`: to a file, or to stdout with `--stdout`,
--- stopping at a code block that would ask before it runs. Part of
--- org.extensions.cli.run, which loads it.

local data = require("org.extensions.cli.data")

local M = require("org.extensions.cli.run")

local fail = M.fail
local arg_path = M.arg_path
local load_buffer = M.load_buffer

--- Stop the export at a code block that would ask before it runs
--- (`babel.confirm_evaluate`, `:eval query`): nothing is exported, as in
--- Emacs's batch export, and the command fails with `input_needed`. The
--- before-parsing hooks run right after the blocks are evaluated, and an
--- export that fails there writes nothing.
local function stop_export_at_prompt()
  local o = require("org.config").opts.export
  o.hooks = o.hooks or {}
  local before = o.hooks.before_parsing
  local list = type(before) == "table" and vim.list_slice(before) or { before }
  table.insert(list, 1, function()
    M.check_prompted()
  end)
  o.hooks.before_parsing = list
end

function M.cmd_export(words, flags)
  local file, backend = words[1], words[2]
  if not file or not backend then
    fail("usage: org export FILE BACKEND [-o OUTPUT|--stdout]", "usage")
  end
  file = arg_path(file)
  if vim.fn.filereadable(file) == 0 then
    fail("no such file: " .. file, "bad_value", { file = file })
  end
  local export = require("org.export")
  local to_stdout = flags.stdout or flags.output == "-"
  if not export.FORMATS[backend] then
    -- other formats go through pandoc, which writes files only; without
    -- pandoc the export itself says so
    local pandoc = not to_stdout and export.pandoc_output_formats()
    if not (pandoc == nil and not to_stdout) and not (pandoc and vim.tbl_contains(pandoc, backend)) then
      local names = vim.tbl_keys(export.FORMATS)
      table.sort(names)
      fail(
        string.format(
          "unknown export back-end %s (%s%s)",
          backend,
          table.concat(names, ", "),
          to_stdout and "" or ", or a pandoc output format"
        ),
        "bad_value",
        { backend = backend }
      )
    end
  end
  local bufnr = load_buffer(file)
  vim.api.nvim_set_current_buf(bufnr)
  stop_export_at_prompt()
  M.mark_messages()
  if to_stdout then
    local ok, text = pcall(export.to_string, backend, { bufnr = bufnr })
    M.check_prompted()
    if not ok then
      fail(tostring(text), "failed")
    end
    return {
      data = { file = file, backend = backend, output = vim.NIL, text = text },
      raw = text:sub(-1) == "\n" and text or (text .. "\n"),
    }
  end
  local output = flags.output and arg_path(flags.output) or nil
  local res = export.export(backend, { bufnr = bufnr, output = output, async = false })
  if not res then
    M.fail_with_messages("export failed")
  end
  M.check_prompted()
  res = vim.fs.normalize(res)
  return { data = { file = file, backend = backend, output = data.path(res), text = vim.NIL }, text = { res } }
end
