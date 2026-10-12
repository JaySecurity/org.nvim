---@mod org.table.calc_alg.expand expand (calc-poly.el)
---
--- expand: products, quotients and small powers of sums.
--- Part of org.table.calc_alg, which loads it.

local A = require("org.table.calc_alg")

local F = A.F
local add = A.add
local neg = A.neg
local op = A.op
local call = A.call
local same = A.same
local isop = A.isop
local primitive = A.primitive
local normalize = A.normalize
local map_children = A.map_children

local function add_or_sub(a, b, aneg, bneg)
  if aneg then
    a = neg(a)
  end
  if bneg then
    b = neg(b)
  end
  return add(a, b)
end

--- math-expand-power: a sum to a small power, term by term.
local function expand_power(x, n)
  if not (type(n) == "number" and n >= 0 and isop(x, "+", "-")) then
    return nil
  end
  local terms = {}
  while isop(x, "+", "-") do
    table.insert(terms, 1, x.op == "-" and neg(x.b) or x.b)
    x = x.a
  end
  table.insert(terms, 1, x)
  local accum = 0
  if #terms == 2 then
    for i = 0, n do
      accum = op("+", accum, op("*", F.choose({ n, i }), op("*", op("^", terms[2], i), op("^", terms[1], n - i))))
    end
  elseif n == 2 then
    for i = 1, #terms do
      accum = op("+", accum, op("^", terms[i], 2))
      for j = i + 1, #terms do
        accum = op("+", accum, op("*", 2, op("*", terms[i], terms[j])))
      end
    end
  elseif n == 3 then
    for i = 1, #terms do
      accum = op("+", accum, op("^", terms[i], 3))
      for j = i + 1, #terms do
        accum = op(
          "+",
          op("+", accum, op("*", 3, op("*", op("^", terms[i], 2), terms[j]))),
          op("*", 3, op("*", terms[i], op("^", terms[j], 2)))
        )
        for k = j + 1, #terms do
          accum = op("+", accum, op("*", 6, op("*", terms[i], op("*", terms[j], terms[k]))))
        end
      end
    end
  else
    return nil
  end
  return accum
end

--- math-expand-term: distribute one product, quotient or power of a sum.
local function expand_term(expr)
  if isop(expr, "*") and isop(expr.a, "+", "-") then
    return add_or_sub(op("*", expr.a.a, expr.b), op("*", expr.a.b, expr.b), false, expr.a.op == "-")
  elseif isop(expr, "*") and isop(expr.b, "+", "-") then
    return add_or_sub(op("*", expr.a, expr.b.a), op("*", expr.a, expr.b.b), false, expr.b.op == "-")
  elseif isop(expr, "/") and isop(expr.a, "+", "-") then
    return add_or_sub(op("/", expr.a.a, expr.b), op("/", expr.a.b, expr.b), false, expr.a.op == "-")
  elseif isop(expr, "^") and isop(expr.a, "+", "-") and type(expr.b) == "number" then
    if expr.b > 0 then
      return expand_power(expr.a, expr.b) or op("*", expr.a, op("^", expr.a, expr.b - 1))
    elseif expr.b < 0 then
      return op("/", 1, op("^", expr.a, -expr.b))
    end
  end
  return expr
end

--- math-map-tree: apply `f` to every node until nothing changes.
local function map_tree(f, expr)
  local budget = 20000
  local function rec(e)
    while budget > 0 do
      while budget > 0 do
        budget = budget - 1
        local nv = f(e)
        if same(e, nv) then
          break
        end
        e = nv
      end
      if primitive(e) then
        break
      end
      local nv = map_children(e, rec)
      if same(nv, e) then
        break
      end
      e = nv
    end
    return e
  end
  return rec(expr)
end

local function expand(expr)
  return normalize(map_tree(expand_term, expr))
end

F.expand = function(args)
  if #args < 1 or #args > 2 then
    return call("expand", args)
  end
  return expand(args[1])
end

A.expand = expand
