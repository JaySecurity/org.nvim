---@mod org.table.calc.logic Calc: logic, comparisons and concatenation

local values = require("org.table.calc.values")
local arith = require("org.table.calc.arith")
local forms = require("org.table.calc.forms")

local tag = values.tag
local is_real = values.is_real
local op = arith.op
local call = arith.call
local num_cmp = arith.num_cmp
local is_zero = arith.is_zero
local F = arith.F
local same = arith.same
local is_objvec = arith.is_objvec
local hms_value = forms.hms_value

-- Logic
local function truth(v)
  if is_real(v) then
    return not is_zero(v)
  end
  return nil
end
F["if"] = function(args)
  local c = truth(args[1])
  if c == nil then
    if tag(args[1]) == "vec" then
      error("bad condition")
    end
    return call("if", args)
  end
  return c and args[2] or args[3]
end
F.lnot = function(args)
  local c = truth(args[1])
  if c == nil then
    return call("lnot", args)
  end
  return c and 0 or 1
end

local compare

--- math-two-eq: 1 when `a` and `b` are equal, 0 when they differ, nil when
--- that is not known (formulas). Vectors are equal element by element;
--- a vector is never equal to a number.
---@return integer?
local function two_eq(a, b)
  local ta, tb = tag(a), tag(b)
  if ta == "vec" then
    if tb ~= "vec" then
      return arith.is_object(b) and 0 or nil
    elseif #a ~= #b then
      return 0
    end
    ---@type integer?
    local res = 1
    for i = 1, #a do
      local r = two_eq(a[i], b[i])
      if r == 0 then
        return 0
      elseif r == nil then
        res = nil
      end
    end
    return res
  elseif tb == "vec" then
    return arith.is_object(a) and 0 or nil
  end
  local r = compare("==", a, b)
  return type(r) == "number" and r or nil
end

compare = function(o, a, b)
  if arith.is_nan(a) or arith.is_nan(b) then
    -- nan is not ordered: the comparison stays (math-compare gives 2)
    return op(o == "=" and "==" or o, a, b)
  elseif is_real(a) and is_real(b) then
    local c = num_cmp(a, b)
    local r = (o == "<" and c < 0)
      or (o == ">" and c > 0)
      or (o == "<=" and c <= 0)
      or (o == ">=" and c >= 0)
      or ((o == "==" or o == "=") and c == 0)
      or (o == "!=" and c ~= 0)
    return r and 1 or 0
  elseif tag(a) == "date" and tag(b) == "date" then
    return compare(o, a.v, b.v)
  elseif
    (tag(a) == "hms" or tag(b) == "hms")
    and (tag(a) == "hms" or is_real(a))
    and (tag(b) == "hms" or is_real(b))
  then
    return compare(o, tag(a) == "hms" and hms_value(a) or a, tag(b) == "hms" and hms_value(b) or b)
  elseif (o == "==" or o == "=" or o == "!=") and (tag(a) == "vec" or tag(b) == "vec") then
    local r = two_eq(a, b)
    if r ~= nil then
      return o == "!=" and 1 - r or r
    end
  end
  if same(a, b) then
    -- math-compare of equal formulas is 0: `x > x` is 0, `x >= x` 1
    return (o == "==" or o == "=" or o == "<=" or o == ">=") and 1 or 0
  end
  return op(o == "=" and "==" or o, a, b)
end

local function concat(a, b)
  if not is_objvec(a) or not is_objvec(b) then
    return op("|", a, b)
  end
  local out = { tag = "vec" }
  for _, v in ipairs({ a, b }) do
    if tag(v) == "vec" then
      for _, x in ipairs(v) do
        out[#out + 1] = x
      end
    else
      out[#out + 1] = v
    end
  end
  return out
end

return {
  truth = truth,
  compare = compare,
  concat = concat,
}
