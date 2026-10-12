---@mod org.table.calc_alg.integ integ
---
--- Integrals (integ): common integrals, not Calc's rule-based integrator.
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
local call = A.call
local same = A.same
local is_zero = A.is_zero
local isop = A.isop
local is_call = A.is_call
local normalize = A.normalize
local map_children = A.map_children
local contains = A.contains
local subst = A.subst
local to_radians = A.to_radians
local from_radians = A.from_radians
local fn = A.fn
local simplify = A.simplify
local expand = A.expand
local is_polynomial = A.is_polynomial
local derivative = A.derivative

--- `u` as a * var + b with a, b free of var, or nil.
local function linear(u, var)
  -- exact coefficients (x / 2 is 1:2 x), as Calc's integrator finds them
  local modes = K.modes()
  local saved = modes.frac
  modes.frac = true
  local ok, p = pcall(is_polynomial, u, var, 1, false, var)
  modes.frac = saved
  if not ok then
    error(p, 0)
  end
  if p and #p == 2 and not contains(p[2], var) and not contains(p[1], var) then
    return p[2], p[1]
  end
  return nil
end

local integral

--- An integral by parts for (polynomial in var) * f with f easy to
--- integrate repeatedly (exp, sin, cos of a linear argument).
local function by_parts(p, f, var, depth)
  if depth > 8 then
    return nil
  end
  local fi = integral(f, var, depth + 1)
  if not fi then
    return nil
  end
  local dp = normalize(derivative(p, var))
  if is_zero(dp) then
    return mul(p, fi)
  end
  local rest = integral(mul(dp, fi), var, depth + 1)
  return rest and expand(sub(mul(p, fi), rest))
end

--- The antiderivative of `e` in `var`, or nil when it isn't known.
integral = function(e, var, depth)
  depth = depth or 0
  if depth > 12 then
    return nil
  end
  if not contains(e, var) then
    return mul(e, var)
  elseif same(e, var) then
    return div(pow(var, 2), 2)
  end
  local t = tag(e)
  if t == "op" and (e.op == "+" or e.op == "-") then
    local a, b = integral(e.a, var, depth), integral(e.b, var, depth)
    return a and b and (e.op == "+" and add(a, b) or sub(a, b))
  elseif t == "neg" then
    local a = integral(e.a, var, depth)
    return a and neg(a)
  elseif t == "op" and e.op == "*" then
    if not contains(e.a, var) then
      local r = integral(e.b, var, depth)
      return r and mul(e.a, r)
    elseif not contains(e.b, var) then
      local r = integral(e.a, var, depth)
      return r and mul(r, e.b)
    end
    -- polynomial times exp/sin/cos: by parts
    for _, pair in ipairs({ { e.a, e.b }, { e.b, e.a } }) do
      local p, f = pair[1], pair[2]
      if is_polynomial(p, var, 10, false, var) and tag(f) == "call" and #f.args == 1 then
        local nm = f.name
        if (nm == "exp" or nm == "sin" or nm == "cos") and linear(f.args[1], var) then
          local r = by_parts(p, f, var, depth)
          if r then
            return r
          end
        end
      end
    end
    local ex = expand(e)
    if not same(ex, e) then
      return integral(ex, var, depth + 1)
    end
    return nil
  elseif t == "op" and e.op == "/" then
    if not contains(e.b, var) then
      local r = integral(e.a, var, depth)
      return r and div(r, e.b)
    elseif not contains(e.a, var) then
      local den = e.b
      local a = linear(den, var)
      if a then
        -- c / (a x + b)
        return mul(e.a, div(fn("ln", den), a))
      end
      a = is_call(den, "sqrt") and linear(den.args[1], var)
      if a then
        -- c / sqrt(a x + b)
        return mul(e.a, div(mul(2, den), a))
      end
      local p = is_polynomial(den, var, 2, false, var)
      if p and #p == 3 and K.equal_int(p[3], 1) and K.equal_int(p[1], 1) and is_zero(p[2]) then
        -- c / (x^2 + 1)
        return mul(e.a, to_radians(fn("arctan", var)))
      end
      return integral(pow(den, -1), var, depth + 1)
    end
    return nil
  elseif t == "op" and e.op == "^" then
    local base, n = e.a, e.b
    if not contains(n, var) then
      local a = linear(base, var)
      if a then
        if K.equal_int(n, -1) then
          return div(fn("ln", base), a)
        end
        local n1 = add(n, 1)
        return div(pow(base, n1), mul(a, n1))
      end
      if isop(base, "+", "-") and type(n) == "number" and n > 1 then
        return integral(expand(e), var, depth + 1)
      end
    elseif not contains(base, var) then
      local a = linear(n, var)
      if a then
        -- c^(a x + b)
        return div(e, mul(a, fn("ln", base)))
      end
    end
    return nil
  elseif t == "call" and #e.args == 1 then
    local u = e.args[1]
    local a = linear(u, var)
    if not a then
      return nil
    end
    local nm = e.name
    local r
    if nm == "exp" then
      r = e
    elseif nm == "sin" then
      r = from_radians(neg(fn("cos", u)))
    elseif nm == "cos" then
      r = from_radians(fn("sin", u))
    elseif nm == "tan" then
      r = from_radians(fn("ln", fn("sec", u)))
    elseif nm == "sinh" then
      r = fn("cosh", u)
    elseif nm == "cosh" then
      r = fn("sinh", u)
    elseif nm == "ln" then
      r = sub(mul(u, e), u)
    elseif nm == "sqrt" then
      r = mul(K.make_frac(2, 3), call("sqrt", { pow(u, 3) }))
    else
      return nil
    end
    return K.equal_int(a, 1) and r or div(r, a)
  end
  return nil
end

--- calcFunc-integ: split sums and constant factors, then integrate.
local function integ(expr, var, low, high)
  local function again(x)
    return integ(x, var, low, high)
  end
  if isop(expr, "+") then
    return add(again(expr.a), again(expr.b))
  elseif isop(expr, "-") then
    return sub(again(expr.a), again(expr.b))
  elseif tag(expr) == "neg" then
    return neg(again(expr.a))
  elseif isop(expr, "*") and not contains(expr.a, var) then
    return mul(expr.a, again(expr.b))
  elseif isop(expr, "*") and not contains(expr.b, var) then
    return mul(again(expr.a), expr.b)
  elseif isop(expr, "/") and not contains(expr.a, var) and not K.equal_int(expr.a, 1) then
    return mul(expr.a, again(div(1, expr.b)))
  elseif isop(expr, "/") and not contains(expr.b, var) then
    return div(again(expr.a), expr.b)
  elseif tag(expr) == "vec" then
    return map_children(expr, again)
  end
  local res = integral(expr, var)
  if res == nil then
    local args = { expr, var, low, high }
    return call("integ", args)
  end
  if low ~= nil and high ~= nil then
    return simplify(sub(subst(res, var, high), subst(res, var, low)))
  elseif low ~= nil then
    return simplify(subst(res, var, low))
  end
  return simplify(res)
end

F.integ = function(args)
  if #args < 2 or #args > 4 or tag(args[2]) ~= "sym" then
    return call("integ", args)
  end
  return integ(args[1], args[2], args[3], args[4])
end
