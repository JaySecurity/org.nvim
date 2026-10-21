---@mod org.babel.lang.forth Forth blocks (ob-forth)
---
--- Emacs sends each line of the block to a gforth session (forth-mode) and
--- collects what each line printed before gforth said "ok"; a line that
--- leaves a definition open ("compiled") gives nothing. Here the lines run
--- in a new gforth process (`cmd`), each followed by a marker word that
--- prints only when gforth is interpreting again, so the output is split
--- by line the same way.

local ob = require("org.babel.ob")

local M = {}

local MARK = "org-babel-mark"
local TAG = "<<org-babel-forth-line "

--- `org-babel-expand-body:generic` without variables.
function M.expand(body, args)
  return ob.expand_generic(type(body) == "table" and body or { body }, args, {})
end

--- The lines Emacs sends: the trimmed expansion, empty lines dropped.
function M.lines(body, args)
  local out = {}
  for _, l in ipairs(vim.split(ob.trim(M.expand(body, args)), "\n", { plain = true })) do
    if l ~= "" then
      out[#out + 1] = l
    end
  end
  return out
end

--- The script given to gforth.
function M.script(lines)
  local out = {
    string.format(
      ': %s ( "n" -- ) parse-name state @ 0= if cr ." %s" type ." >>" cr else 2drop then ; immediate',
      MARK,
      TAG
    ),
  }
  for i, l in ipairs(lines) do
    out[#out + 1] = l
    out[#out + 1] = MARK .. " " .. i
  end
  out[#out + 1] = "bye"
  return table.concat(out, "\n") .. "\n"
end

--- The output of each line (nil for a line that left a definition open)
--- from what gforth printed.
function M.split(raw, n)
  local results = {}
  local pos = 1
  while true do
    local s, e, i = raw:find("\n" .. vim.pesc(TAG) .. "(%d+)>>\n?", pos)
    if not s then
      break
    end
    results[tonumber(i)] = raw:sub(pos, s - 1)
    pos = e + 1
  end
  local all = {}
  for i = 1, n do
    all[i] = results[i] or false
  end
  return all
end

function M.prepare(body, args, _, ctx)
  if ob.unq(args.session) == "none" then
    error("Non-session evaluation not supported for Forth code blocks", 0)
  end
  local lines = M.lines(body, args)
  local file = ob.write(ob.temp(".fs"), M.script(lines))
  return {
    steps = { { cmd = string.format("%s %s", ctx.opts.cmd or "gforth", ob.sh(file)), stdin = "" } },
    convert = function(raw)
      local all = M.split(raw:gsub("\r\n", "\n"), #lines)
      if args.results_spec.collection == "output" then
        local parts = {}
        for i, r in ipairs(all) do
          parts[i] = r or ""
        end
        return table.concat(parts, "\n")
      end
      return all[#all] or nil
    end,
  }
end

return M
