-- ob-calc, checked against Emacs Org 9.8.10 (`emacs --batch`,
-- org-babel-execute-src-block on each block). The blocks run on the Calc
-- port of table formulas; no program is needed.
local config = require("org.config")
local h = require("tests.helpers.babel_ob")

--- The result lines of the only block of `lines`.
local function result(lines)
  local out = h.run(lines)
  for i, l in ipairs(out) do
    if l:match("^#%+RESULTS") then
      return vim.list_slice(out, i + 1)
    end
  end
  return {}
end

describe("babel ob-calc", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("evaluates formulas with calc-eval's default modes", function()
    -- Emacs 9.8.10
    local cases = {
      { "1 + 2", ": 3" },
      { "1/3", ": 0.333333333333" },
      { "x + x", ": 2 x" },
      { "1:3 + 1", ": 4:3" },
      { "2^100", ": 1267650600228229401496703205376" },
      { "sin(30)", ": 0.5" },
    }
    for _, c in ipairs(cases) do
      eq({ c[2] }, result({ "#+begin_src calc", c[1], "#+end_src" }), c[1])
    end
  end)

  it("runs stack lines: values, 'KEY operations, the top is the result", function()
    -- Emacs 9.8.10
    eq({ ": 14" }, result({ "#+begin_src calc", "3", "4", "'*", "2", "'+", "#+end_src" }))
    eq({ ": -1" }, result({ "#+begin_src calc", "2", "3", "'-", "#+end_src" }))
    eq({ ": (0., 1.58113883008)" }, result({ "#+begin_src calc", "2.5", "'n", "'Q", "#+end_src" }))
    eq({ ": 0.025" }, result({ "#+begin_src calc", "10", "'&", "4", "'/", "#+end_src" }))
  end)

  it("pushes :var values by name and replaces them in formulas", function()
    -- Emacs 9.8.10
    eq({ ": 5" }, result({ "#+begin_src calc :var a=2 b=3", "a + b", "#+end_src" }))
    eq({ ": 8" }, result({ "#+begin_src calc :var a=2", "a", "3", "'^", "#+end_src" }))
    eq({ ": 3." }, result({ "#+begin_src calc :var a=1.5", "a * 2", "#+end_src" }))
    -- Emacs gives y + 2 (Calc puts the number last)
    eq({ ": 2 + y" }, result({ "#+begin_src calc :var x=4", "sqrt(x) + y", "#+end_src" }))
  end)

  it("gives a vector as a row and a matrix as a table, verbatim as text", function()
    local tables = {
      "#+name: tb",
      "| 1 | 2 |",
      "| 3 | 4 |",
      "",
      "#+name: row",
      "| 5 | 6 | 7 |",
      "",
    }
    local function with_tables(block)
      local out = h.run(vim.list_extend(vim.deepcopy(tables), block))
      return vim.list_slice(out, #tables + #block + 3)
    end
    -- Emacs 9.8.10
    eq({ "| 1 | 2 |", "| 3 | 4 |" }, with_tables({ "#+begin_src calc :var m=tb", "m", "#+end_src" }))
    eq({ "| 5 | 6 | 7 |" }, with_tables({ "#+begin_src calc :var v=row", "v", "#+end_src" }))
    eq({ "| 1 | 2 | 3 |" }, result({ "#+begin_src calc", "[1, 2, 3]", "#+end_src" }))
    eq({ ": [1, 2, 3]" }, result({ "#+begin_src calc :results verbatim", "[1, 2, 3]", "#+end_src" }))
    -- Emacs mangles a matrix inside a formula (calc-eval of a Lisp form)
    eq({ "| 2 | 4 |", "| 6 | 8 |" }, with_tables({ "#+begin_src calc :var m=tb", "m * 2", "#+end_src" }))
  end)

  it("adds :prologue and :epilogue lines, and reports a bad line", function()
    eq("2\n3\n'+\n", h.expand({ "#+begin_src calc :prologue 2 :epilogue '+", "3", "#+end_src" }))
    eq({ ": 5" }, result({ "#+begin_src calc :prologue 2 :epilogue '+", "3", "#+end_src" }))
    local errs = {}
    local notify = vim.notify
    vim.notify = function(msg)
      errs[#errs + 1] = msg
    end
    local out = h.run({ "#+begin_src calc", "'+", "#+end_src" })
    vim.notify = notify
    eq(3, #out)
    ok(table.concat(errs, "\n"):find('Calc error "Too few elements on stack" on input "\'+"', 1, true))
  end)
end)
