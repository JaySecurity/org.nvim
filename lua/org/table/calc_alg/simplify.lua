---@mod org.table.calc_alg.simplify Calc's simplify (math-simplify)
---
--- simplify (math-simplify and its rules for + - * / ^, sqrt, exp,
--- trigonometric functions and equations) and subst.
--- Part of org.table.calc_alg, which loads it.

local A = require("org.table.calc_alg")

--- A formula node of org.table.calc (an operator and its operands).
---@class calc.Node
---@field tag string
---@field op? string
---@field a any
---@field b any

local K = A.K
local F = A.F
local tag = A.tag
local is_real = A.is_real
local is_int = A.is_int
local add = A.add
local sub = A.sub
local mul = A.mul
local div = A.div
local neg = A.neg
local call = A.call
local same = A.same
local is_zero = A.is_zero
local negative = A.negative
local looks_neg = A.looks_neg
local is_object = A.is_object
local is_number = A.is_number
local isop = A.isop
local is_call = A.is_call
local primitive = A.primitive
local is_rat = A.is_rat
local COMPARE = A.COMPARE
local normalize = A.normalize
local map_children = A.map_children
local contains = A.contains
local subst = A.subst
local simplifying = A.simplifying

-- A settable reference to a sub-formula (a cons cell in Calc): the field
-- `k` of the node `t`.
local function cell(t, k)
  return {
    get = function()
      return t[k]
    end,
    set = function(v)
      t[k] = v
    end,
  }
end

-- the Calc symbol of a node, for the canonical order of math-beforep
local HEAD = { ["=="] = "calcFunc-eq", ["!="] = "calcFunc-neq", ["<"] = "calcFunc-lt", [">"] = "calcFunc-gt" }
HEAD["<="], HEAD[">="], HEAD["&&"], HEAD["||"] = "calcFunc-leq", "calcFunc-geq", "calcFunc-land", "calcFunc-lor"
local function head(v)
  local t = tag(v)
  if t == "op" then
    return HEAD[v.op] or v.op
  elseif t == "call" then
    return "calcFunc-" .. v.name
  end
  return t
end
local function parts(v)
  local t = tag(v)
  if t == "op" then
    return { v.a, v.b }
  elseif t == "neg" then
    return { v.a }
  elseif t == "call" then
    return v.args
  elseif t == "vec" then
    return v
  end
  return {}
end

--- math-beforep: the canonical order of terms and factors.
local function beforep(a, b)
  if is_real(a) and is_real(b) then
    local c = K.num_cmp(a, b)
    local rank = { int = 3, big = 3, frac = 2, float = 1 }
    return c < 0 or (c == 0 and not same(a, b) and rank[tag(a)] > rank[tag(b)])
  elseif is_real(a) then
    return true
  elseif is_real(b) then
    return false
  elseif (is_object(a) or false) ~= (is_object(b) or false) then
    return is_object(a) and true or false
  elseif tag(a) == "sym" then
    if tag(b) == "sym" then
      return a.name < b.name
    end
    return not is_number(b)
  elseif tag(b) == "sym" then
    return is_number(a)
  elseif head(a) == head(b) then
    local pa, pb = parts(a), parts(b)
    local i = 1
    while pb[i] ~= nil and pa[i] ~= nil and same(pa[i], pb[i]) do
      i = i + 1
    end
    return pb[i] ~= nil and (pa[i] == nil or beforep(pa[i], pb[i]))
  end
  return head(a) < head(b)
end

--- math-to-simple-fraction
local function simple_fraction(v)
  if tag(v) == "float" then
    local x = v.v
    if x == math.floor(x) and math.abs(x) < 2 ^ 53 then
      return x
    end
    for d = 1, 3 do
      local n = x * 10 ^ d
      if math.abs(n - math.floor(n + 0.5)) < 1e-9 and math.abs(n) < 1000 then
        return K.make_frac(math.floor(n + 0.5), 10 ^ d)
      end
    end
  end
  return v
