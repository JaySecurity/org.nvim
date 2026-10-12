---@mod org.table.calc_alg.deriv deriv (math-derivative)
---
--- Derivatives (deriv).
--- Part of org.table.calc_alg, which loads it.

local A = require("org.table.calc_alg")

local K = A.K
local F = A.F
local tag = A.tag
local add = A.add
local sub = A.sub
local mul = A.mul
local div = A.div
local pow = A.pow
local neg = A.neg
local op = A.op
local call = A.call
local same = A.same
local is_zero = A.is_zero
local is_object = A.is_object
local COMPARE = A.COMPARE
local normalize = A.normalize
local map_children = A.map_children
local subst = A.subst
local to_radians = A.to_radians
local from_radians = A.from_radians
local sqr = A.sqr
local fn = A.fn

-- derivatives of functions of one argument (the `f'` handlers)
local DERIV = {
  sqrt = function(u)
    return div(1, mul(2, call("sqrt", { u })))
  end,
  ln = function(u)
    return div(1, u)
  end,
  log10 = function(u)
    return div(div(1, fn("ln", 10)), u)
  end,
  exp = function(u)
    return fn("exp", u)
  end,
  sin = function(u)
    return to_radians(fn("cos", u))
  end,
  cos = function(u)
    return neg(to_radians(fn("sin", u)))
  end,
  tan = function(u)
    return to_radians(sqr(fn("sec", u)))
  end,
  sec = function(u)
    return to_radians(mul(fn("sec", u), fn("tan", u)))
  end,
  csc = function(u)
    return neg(to_radians(mul(fn("csc", u), fn("cot", u))))
  end,
  cot = function(u)
    return neg(to_radians(sqr(fn("csc", u))))
  end,
  arcsin = function(u)
    return from_radians(div(1, fn("sqrt", sub(1, sqr(u)))))
  end,
  arccos = function(u)
    return from_radians(div(-1, fn("sqrt", sub(1, sqr(u)))))
  end,
  arctan = function(u)
    return from_radians(div(1, add(1, sqr(u))))
  end,
  sinh = function(u)
    return fn("cosh", u)
  end,
  cosh = function(u)
    return fn("sinh", u)
  end,
  tanh = function(u)
    return sqr(fn("sech", u))
  end,
  arcsinh = function(u)
    return div(1, fn("sqrt", add(sqr(u), 1)))
  end,
  arccosh = function(u)
    return div(1, fn("sqrt", add(sqr(u), -1)))
  end,
  arctanh = function(u)
    return div(1, sub(1, sqr(u)))
  end,
  deg = function()
    return div(K.float(180), K.float(math.pi))
  end,
  rad = function()
    return K.float(math.pi / 180)
  end,
  inv = function(u)
    return neg(div(1, sqr(u)))
  end,
}

local function derivative(expr, var)
  local function d(e)
    if same(e, var) then
      return 1
    end
    local t = tag(e)
    if is_object(e) or t == "sym" then
      return 0
    elseif t == "op" then
      local o = e.op
      if o == "+" then
        return add(d(e.a), d(e.b))
      elseif o == "-" then
        return sub(d(e.a), d(e.b))
      elseif COMPARE[o] then
        return op(o, d(e.a), d(e.b))
      elseif o == "*" then
        return add(mul(e.b, d(e.a)), mul(e.a, d(e.b)))
      elseif o == "/" then
        return sub(div(d(e.a), e.b), div(mul(e.a, d(e.b)), sqr(e.b)))
      elseif o == "^" then
        local du, dv = d(e.a), d(e.b)
        if not is_zero(du) then
          du = mul(e.b, mul(pow(e.a, add(e.b, -1)), du))
        end
        if not is_zero(dv) then
          dv = mul(fn("ln", e.a), mul(e, dv))
        end
        return add(du, dv)
      elseif o == "%" then
        return d(e.a)
      end
    elseif t == "neg" then
      return neg(d(e.a))
    elseif t == "vec" then
      return map_children(e, d)
    elseif t == "call" then
      if e.name == "re" or e.name == "im" or e.name == "conj" then
        return call(e.name, { d(e.args[1]) })
      end
      -- the sum of the partial derivatives, `f'(x)` for unknown ones
      local accum = 0
      for i, arg in ipairs(e.args) do
        local dv = d(arg)
        if not is_zero(dv) then
          local h = #e.args == 1 and DERIV[e.name]
          local fd = h and h(arg) or call(e.name .. "'" .. (i > 1 and tostring(i) or ""), e.args)
          accum = add(accum, mul(dv, fd))
        end
      end
      return accum
    end
    return call("deriv", { e, var })
  end
  return d(expr)
end

F.deriv = function(args)
  local expr, var, value = args[1], args[2], args[3]
  if #args < 2 or #args > 3 then
    return call("deriv", args)
  end
  local res = normalize(derivative(expr, var))
  if value ~= nil then
    return subst(res, var, value)
  end
  return res
end

A.derivative = derivative
