---@mod org.babel.lang.octave Octave and MATLAB blocks (ob-octave)
---
--- Blocks run in a new process (`org-babel-octave-evaluate-external-process`):
--- the code is fed to `cmd` ("octave -q", "matlab -nosplash") on stdin.

local ob = require("org.babel.ob")
local lisp = require("org.babel.lisp")

local M = {}

-- org-babel-octave-wrapper-method
local WRAPPER = "%s\nif ischar(ans), fid = fopen('%s', 'w'); fdisp(fid, ans); fclose(fid);\n"
  .. "else, dlmwrite('%s', ans, '\\t')\nend"

--- `org-babel-octave-var-to-octave`
function M.var_to_octave(v)
  if lisp.is_list(v) then
    local parts = {}
    for i, x in ipairs(v) do
      parts[i] = M.var_to_octave(x)
    end
    return "[" .. table.concat(parts, lisp.is_list(v[1]) and "; " or ",") .. "]"
  elseif type(v) == "string" then
    return "'" .. v .. "'"
  end
  return lisp.princ(v)
end

--- `org-babel-variable-assignments:octave`
local function var_lines(vars)
  local out = {}
  for i, v in ipairs(vars) do
    out[i] = string.format("%s=%s;", v.name, M.var_to_octave(v.value))
  end
  return out
end

--- The expanded body (C-c C-v v): the generic expansion with the
--- assignments.
function M.expand(body, args, vars)
  return ob.expand_generic(type(body) == "table" and body or { body }, args, var_lines(vars))
end

--- `org-babel-octave-import-elisp-from-file`: the file without its first
--- blank and comment lines, read as a tab-separated table.
function M.import(text)
  local lines = vim.split(text, "\n", { plain = true })
  local first
  for i, l in ipairs(lines) do
    if l:match("^[ \t]*[^# \t]") then
      first = i
      break
    end
  end
  if first then
    text = table.concat(vim.list_slice(lines, first), "\n")
  end
  return lisp.import_table(text, "tab")
end

local warned = {}

function M.prepare(body, args, vars, ctx)
  local session = ob.unq(args.session)
  if session and session ~= "none" and not warned[ctx.lang] then
    -- Emacs: an inferior Octave (or matlab-shell) buffer
    warned[ctx.lang] = true
    require("org.utils").warn(string.format("babel: %s has no session support; ignoring :session", ctx.lang))
  end
  local full = M.expand(body, args, vars)
  local ok, gfx = pcall(ob.graphical_output_file, args)
  gfx = ok and gfx or nil
  if gfx then
    full = table.concat({
      'set (0, "defaultfigurevisible", "off");',
      full,
      string.format("print -dpng %s\nans=%s", lisp.prin1(gfx), lisp.prin1(gfx)),
    }, "\n")
  end
  local cmd = ctx.opts.cmd or (ctx.lang == "matlab" and "matlab -nosplash" or "octave -q")
  local value = (args.results_spec or {}).collection ~= "output"
  local tmp
  local stdin = full
  if value then
    tmp = ob.temp()
    local name = vim.fs.normalize(tmp)
    stdin = WRAPPER:format(full, name, name)
  end
  return {
    steps = { { cmd = cmd, stdin = stdin } },
    convert = function(raw)
      if gfx then
        return nil
      end
      if not value then
        return raw
      end
      return M.import(ob.read(tmp) or "")
    end,
  }
end

return M