end

local function frac_parts(v)
  if tag(v) == "frac" then
    return v.n, v.d
  end
  return v, 1
end

local function igcd(a, b)
  a, b = math.abs(a), math.abs(b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

--- math-frac-gcd
local function frac_gcd(a, b)
  if is_zero(a) then
    return b
  elseif is_zero(b) then
    return a
  elseif type(a) == "number" and type(b) == "number" then
    return igcd(a, b)
  end
  local an, ad = frac_parts(a)
  local bn, bd = frac_parts(b)
  return K.make_frac(igcd(an, bn), igcd(ad, bd))
end

--- math-common-constant-factor: a rational factor of every term.
local function ccf(expr)
  if is_real(expr) then
    if is_rat(expr) then
      if expr == 0 or expr == 1 or expr == -1 then
        return nil
      end
      return negative(expr) and neg(expr) or expr
    end
    local r = simple_fraction(expr)
    return is_rat(r) and ccf(r) or nil
  end
  if isop(expr, "+", "-") then
    local f1, f2 = ccf(expr.a), ccf(expr.b)
    if f1 and f2 then
      local g = frac_gcd(f1, f2)
      return g ~= 1 and g or nil
    end
  elseif isop(expr, "*") then
    return ccf(expr.a)
  elseif isop(expr, "/") then
    return ccf(expr.a) or (is_int(expr.b) and K.make_frac(1, math.abs(expr.b))) or nil
  end
  return nil
end

--- math-cancel-common-factor
local function cancel(expr, val)
  if isop(expr, "+", "-") then
    expr.a = cancel(expr.a, val)
    expr.b = cancel(expr.b, val)
    return expr
  elseif isop(expr, "*") then
    return mul(cancel(expr.a, val), expr.b)
  end
  return div(expr, val)
end

--- math-possible-signs, for numbers only: 1 negative, 2 zero, 4 positive
--- (7: unknown).
local function signs(v)
  if is_real(v) then
    return negative(v) and 1 or (is_zero(v) and 2 or 4)
  end
  return 7
end

-- the relation after multiplying both sides by a negative number
local TWEAK = { ["=="] = "==", ["!="] = "!=", ["<"] = ">", [">"] = "<", ["<="] = ">=", [">="] = "<=" }

local simplify_divisor

local function simplify_one_divisor(expr, np, dp, nover, dover)
  local temp = K.combine_prod(np.get(), dp.get(), nover, dover, true)
  if temp ~= nil then
    if not (expr.op == "/" or expr.op == "==" or expr.op == "!=") and negative(dp.get()) and TWEAK[expr.op] then
      expr.op = TWEAK[expr.op]
    end
    np.set(nover and div(1, temp) or temp)
    dp.set(1)
  elseif dover and not nover and expr.op == "/" and is_call(dp.get(), "sqrt") and is_int(dp.get().args[1]) then
    local arg = dp.get().args[1]
    np.set(mul(np.get(), call("sqrt", { arg })))
    dp.set(arg)
  end
end

simplify_divisor = function(expr, np, dp, nover, dover)
  local d = dp.get()
  if isop(d, "/") then
    simplify_divisor(expr, np, cell(d, "a"), nover, dover)
    if K.known_scalar(d.a, true) then
      simplify_divisor(expr, np, cell(d, "b"), nover, not dover)
    end
    return
  end
  local s = signs(np.get())
  if expr.op == "/" or s == 1 or s == 4 or is_number(np.get()) then
    local safe, scalar = true, K.known_scalar(np.get())
    while isop(dp.get(), "*") and safe do
      d = dp.get()
      simplify_one_divisor(expr, np, cell(d, "a"), nover, dover)
      safe = scalar or K.known_scalar(d.a, true)
      dp = cell(d, "b")
    end
    if safe then
      simplify_one_divisor(expr, np, dp, nover, dover)
    end
  end
end

--- math-simplify-divide: cancel common factors of a quotient or of the
--- two sides of an equation.
local function simplify_divide(expr)
  local nn = (expr.op == "/" or not is_real(expr.b)) and ccf(expr.b)
  if nn then
    local n = (expr.op == "/" or not is_real(expr.a)) and ccf(expr.a)
    if tag(nn) == "frac" and nn.n == 1 and not n then
      if not (expr.op == "==" and tag(expr.a) == "sym" and not contains(expr.b, expr.a)) then
        expr.a = mul(nn.d, expr.a)
        expr.b = cancel(expr.b, nn)
      end
    elseif n then
      n = frac_gcd(n, nn)
      if n ~= 1 then
        expr.a = cancel(expr.a, n)
        expr.b = cancel(expr.b, n)
        if negative(n) and TWEAK[expr.op] then
          expr.op = TWEAK[expr.op]
        end
      end
    end
  end
  local np = cell(expr, "a")
  local nover = false
  if isop(np.get(), "/") and K.known_scalar(expr.b, true) then
    local num = expr.a
    np = cell(num, "a")
    while isop(np.get(), "*") do
      local n = np.get()
      if K.known_scalar(n.b, true) then
        simplify_divisor(expr, cell(n, "a"), cell(expr, "b"), false, true)
      end
      np = cell(n, "b")
    end
    simplify_divisor(expr, np, cell(expr, "b"), false, true)
    nover = true
    np = cell(num, "b")
  end
  while isop(np.get(), "*") do
    local n = np.get()
    if K.known_scalar(n.b, true) then
      simplify_divisor(expr, cell(n, "a"), cell(expr, "b"), nover, true)
    end
    np = cell(n, "b")
  end
  simplify_divisor(expr, np, cell(expr, "b"), nover, true)
  return expr
end

--- math-simplify-add-term: move a term of the left side of an equation
--- to the right one when they combine.
local function simplify_add_term(np, dp, minus, lplain)
  if tag(np.get()) == "vec" then
    return
  end
  local rplain = true
  local n, d = np.get(), dp.get()
  while isop(d, "+", "-") do
    rplain = false
    local temp = K.combine_sum(n, d.b, minus, d.op == "+", true)
    if temp ~= nil then
      if lplain or looks_neg(temp) == minus then
        np.set(minus and neg(temp) or temp)
        d.b = 0
      else
        np.set(0)
        d.b = d.op == "+" and neg(temp) or temp
      end
    end
    dp = cell(d, "a")
    n, d = np.get(), dp.get()
  end
  local temp = K.combine_sum(n, d, minus, true, true)
  if temp ~= nil then
    if lplain or (not rplain and looks_neg(temp) == minus) then
      np.set(minus and neg(temp) or temp)
      dp.set(0)
    else
      np.set(0)
      dp.set(neg(temp))
    end
  end
end

--- math-simplify-ineq: an equation or inequality.
local function simplify_ineq(expr)
  local np = cell(expr, "a")
  local plain = true
  while isop(np.get(), "+", "-") do
    local n = np.get()
    simplify_add_term(cell(n, "b"), cell(expr, "b"), n.op == "-", false)
    np = cell(n, "a")
    plain = false
  end
  simplify_add_term(np, cell(expr, "b"), false, plain)
  simplify_divide(expr)
  local s
  if is_real(expr.a) and is_real(expr.b) then
    s = signs(sub(expr.a, expr.b))
  elseif same(expr.a, expr.b) then
    s = 2
  else
    return expr
  end
  local o = expr.op
  local r
  if o == "==" then
    r = s == 2 and 1 or 0
  elseif o == "!=" then
    r = s == 2 and 0 or 1
  elseif o == "<" then
    r = s == 1 and 1 or 0
  elseif o == ">" then
    r = s == 4 and 1 or 0
  elseif o == "<=" then
    r = s == 4 and 0 or 1
  elseif o == ">=" then
    r = s == 1 and 0 or 1
  end
  return r or expr
end

local function simplify_addsub(expr)
  local a = expr.a
  if isop(a, "+", "-") and is_number(a.b) and not is_number(expr.b) then
    -- (u + 2) + x is (u + x) + 2
    local x, o = expr.b, expr.op
    expr.b, expr.op = a.b, a.op
    a.b, a.op = x, o
  elseif expr.op == "+" and is_number(expr.a) and not is_number(expr.b) then
    expr.a, expr.b = expr.b, expr.a
  end
  -- the node and its operand being walked down (formula nodes)
  ---@type calc.Node
  local aa = expr
  ---@type calc.Node
  local aaa = nil
  while true do
    aaa = aa.a
    if not isop(aaa, "+", "-") then
      break
    end
    local temp = K.combine_sum(aaa.b, expr.b, aaa.op == "-", expr.op == "-", true)
    if temp ~= nil then
      expr.b, expr.op = temp, "+"
      aaa.b = 0
    end
    aa = aa.a
  end
  local temp = K.combine_sum(aaa, expr.b, false, expr.op == "-", true)
  if temp ~= nil then
    expr.b, expr.op = temp, "+"
    aa.a = 0
  end
  return expr
end

local function simplify_mul(expr)
  local b = expr.b
  if isop(b, "*") then
    if beforep(b.a, expr.a) and (K.known_scalar(expr.a, true) or K.known_scalar(b.a, true)) then
      expr.a, b.a = b.a, expr.a
    end
  elseif beforep(expr.b, expr.a) and (K.known_scalar(expr.a, true) or K.known_scalar(expr.b, true)) then
    expr.a, expr.b = expr.b, expr.a
  end
  local safe, scalar = true, K.known_scalar(expr.a)
  if is_rat(expr.a) then
    local temp = ccf(expr.b)
    if temp then
      expr.b = cancel(expr.b, temp)
      expr.a = mul(expr.a, temp)
    end
  end
  -- the node and its operand being walked down (formula nodes)
  ---@type calc.Node
  local aa = expr
  ---@type calc.Node
  local aaa = nil
  while true do
    aaa = aa.b
    if not (isop(aaa, "*") and safe) then
      break
    end
    local temp = K.combine_prod(expr.a, aaa.a, false, false, true)
    if temp ~= nil then
      expr.a = temp
      aaa.a = 1
    end
    safe = scalar or K.known_scalar(aaa.a, true)
    aa = aa.b
  end
  local temp = K.combine_prod(aaa, expr.a, false, false, true)
  if temp ~= nil and safe then
    expr.a = temp
    aa.b = 1
  end
  local f = expr.a
  if tag(f) == "frac" and (f.n == 1 or f.n == -1) then
    return div(mul(expr.b, f.n), f.d)
  end
  return expr
end

--- math-squared-factor: the product of the squares of small primes that
--- divide an integer.
local function squared_factor(x)
  if type(x) ~= "number" then
    return nil
  end
  local fac = 1
  for _, p in ipairs({ 4, 9, 25, 49, 121, 169, 289, 361, 529, 841 }) do
    while x % p == 0 and x ~= 0 do
      x, fac = x / p, fac * p
    end
  end
  return fac
end

local function simplify_sqrt(expr)
  local u = expr.args[1]
  if tag(u) == "frac" then
    return div(call("sqrt", { mul(u.n, u.d) }), u.d)
  end
  local fac
  if is_object(u) then
    fac = squared_factor(u)
  else
    fac = ccf(u)
  end
  if fac and fac ~= 1 then
    return mul(F.sqrt({ fac }), F.sqrt({ cancel(u, fac) }))
  end
  return nil
end

local function simplify_exp(x)
  if is_call(x, "ln") then
    return x.args[1]
  end
  return nil
end

-- trigonometric rules: f(g(u)) for inverse functions, f(-u)
local function sqrt_1_minus_sqr(u)
  return call("sqrt", { sub(1, mul(u, u)) })
end
local function sqrt_1_plus_sqr(u)
  return call("sqrt", { add(1, mul(u, u)) })
end
local TRIG = {
  sin = {
    arcsin = function(u)
      return u
    end,
    arccos = sqrt_1_minus_sqr,
    arctan = function(u)
      return div(u, sqrt_1_plus_sqr(u))
    end,
    odd = true,
  },
  cos = {
    arccos = function(u)
      return u
    end,
    arcsin = sqrt_1_minus_sqr,
    arctan = function(u)
      return div(1, sqrt_1_plus_sqr(u))
    end,
    odd = false,
  },
  tan = {
    arctan = function(u)
      return u
    end,
    arcsin = function(u)
      return div(u, sqrt_1_minus_sqr(u))
    end,
    arccos = function(u)
      return div(sqrt_1_minus_sqr(u), u)
    end,
    odd = true,
  },
  sinh = {
    arcsinh = function(u)
      return u
    end,
    odd = true,
  },
  cosh = {
    arccosh = function(u)
      return u
    end,
    odd = false,
  },
  tanh = {
    arctanh = function(u)
      return u
    end,
    odd = true,
  },
}
local INVERSE_OF = { arcsin = "sin", arccos = "cos", arctan = "tan", arcsinh = "sinh", arctanh = "tanh" }

local function simplify_call(expr)
  local name, u = expr.name, expr.args[1]
  if #expr.args ~= 1 then
    return nil
  end
  local rules = TRIG[name]
  if rules then
    if tag(u) == "call" and #u.args == 1 and rules[u.name] then
      return rules[u.name](u.args[1])
    elseif looks_neg(u) then
      local r = call(name, { neg(u) })
      return rules.odd and neg(r) or r
    end
    return nil
  elseif INVERSE_OF[name] and looks_neg(u) then
    -- arcsin(-x) is -arcsin(x)
    return neg(call(name, { neg(u) }))
  elseif name == "sqrt" then
    return simplify_sqrt(expr)
  elseif name == "exp" then
    return simplify_exp(u)
  end
  return nil
end

local function simplify_pow(expr)
  local a, b = expr.a, expr.b
  if K.equal_int(a, 10) and is_call(b, "log10") then
    return b.args[1]
  elseif tag(a) == "sym" and a.name == "e" then
    return simplify_exp(b)
  elseif is_call(a, "exp") then
    return call("exp", { mul(a.args[1], b) })
  end
  return nil
end

local function handler(aa)
  local t = tag(aa)
  if t == "op" then
    if aa.op == "+" or aa.op == "-" then
      return simplify_addsub(aa)
    elseif aa.op == "*" then
      return simplify_mul(aa)
    elseif aa.op == "/" then
      return simplify_divide(aa)
    elseif aa.op == "^" then
      return simplify_pow(aa)
    elseif COMPARE[aa.op] then
      return simplify_ineq(aa)
    end
  elseif t == "call" then
    return simplify_call(aa)
  end
  return nil
end

--- math-simplify-step: simplify the parts, then the formula itself.
local function simplify_step(a)
  if primitive(a) then
    return a
  end
  local aa = map_children(a, simplify_step)
  local r = handler(aa)
  if r ~= nil then
    return r
  end
  return aa
end

--- math-simplify: normalize and simplify until nothing changes.
local function simplify(top)
  return simplifying(function()
    for _ = 1, 100 do
      local res = simplify_step(normalize(top))
      if same(top, res) then
        break
      end
      top = res
    end
    return top
  end)
end

F.simplify = function(args)
  if #args ~= 1 then
    return call("simplify", args)
  end
  return simplify(args[1])
end
F.subst = function(args)
  if #args ~= 3 then
    return call("subst", args)
  end
  return subst(args[1], args[2], args[3])
end

A.simplify = simplify
A.parts = parts
