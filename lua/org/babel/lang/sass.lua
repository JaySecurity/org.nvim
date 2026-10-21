---@mod org.babel.lang.sass Sass blocks (ob-sass)

local ob = require("org.babel.ob")

local M = {}

--- `org-babel-expand-body:generic` without variables.
function M.expand(body, args)
  return ob.expand_generic(type(body) == "table" and body or { body }, args, {})
end

--- `org-babel-execute:sass`: `sass CMDLINE IN OUT`, OUT being the :file
--- (no result: the link) or a temporary file whose text is the result.
function M.prepare(body, args, _, ctx)
  local file = ob.unq(args.file)
  if file == "" then
    file = nil
  end
  local out_file = file or ob.temp()
  local in_file = ob.write(ob.temp(), M.expand(body, args))
  local cmd =
    string.format("%s %s %s %s", ctx.opts.cmd or "sass", ob.unq(args.cmdline) or "", ob.sh(in_file), ob.sh(out_file))
  return {
    steps = { { cmd = cmd } },
    convert = function()
      if file then
        return nil
      end
      return ob.read(out_file) or ""
    end,
  }
end

return M
