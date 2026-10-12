---@mod org.table.calc_alg.poly Polynomials and collect
---
--- The coefficients of a polynomial (math-is-polynomial) and collect.
--- Part of org.table.calc_alg, which loads it.

local A = require("org.table.calc_alg")

local F = A.F
local tag = A.tag
local add = A.add
local mul = A.mul
local div = A.div
local pow = A.pow
local neg = A.neg
local op = A.op
local call = A.call
local same = A.same
local is_zero = A.is_zero
local looks_neg = A.looks_neg
local is_object = A.is_object
local isop = A.isop
local normalize = A.normalize
local contains = A.contains

local function poly_mix(a, ac, b, bc)
  local out = {}
  for i = 1, math.max(#a, #b) do
    out[i] = add(mul(a[i] or 0, ac), mul(b[i] or 0, bc))
  end
  return out
end

local function poly_mul(a, b)
  if #a == 0 or #b == 0 then
    return {}
  end
  local rest = { unpack(a, 2) }
  local shifted = { 0, unpack(b) }
  return poly_mix(b, a[1], #rest > 0 and poly_mul(rest, shifted) or {}, 1)
end

local function poly_simplify(p)
  while #p > 1 and is_zero(p[#p]) do
    p[#p] = nil
  end
  return p
end

--- The coefficients { c0, c1, ... } of `expr` as a polynomial in `var`,
--- or nil. `base` is the variable whose presence makes a term
--- non-constant (nil with `loose`: every other term is a coefficient).
local function is_polynomial(expr, var, degree, loose, base)
  base = base or var
  local function depends(x)
    return not loose and contains(x, base)
  end
  local rec
  rec = function(e)
    local r
    if same(e, var) then
      r = { 0, 1 }
    elseif isop(e, "^") then
      local b, n = e.a, e.b
      if type(n) == "number" and n >= 0 then
        local p1 = same(b, var) and { 0, 1 } or rec(b)
        if p1 and (not degree or (#p1 - 1) * n <= degree) then
          r = { 1 }
          for _ = 1, n do
            r = poly_mul(r, p1)
          end
        end
      end
    elseif is_object(e) then
      r = { e }
    elseif isop(e, "+", "-") then
      local p1 = rec(e.a)
      local p2 = p1 and rec(e.b)
      if p2 then
        r = poly_mix(p1, 1, p2, e.op == "+" and 1 or -1)
      end
    elseif tag(e) == "neg" then
      local p1 = rec(e.a)
      if p1 then
        r = {}
        for i, c in ipairs(p1) do
          r[i] = neg(c)
        end
      end
    elseif isop(e, "*") then
      local p1 = rec(e.a)
      local p2 = p1 and rec(e.b)
      if p2 and (not degree or #p1 + #p2 - 2 <= degree) then
        r = poly_mul(p1, p2)
      end
    elseif isop(e, "/") then
      if not depends(e.b) and not is_zero(e.b) then
        local p1 = rec(e.a)
        if p1 then
          r = {}
          for i, c in ipairs(p1) do
            r[i] = div(c, e.b)
          end
        end
      end
    end
    if r == nil and not depends(e) and tag(e) ~= "vec" then
      r = { e }
    end
    return r and poly_simplify(r)
  end
  local p = rec(expr)
  if p and degree and #p > degree + 1 then
    return nil
  end
  return p
end

--- math-build-polynomial-expr
local function build_polynomial(p, var)
  local n = #p - 1
  local accum = mul(p[#p], pow(var, n))
  for i = #p - 1, 1, -1 do
    n = n - 1
    local c = p[i]
    if not is_zero(c) then
      local negc = looks_neg(c)
      accum = op(negc and "-" or "+", accum, mul(negc and neg(c) or c, pow(var, n)))
    end
  end
  return accum
end

F.collect = function(args)
  if #args ~= 2 then
    return call("collect", args)
  end
  local p = is_polynomial(args[1], args[2], 50, true)
  if not p then
    return call("collect", args)
  elseif #p > 1 then
    for i, c in ipairs(p) do
      p[i] = normalize(c)
    end
    return build_polynomial(p, args[2])
  end
  return p[1]
end

A.is_polynomial = is_polynomial
