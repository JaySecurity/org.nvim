-- Checks and hints of the exercises of tutor/org/tables.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson").

--- The rows of the exercise's tables as lists of trimmed fields, the
--- separator lines left out.
---@param ctx org.tutor.Context
---@return string[][]
local function rows(ctx)
  local out = {}
  for _, line in ipairs(ctx.lines) do
    if line:match("^%s*|") and not line:match("^%s*|%-") then
      out[#out + 1] = require("org.table").split_cells(line)
    end
  end
  return out
end

--- A condition: the row whose first field is `first` has `want` (field
--- number → text).
---@param first string
---@param want table<integer, string>
local function row(first, want)
  return {
    fn = function(ctx)
      for _, r in ipairs(rows(ctx)) do
        if r[1] == first then
          for i, v in pairs(want) do
            if r[i] ~= v then
              return false
            end
          end
          return true
        end
      end
      return false
    end,
  }
end

--- A condition: the first fields of the rows are these, in order.
---@param firsts string[]
local function order(firsts)
  return {
    fn = function(ctx)
      local got = {}
      for _, r in ipairs(rows(ctx)) do
        got[#got + 1] = r[1]
      end
      return vim.deep_equal(got, firsts)
    end,
  }
end

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = row("Milk", { [3] = "1.20" }),
    ["1.2"] = { row("Eggs", { [2] = "12" }), row("Flour", { [2] = "3" }) },
    ["2.1"] = row("Qty", { [2] = "Item" }),
    ["2.2"] = order({ "Drink", "Coffee", "Tea" }),
    ["2.3"] = {
      fn = function(ctx)
        return vim.deep_equal(rows(ctx)[1], { "Item", "Qty" })
      end,
    },
    ["2.4"] = order({ "Task", "Write", "Read" }),
    -- the separator is the table's second line
    ["2.5"] = {
      fn = function(ctx)
        for i, line in ipairs(ctx.lines) do
          if line:match("^%s*|") then
            return (ctx.lines[i + 1] or ""):match("^%s*|%-") ~= nil
          end
        end
        return false
      end,
    },
    ["2.6"] = order({ "Name", "Ben", "Cleo", "Ana" }),
    ["3.1"] = { { contains = "#+TBLFM: $4=$2*$3" }, row("Apples", { [4] = "1.5" }) },
    ["3.2"] = { { contains = "#+TBLFM: $2=$1*0.62" }, row("10", { [2] = "6.2" }) },
    ["3.3"] = { row("Apples", { [4] = "1.5" }), row("Lemons", { [4] = "1." }) },
    ["3.4"] = { { contains = "vsum(@2..@-1)" }, row("Sum", { [2] = "1050" }) },
    ["3.5"] = { row("Apples", { [4] = "1.50" }), row("Lemons", { [4] = "1.00" }) },
    ["4.1"] = { table_row = "Lima", table_aligned = true },
  },
  hints = {
    ["1.1"] = "On Milk press i, {{org_insert.insert_tab}} twice, type 1.20, then <Esc>.",
    ["1.2"] = "On Eggs press i and {{org_insert.insert_tab}}, type 12, <CR>, type 3, then <Esc>.",
    ["2.1"] = "On Qty press {{org.meta_left}}.",
    ["2.2"] = "On Coffee press {{org.meta_up}}.",
    ["2.3"] = "On Notes press {{org.shift_meta_left}}.",
    ["2.4"] = "On Old press {{org.shift_meta_up}}.",
    ["2.5"] = "On Day press {{org.table_insert_hline}}.",
    ["2.6"] = "On a number of the Score column press {{org.table_sort}}, then N.",
    ["3.1"] = "On Apples press i, {{org_insert.insert_tab}} three times, type =$2*$3, {{org_insert.insert_tab}}.",
    ["3.2"] = "On the 0 next to 10 press {{emacs.table_formula}}, type $1*0.62 and <CR>.",
    ["3.3"] = "In the table press {{org.table_recalc}}.",
    ["3.4"] = "On Sum press i, {{org_insert.insert_tab}}, type :=vsum(@2..@-1), <Esc>, {{org.context_action}}.",
    ["3.5"] = "On #+TBLFM: press A, type ;%.2f, then <Esc> and {{org.context_action}}.",
    ["4.1"] = "On city press V, jj, then {{org.table_create}}.",
  },
}
