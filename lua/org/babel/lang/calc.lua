---@mod org.babel.lang.calc Calc blocks (ob-calc)
---
--- Emacs runs each line on the Calc stack of *Calculator*: a line naming a
--- `:var` pushes its value, a line starting with `'` runs that Calc key on
--- the stack (`'+`, `'*`, `'n`, `'Q`, ...), any other line is a formula
--- whose value is pushed (the variables are replaced by their values).
--- The result is the top of the stack. Here the formulas run on the Calc
--- port of table formulas (org.table.calc) with calc-eval's default modes:
--- 12 digits, full float display, degrees, no fraction mode.

local ob = require("org.babel.ob")
local lisp = require("org.babel.lisp")

local M = {}

--- `org-babel-expand-body:calc`: :prologue and :epilogue around the body.
function M.expand(body, args)
  local prologue, epilogue = ob.unq(args.prologue), ob.unq(args.epilogue)
  return (prologue and (prologue .. "\n") or "")
    .. ob.body_text(body)
    .. (epilogue and ("\n" .. epilogue .. "\n") or "")
end

local OPTS = { prec = 12, float_format = { "float", 0 }, deg = true, frac = false }

local function val(v)
  return { k = "val", v = v }
end

local function bin(o)
  return function(a, b)
    return { k = "bin", op = o, a = val(a), b = val(b) }
  end
end

local function fn1(name)
  return function(a)
    return { k = "call", name = name, args = { val(a) } }
  end
end

local function fn2(name)
  return function(a, b)
    return { k = "call", name = name, args = { val(a), val(b) } }
  end
end

--- Keys of calc-mode-map a `'KEY` line runs: their arity and the formula
--- they build from the popped values.
local KEYS = {
  ["+"] = { 2, bin("+") },
  ["-"] = { 2, bin("-") },
  ["*"] = { 2, bin("*") },
  ["/"] = { 2, bin("/") },
  ["^"] = { 2, bin("^") },
  ["%"] = { 2, bin("%") },
  ["\\"] = { 2, bin("\\") },
  ["|"] = { 2, bin("|") },
  [":"] = { 2, fn2("fdiv") },
  B = { 2, fn2("log") },
  n = {
    1,
    function(a)
      return { k = "neg", a = val(a) }
    end,
  },
  ["&"] = {
    1,
    function(a)
      return { k = "bin", op = "/", a = { k = "val", v = 1 }, b = val(a) }
    end,
  },
  Q = { 1, fn1("sqrt") },
  L = { 1, fn1("ln") },
  E = { 1, fn1("exp") },
  S = { 1, fn1("sin") },
  C = { 1, fn1("cos") },
  T = { 1, fn1("tan") },
  A = { 1, fn1("abs") },
  F = { 1, fn1("floor") },
  R = { 1, fn1("round") },
  ["!"] = { 1, fn1("fact") },
  -- calc-pi in the default (not symbolic) mode
  P = {
    0,
    function()
      return require("org.table.calc").parse("3.14159265359")
    end,
  },
}

--- A Babel value as a Calc value: numbers and formulas as Calc reads them,
--- a table as a matrix (one row: a vector), a list as a vector.
local function to_calc(api, calc, v)
  if lisp.is_list(v) then
    local rows = v
    if #v == 1 and lisp.is_list(v[1]) then
      rows = v[1]
    end
    local out = { tag = "vec" }
    for i, x in ipairs(rows) do
      out[i] = to_calc(api, calc, x)
    end
    return out
  end
  local text = type(v) == "string" and v or lisp.princ(v)
  local ok, res = pcall(function()
    return api.eval(calc.parse(text))
  end)
  if ok then
    return res
  end
  return api.eval({ k = "sym", name = text })
end

--- The formula `node` with the variables of `values` replaced.
local function subst(node, values)
  if type(node) ~= "table" then
    return node
  end
  if node.k == "sym" and values[node.name] ~= nil then
    return val(values[node.name])
  end
  if node.k == "val" then
    return node
  end
  local out = {}
  for k, x in pairs(node) do
    out[k] = type(x) == "table" and subst(x, values) or x
  end
  return out
end

--- Run the lines of `text` on a new stack; returns the top value (nil
--- for an empty stack) as a Babel result.
function M.evaluate(text, args, vars)
  local calc = require("org.table.calc")
  return calc.with_values(OPTS, function(api)
    local values = {}
    for _, v in ipairs(vars or {}) do
      values[v.name] = to_calc(api, calc, v.value)
    end
    local stack = {}
    local function pop(n, line)
      if #stack < n then
        error(string.format('Calc error "Too few elements on stack" on input "%s"', line), 0)
      end
      local out = {}
      for i = n, 1, -1 do
        out[i] = table.remove(stack)
      end
      return out
    end
    for _, raw in ipairs(vim.split(text, "[\n\r]")) do
      local line = ob.trim(raw)
      if line ~= "" then
        if values[line] ~= nil then
          stack[#stack + 1] = values[line]
        elseif line:sub(1, 1) == "'" then
          local key = KEYS[line:sub(2)]
          if not key then
            error(string.format('Calc error "Unsupported stack operation" on input "%s"', line), 0)
          end
          local popped = pop(key[1], line)
          stack[#stack + 1] = api.eval(key[2](unpack(popped, 1, key[1])))
        else
          local ok, res = pcall(function()
            return api.eval(subst(calc.parse(line), values))
          end)
          if not ok then
            error(string.format('Calc error "%s" on input "%s"', tostring(res), line), 0)
          end
          stack[#stack + 1] = res
        end
      end
    end
    local top = stack[#stack]
    if top == nil then
      return nil
    end
    if api.tag(top) ~= "vec" or require("org.babel.langs").scalar_result(args) then
      return api.display(top)
    end
    -- a matrix gives its rows, another vector one row
    local matrix = #top > 0
    for _, x in ipairs(top) do
      if api.tag(x) ~= "vec" then
        matrix = false
      end
    end
    local rows = {}
    for _, r in ipairs(matrix and top or { top }) do
      local cells = {}
      for i, x in ipairs(r) do
        cells[i] = api.display(x)
      end
      rows[#rows + 1] = cells
    end
    return rows
  end)
end

function M.prepare(body, args, vars)
  return { value = M.evaluate(M.expand(body, args), args, vars) }
end

return M
