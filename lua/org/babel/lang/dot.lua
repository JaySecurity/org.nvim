---@mod org.babel.lang.dot Graphviz blocks (ob-dot)
---
--- The diagrams extension replaces this handler with its own (generated
--- file names, a cache, previews) while it is on.

local ob = require("org.babel.ob")

local M = {}

--- `org-babel-expand-body:dot`: `$NAME` becomes the value of `:var NAME`,
--- :prologue and :epilogue around the body.
function M.expand(body, args, vars)
  local text = ob.body_text(body)
  for _, v in ipairs(vars or {}) do
    local value = type(v.value) == "string" and v.value or require("org.babel.lisp").prin1(v.value)
    text = text:gsub("%$" .. vim.pesc(v.name), function()
      return value
    end)
  end
  local prologue, epilogue = ob.unq(args.prologue), ob.unq(args.epilogue)
  return (prologue and (prologue .. "\n") or "") .. text .. (epilogue and ("\n" .. epilogue .. "\n") or "")
end

--- `org-babel-execute:dot`: `CMD IN CMDLINE -o OUT`, CMDLINE defaulting to
--- `-T` and the extension of the :file, CMD to `:cmd` or the `cmd` option.
function M.prepare(body, args, vars, ctx)
  local out_file = ob.unq(args.file)
  if not out_file or out_file == "" then
    error("You need to specify a :file parameter", 0)
  end
  local cmdline = ob.unq(args.cmdline) or ("-T" .. (out_file:match("%.([^./\\]+)$") or ""))
  local cmd = ob.unq(args.cmd) or ctx.opts.cmd or "dot"
  local in_file = ob.write(ob.temp(".dot"), M.expand(body, args, vars))
  return {
    steps = { { cmd = string.format("%s %s %s -o %s", cmd, ob.sh(in_file), cmdline, ob.sh(out_file)) } },
    convert = function()
      return nil
    end,
  }
end

return M
