---@mod org.table.calc_alg.solve solve (math-try-solve-for)
---
--- solve: linear and quadratic (up to quartic) polynomials and inverse
--- functions; one solution, as Calc without the "all solutions" flag.
--- Part of org.table.calc_alg, which loads it.

local A = require("org.table.calc_alg")

local K = A.K
local F = A.F
local tag = A.tag
local is_real = A.is_real
local is_int = A.is_int
local add = A.add
local sub = A.sub
local mul = A.mul
local div = A.div
local pow = A.pow
local neg = A.neg
local op = A.op
local sym = A.sym
local call = A.call
local same = A.same
local is_zero = A.is_zero
local negative = A.negative
local looks_neg = A.looks_neg
local is_number = A.is_number
local isop = A.isop
local is_call = A.is_call
local primitive = A.primitive
local normalize = A.normalize
local map_children = A.map_children
local contains = A.contains
local PI = A.PI
local sqr = A.sqr
local fn = A.fn
local simplify = A.simplify
local parts = A.parts
local is_polynomial = A.is_polynomial

-- the variable being solved for, and the direction of the solution for
-- inequalities (math-solve-sign: 1 same, -1 reversed, nil unknown)
local solve_var, solve_sign

--- math-solve-get-sign without "all solutions": the simplified value.
local function get_sign(val)
  val = simplify(val)
  if isop(val, "*") and is_number(val.a) then
    return op("*", val.a, get_sign(val.b))
  end
  if is_call(val, "sqrt") and isop(val.args[1], "^") then
    val = pow(val.args[1].a, div(val.args[1].b, 2))
  end
  return val
end

--- math-solve-sign: the direction after multiplying by `expr`.
local function sign_by(sign, expr)
  if sign == nil or not is_real(expr) then
    return nil
  elseif negative(expr) then
    return -sign
  end
  return not is_zero(expr) and sign or nil
end

local function looks_even(e)
  if is_int(e) then
    return type(e) == "number" and e % 2 == 0
  elseif isop(e, "*", "/") then
    return looks_even(e.a)
  end
  return false
end

local try_solve

local function integer_log2(n)
  local k = 0
  while n > 1 and n % 2 == 0 do
    n, k = n / 2, k + 1
  end
  return n == 1 and k > 0 and k or nil
end

-- Calc picks the arbitrary integers of general solutions as 0
-- (math-solve-get-int without "all solutions"), but keeps their terms
local function zero_term(scale)
  return mul(scale, 0)
end

local function try_solve_prod(lhs, rhs, sign)
  local var = solve_var
  if isop(lhs, "*") then
    if not contains(lhs.a, var) then
      return try_solve(lhs.b, div(rhs, lhs.a), sign_by(sign, lhs.a))
    elseif not contains(lhs.b, var) then
      return try_solve(lhs.a, div(rhs, lhs.b), sign_by(sign, lhs.b))
    elseif is_zero(rhs) then
      return try_solve(lhs.b, 0) or try_solve(lhs.a, 0)
    end
  elseif isop(lhs, "/") then
    if not contains(lhs.a, var) then
      return try_solve(lhs.b, div(lhs.a, rhs), sign_by(sign, lhs.a))
    elseif not contains(lhs.b, var) then
      return try_solve(lhs.a, mul(rhs, lhs.b), sign_by(sign, lhs.b))
    end
    return try_solve(sub(lhs.a, mul(lhs.b, rhs)), 0)
  elseif isop(lhs, "^") then
    local base, n = lhs.a, lhs.b
    if not contains(base, var) then
      local k = div(mul(2, mul(PI, zero_term(sym("i")))), fn("ln", base))
      return try_solve(n, add(fn("log", rhs, base), k))
    elseif not contains(n, var) then
      local k = type(n) == "number" and n >= 2 and integer_log2(n)
      if k then
        local t2 = rhs
        for _ = 1, k do
          t2 = get_sign(fn("sqrt", t2))
        end
        return try_solve(base, normalize(t2))
      elseif looks_neg(n) then
        return try_solve(op("^", base, neg(n)), div(1, rhs))
      end
      local odd = type(n) == "number" and n % 2 == 1
      local root = fn("exp", div(mul(PI, zero_term(sym("i"))), div(n, 2)))
      return try_solve(base, mul(root, fn("nroot", rhs, n)), odd and sign_by(sign, n) or nil)
    end
  end
  return nil
