---@mod org.babel.lang.sed sed blocks (ob-sed)

local ob = require("org.babel.ob")

local M = {}

--- ob-sed has no expand function: the generic one without variables.
function M.expand(body, args)
  return ob.expand_generic(type(body) == "table" and body or { body }, args, {})
end

--- `org-babel-execute:sed`: `CMD -f "SCRIPT" :cmd-line :in-file`, reading
--- the value of `:stdin` (a reference) when given.
function M.prepare(body, args, _, ctx)
  local code_file = ob.write(ob.temp(".sed"), ob.body_text(body))
  local parts = { ctx.opts.cmd or "sed", string.format('-f "%s"', code_file) }
  parts[#parts + 1] = ob.unq(args["cmd-line"])
  parts[#parts + 1] = ob.unq(args["in-file"])
  local step = { cmd = table.concat(parts, " ") }
  if args.stdin then
    local res = require("org.babel").resolve_var(ctx.bufnr, args.stdin, args, {})
    step.stdin = type(res) == "string" and res or require("org.babel.langs").table_to_text(res)
  end
  return {
    steps = { step },
    convert = function(raw)
      return ob.result_cond(args, raw, function(s)
        return ob.import(s)
      end)
    end,
  }
end

return M
