---@mod org.table.calc_alg Symbolic algebra for the table Calc
---
--- Ports of Calc's algebra functions (calc-alg.el, calc-poly.el,
--- calcalg2.el) for formulas with variables: simplify (math-simplify and
--- its rules for + - * / ^ sqrt exp trigonometric functions and
--- equations), expand, collect, subst, deriv, integ (common integrals, not
--- Calc's rule-based integrator) and solve (linear and quadratic
--- polynomials, inverse functions; one solution, as Calc without the "all
--- solutions" flag).
---
--- This file holds the helpers the parts share (normalize, subst, the
--- angle conversions, ...); setup() loads the parts from
--- org/table/calc_alg/: simplify, expand, poly (polynomials and collect),
--- deriv, integ and solve. Each adds its functions to the `F` of
--- org.table.calc.

local M = {}
-- The parts in org/table/calc_alg/ read the internals and the shared
-- helpers from this table and require it back, so it must be in
-- package.loaded before they load.
package.loaded["org.table.calc_alg"] = M

--- Add the algebra functions to org.table.calc, whose internals are `K`.
---@param K table the internals of org.table.calc
function M.setup(K)
  M.K = K
  local F, tag, is_real, is_int = K.F, K.tag, K.is_real, K.is_int
  local add, sub, mul, div, pow, neg = K.add, K.sub, K.mul, K.div, K.pow, K.neg
  local op, sym, call, same = K.op, K.sym, K.call, K.same
  local is_zero, negative, looks_neg = K.is_zero, K.negative, K.looks_neg
  local is_object, is_number = K.is_object, K.is_number

  local function isop(v, a, b)
    return tag(v) == "op" and (v.op == a or (b ~= nil and v.op == b))
  end

  local function is_call(v, name)
    return tag(v) == "call" and v.name == name and #v.args == 1
  end

  --- Math-primp: a number, object or variable (no sub-formulas).
  local function primitive(v)
    local t = tag(v)
    return not (t == "op" or t == "neg" or t == "call" or t == "vec")
  end

  local function is_rat(v)
    return is_int(v) or tag(v) == "frac"
  end

  local COMPARE = { ["=="] = true, ["!="] = true, ["<"] = true, [">"] = true, ["<="] = true, [">="] = true }
  local BINARY = { ["+"] = add, ["-"] = sub, ["*"] = mul, ["/"] = div, ["^"] = pow, ["|"] = K.concat }

  local HELD = { deriv = true, integ = true, solve = true, simplify = true, expand = true, collect = true }

  --- math-normalize: evaluate a formula again, bottom up.
  local function normalize(v)
    local t = tag(v)
    if t == "op" then
      local a, b = normalize(v.a), normalize(v.b)
      if BINARY[v.op] then
        return BINARY[v.op](a, b)
      elseif COMPARE[v.op] then
        return K.compare(v.op, a, b)
      elseif v.op == "%" then
        return F.mod({ a, b })
      end
      return op(v.op, a, b)
    elseif t == "neg" then
      return neg(normalize(v.a))
    elseif t == "call" then
      local args = {}
      for i, x in ipairs(v.args) do
        args[i] = normalize(x)
      end
      -- an algebra function left unevaluated stays so (no retrying it)
      local f = not HELD[v.name] and F[v.name]
      return f and f(args) or call(v.name, args)
    elseif t == "vec" then
      local out = { tag = "vec" }
      for i, x in ipairs(v) do
        out[i] = normalize(x)
      end
      return out
    end
    return v
  end

  --- The same formula with `f` applied to each direct sub-formula.
  local function map_children(v, f)
    local t = tag(v)
    if t == "op" then
      return op(v.op, f(v.a), f(v.b))
    elseif t == "neg" then
      return { tag = "neg", a = f(v.a) }
    elseif t == "call" then
      local args = {}
      for i, x in ipairs(v.args) do
        args[i] = f(x)
      end
      return call(v.name, args)
    elseif t == "vec" then
      local out = { tag = "vec" }
      for i, x in ipairs(v) do
        out[i] = f(x)
      end
      return out
    end
    return v
  end

  --- math-expr-contains
  local function contains(expr, thing)
    if same(expr, thing) then
      return true
    end
    local t = tag(expr)
    if t == "op" then
      return contains(expr.a, thing) or contains(expr.b, thing)
    elseif t == "neg" then
      return contains(expr.a, thing)
    elseif t == "call" then
      for _, x in ipairs(expr.args) do
        if contains(x, thing) then
          return true
        end
      end
    elseif t == "vec" then
      for _, x in ipairs(expr) do
        if contains(x, thing) then
          return true
        end
      end
    end
    return false
  end

  --- math-expr-subst: replace `old` by `new`, without evaluating again
  --- (`subst(x^2, x, 3)` is `3^2`, as in Calc).
  local function subst(expr, old, new)
    if same(expr, old) then
      return new
    elseif primitive(expr) then
      return expr
    end
    return map_children(expr, function(x)
      return subst(x, old, new)
    end)
  end

  --- Run `f` with Calc's math-simplifying on.
  local function simplifying(f, ...)
    local old = K.set_simplifying(true)
    local ok, r = pcall(f, ...)
    K.set_simplifying(old)
    if not ok then
      error(r, 0)
    end
    return r
  end

  local PI = sym("pi")

  --- An angle in the angle mode to radians, kept symbolic (math-to-radians-2).
  local function to_radians(a)
    if K.modes().deg then
      return div(mul(a, PI), 180)
    end
    return a
  end

  local function from_radians(a)
    if K.modes().deg then
      return div(mul(a, 180), PI)
    end
    return a
  end

  local function sqr(u)
    return mul(u, u)
  end

  local function fn(name, ...)
    local f = F[name]
    local args = { ... }
    return f and f(args) or call(name, args)
  end

  -- what the parts share
  M.F = F
  M.tag = tag
  M.is_real = is_real
  M.is_int = is_int
  M.add = add
  M.sub = sub
  M.mul = mul
  M.div = div
  M.pow = pow
  M.neg = neg
  M.op = op
  M.sym = sym
  M.call = call
  M.same = same
  M.is_zero = is_zero
  M.negative = negative
  M.looks_neg = looks_neg
  M.is_object = is_object
  M.is_number = is_number
  M.isop = isop
  M.is_call = is_call
  M.primitive = primitive
  M.is_rat = is_rat
  M.COMPARE = COMPARE
  M.normalize = normalize
  M.map_children = map_children
  M.contains = contains
  M.subst = subst
  M.simplifying = simplifying
  M.PI = PI
  M.to_radians = to_radians
  M.from_radians = from_radians
  M.sqr = sqr
  M.fn = fn

  -- in this order: a part uses the functions of those before it
  require("org.table.calc_alg.simplify")
  require("org.table.calc_alg.expand")
  require("org.table.calc_alg.poly")
  require("org.table.calc_alg.deriv")
  require("org.table.calc_alg.integ")
  require("org.table.calc_alg.solve")
end

return M