end

local contains_vars

--- math-decompose-poly: the sub-formula (the variable itself, 1/x, ...)
--- that `lhs` - `rhs` is a polynomial of, with its coefficients.
local function decompose_poly(lhs, rhs)
  local var = solve_var
  local found
  local function pred(b)
    if same(b, lhs) then
      return false
    end
    local p = is_polynomial(lhs, b, 50, false, var)
    if not p then
      return false
    end
    p[1] = sub(p[1], rhs)
    -- math-solve-crunch-poly: x^2 (a x^2 + b) = 0 and powers of x^k
    local count = 0
    while #p > 0 and is_zero(p[1]) do
      table.remove(p, 1)
      count = count + 1
    end
    if #p == 0 then
      return false
    end
    local degree = #p - 1
    local power = 1
    for scale = degree, 2, -1 do
      if power == 1 and degree % scale == 0 then
        local ok, new = true, {}
        for i, c in ipairs(p) do
          if (i - 1) % scale == 0 then
            new[#new + 1] = c
          elseif not is_zero(c) then
            ok = false
          end
        end
        if ok then
          power, p = scale, new
        end
      end
    end
    if #p - 1 > 15 or not (contains(b, var)) then
      return false
    end
    found = { base = pow(b, power), coefs = p, factor = pow(b, count) }
    return true
  end
  local function rec(e, const_ok)
    if K.is_objvec(e) then
      return false
    end
    if isop(e, "+", "-") or isop(e, "*") then
      if rec(e.a, const_ok) or rec(e.b, const_ok) then
        return true
      end
    elseif isop(e, "/") or tag(e) == "neg" or isop(e, "^") then
      if rec(e.a, const_ok) then
        return true
      end
    end
    return (const_ok or contains_vars(e)) and pred(e)
  end
  if rec(lhs, false) or rec(lhs, true) then
    return found
  end
  return nil
end

--- math-expr-contains-vars
contains_vars = function(e)
  local t = tag(e)
  if t == "sym" then
    return true
  elseif primitive(e) then
    return false
  end
  for _, x in ipairs(parts(e)) do
    if contains_vars(x) then
      return true
    end
  end
  return false
end

local function solve_quadratic(var, c, b, a)
  local val
  if looks_even(b) then
    local halfb = div(b, 2)
    val = div(add(neg(halfb), get_sign(fn("sqrt", add(sqr(halfb), mul(neg(c), a))))), a)
  else
    val = div(add(neg(b), get_sign(fn("sqrt", add(sqr(b), mul(4, mul(neg(c), a)))))), mul(2, a))
  end
  return try_solve(var, val, nil, true)
end

local function half_circle()
  return K.modes().deg and 180 or K.float(math.pi)
end

--- math-solve-cubic
local function solve_cubic(var, d, c, b, a)
  local p, q, r = div(b, a), div(c, a), div(d, a)
  local psqr = sqr(p)
  local aa = sub(q, div(psqr, 3))
  local bb = add(r, div(sub(mul(2, mul(psqr, p)), mul(9, mul(p, q))), 27))
  if is_zero(aa) then
    return try_solve(pow(add(var, div(p, 3)), 3), neg(bb), nil, true)
  elseif is_zero(bb) then
    local v = add(var, div(p, 3))
    return try_solve(mul(v, add(sqr(v), aa)), 0, nil, true)
  end
  local m = mul(2, call("sqrt", { div(aa, -3) }))
  local angle = sub(call("arccos", { div(mul(3, bb), mul(aa, m)) }), mul(2, mul(add(1, 0), half_circle())))
  local root = sub(normalize(mul(m, call("cos", { div(angle, 3) }))), div(p, 3))
  if tag(root) == "cplx" and is_real(root.re) and is_real(root.im) then
    -- a real root reached through complex numbers: drop the rounding
    -- noise left in its imaginary part
    local re, im = K.tofloat(root.re), K.tofloat(root.im)
    if math.abs(im) <= math.abs(re) * 10 ^ -(K.modes().prec - 2) then
      root = root.re
    end
  end
  return try_solve(var, root, nil, true)
end

--- math-solve-quartic
local function solve_quartic(var, d, c, b, a, aa)
  a, b, c, d = div(a, aa), div(b, aa), div(c, aa), div(d, aa)
  local asqr = sqr(a)
  local asqr4 = div(asqr, 4)
  local saved = solve_var
  local cd = sub(sub(mul(4, mul(b, d)), mul(asqr, d)), sqr(c))
  local y = solve_cubic(solve_var, cd, sub(mul(a, c), mul(4, d)), neg(b), 1)
  solve_var = saved
  if y == nil then
    return nil
  end
  local rsqr = add(sub(asqr4, b), y)
  local r = call("sqrt", { rsqr })
  local sign1 = get_sign(1)
  local de
  if is_zero(rsqr) then
    de = add(sub(mul(3, asqr4), mul(2, b)), mul(2, mul(sign1, call("sqrt", { sub(sqr(y), mul(4, d)) }))))
  else
    de = add(
      sub(mul(3, asqr4), mul(2, b)),
      sub(mul(sign1, div(sub(sub(mul(4, mul(a, b)), mul(8, c)), mul(asqr, a)), mul(4, r))), rsqr)
    )
  end
  de = call("sqrt", { de })
  local val = normalize(sub(add(mul(sign1, div(r, 2)), get_sign(div(de, 2))), div(a, 4)))
  return try_solve(var, val, nil, true)
end

-- the inverse of functions of one argument (math-inverse), and whether
-- they keep (1) or reverse (-1) the order (math-inverse-sign)
local INVERSE = {
  sqrt = function(x)
    return sqr(x)
  end,
  ln = function(x)
    return call("exp", { x })
  end,
  log10 = function(x)
    return call("exp10", { x })
  end,
  exp = function(x)
    return add(fn("ln", x), mul(2, mul(PI, zero_term(sym("i")))))
  end,
  sin = function(x)
    local n = 0
    return add(mul(fn("arcsin", x), pow(-1, n)), mul(half_circle(), n))
  end,
  cos = function(x)
    return add(get_sign(fn("arccos", x)), zero_term(mul(2, half_circle())))
  end,
  tan = function(x)
    return add(fn("arctan", x), zero_term(half_circle()))
  end,
  arcsin = function(x)
    return fn("sin", x)
  end,
  arccos = function(x)
    return fn("cos", x)
  end,
  arctan = function(x)
    return fn("tan", x)
  end,
  sinh = function(x)
    return fn("arcsinh", x)
  end,
  cosh = function(x)
    return get_sign(fn("arccosh", x))
  end,
  tanh = function(x)
    return fn("arctanh", x)
  end,
  arcsinh = function(x)
    return fn("sinh", x)
  end,
  arccosh = function(x)
    return fn("cosh", x)
  end,
  arctanh = function(x)
    return fn("tanh", x)
  end,
  abs = function(x)
    return get_sign(x)
  end,
  deg = function(x)
    return call("rad", { x })
  end,
  rad = function(x)
    return call("deg", { x })
  end,
  inv = function(x)
    return div(1, x)
  end,
}
local INVERSE_SIGN = {
  ln = 1,
  log10 = 1,
  exp = 1,
  deg = 1,
  rad = 1,
  sinh = 1,
  tanh = 1,
  arcsinh = 1,
  arctanh = 1,
  inv = -1,
}

try_solve = function(lhs, rhs, sign, no_poly)
  local var = solve_var
  if same(lhs, var) then
    solve_sign = sign
    return rhs
  elseif primitive(lhs) then
    return nil
  elseif tag(lhs) == "neg" then
    return try_solve(lhs.a, neg(rhs), sign and -sign)
  end
  local r = try_solve_prod(lhs, rhs, sign)
  if r ~= nil then
    return r
  end
  if not no_poly then
    local d = decompose_poly(lhs, rhs)
    if d then
      local p = d.coefs
      if #p == 5 then
        r = solve_quartic(d.base, p[1], p[2], p[3], p[4], p[5])
      elseif #p == 4 then
        r = solve_cubic(d.base, p[1], p[2], p[3], p[4])
      elseif #p == 3 then
        r = solve_quadratic(d.base, p[1], p[2], p[3])
      elseif #p == 2 then
        r = try_solve(d.base, div(neg(p[1]), p[2]), sign_by(sign, p[2]), true)
      elseif #p == 1 and not K.equal_int(d.factor, 1) then
        r = try_solve(d.factor, 0, nil, true)
      end
      -- (a polynomial of degree 5 or more: Calc finds a root numerically)
      return r
    end
  end
  if isop(lhs, "+") then
    if not contains(lhs.a, var) then
      return try_solve(lhs.b, sub(rhs, lhs.a), sign)
    elseif not contains(lhs.b, var) then
      return try_solve(lhs.a, sub(rhs, lhs.b), sign)
    end
  elseif isop(lhs, "==") then
    return try_solve(sub(lhs.a, lhs.b), rhs, sign, no_poly)
  elseif isop(lhs, "-") then
    if not contains(lhs.a, var) then
      return try_solve(lhs.b, sub(lhs.a, rhs), sign and -sign)
    elseif not contains(lhs.b, var) then
      return try_solve(lhs.a, add(rhs, lhs.b), sign)
    end
  elseif tag(lhs) == "call" and lhs.name == "log" and #lhs.args == 2 then
    if not contains(lhs.args[2], var) then
      return try_solve(lhs.args[1], pow(lhs.args[2], rhs))
    elseif not contains(lhs.args[1], var) then
      return try_solve(lhs.args[2], pow(lhs.args[1], div(1, rhs)))
    end
  elseif tag(lhs) == "call" and #lhs.args == 1 and INVERSE[lhs.name] then
    local s = INVERSE_SIGN[lhs.name]
    return try_solve(lhs.args[1], normalize(INVERSE[lhs.name](rhs)), sign and s and sign * s)
  end
  return nil
end

--- The floats of a formula rounded to the working precision.
local function round_floats(v)
  local t = tag(v)
  if t == "float" then
    return K.float(v.v)
  elseif t == "cplx" then
    return { tag = "cplx", re = round_floats(v.re), im = round_floats(v.im) }
  elseif primitive(v) then
    return v
  end
  return map_children(v, round_floats)
end

--- math-solve-for: lhs = rhs for var, or nil.
local function solve_for(lhs, rhs, var, sign)
  if contains(rhs, var) then
    return solve_for(sub(lhs, rhs), 0, var, sign)
  elseif not contains(lhs, var) then
    return nil
  end
  local saved = solve_var
  solve_var, solve_sign = var, nil
  -- extra working precision, as Calc's solver and its functions use
  local modes = K.modes()
  local prec = modes.prec
  modes.prec = prec + 3
  local ok, r = pcall(try_solve, lhs, rhs, sign)
  modes.prec = prec
  solve_var = saved
  if not ok then
    error(r, 0)
  end
  return r and round_floats(r)
end

local INEQ = { ["<"] = true, [">"] = true, ["<="] = true, [">="] = true, ["!="] = true }

--- math-solve-eqn: an equation `var = solution`, or an inequality with
--- the variable on the side it ends up on.
local function solve_eqn(expr, var)
  if tag(expr) == "op" and INEQ[expr.op] then
    local res = solve_for(op("-", expr.a, expr.b), 0, var, expr.op ~= "!=" and 1 or nil)
    if res == nil then
      return nil
    elseif solve_sign == 1 then
      return op(expr.op, var, res)
    elseif solve_sign == -1 then
      return op(expr.op, res, var)
    elseif expr.op == "!=" or expr.op == "<" or expr.op == ">" then
      return op("!=", var, res)
    end
    return nil
  end
  local res = solve_for(expr, 0, var)
  return res ~= nil and op("==", var, res) or nil
end

F.solve = function(args)
  local expr, var = args[1], args[2]
  if #args ~= 2 or tag(var) ~= "sym" or tag(expr) == "vec" then
    return call("solve", args)
  end
  return solve_eqn(expr, var) or call("solve", args)
end
