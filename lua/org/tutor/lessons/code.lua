-- Checks and hints of the exercises of tutor/org/code.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson"). Exercises without a check get no mark.

--- A line after a `#+RESULTS:` line of the exercise contains `text`.
---@param text string
---@return org.tutor.Condition
local function result(text)
  return {
    fn = function(ctx)
      local in_result = false
      for _, line in ipairs(ctx.lines) do
        if line:upper():match("^%s*#%+RESULTS") then
          in_result = true
        elseif in_result and line:find(text, 1, true) then
          return true
        end
      end
      return false
    end,
  }
end

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = result(": 42"),
    ["1.2"] = result(": and hello again"),
    ["1.3"] = { table_row = "cheese" },
    ["1.4"] = result(": 3"),
    -- the name changed in the block
    ["1.5"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.lines) do
          local who = line:match('^%s*return "Hello, (.-)"%s*$')
          if who and who ~= "World" and vim.trim(who) ~= "" then
            return true
          end
        end
        return false
      end,
    },
    ["2.1"] = result(": 12"),
    ["2.2"] = result(": Hello, Neovim"),
    ["2.3"] = result(": Double: 8"),
    -- tangled, and the file opened
    ["3.1"] = {
      { buffer = "hello.lua" },
      {
        fn = function(ctx)
          local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(ctx.buf))
          return vim.fn.filereadable(vim.fs.joinpath(dir, "hello.lua")) == 1
        end,
      },
    },
    ["4.1"] = { buffer = "Org MD Export" },
    ["4.2"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.lines) do
          local opts = line:upper():match("^%s*#%+OPTIONS:(.*)")
          if opts and (" " .. opts .. " "):find("%sTOC:NIL%s") and (" " .. opts .. " "):find("%sNUM:NIL%s") then
            return true
          end
        end
        return false
      end,
    },
    ["4.3"] = { heading = "Private", tags = { "noexport" } },
  },
  hints = {
    ["1.1"] = "On #+begin_src press {{org.context_action}}, then y.",
    ["1.2"] = "On #+begin_src press {{org.context_action}}, then y.",
    ["1.3"] = "On #+begin_src press {{org.context_action}}, then y.",
    ["1.4"] = "Under Your block press {{org.insert_structure_template}}, s, lua, <Esc>, o, return 1 + 2, <Esc>; run it.",
    ["1.5"] = "In the block press {{org.edit_special}}, change World, then press {{edit_src.save_exit}}.",
    ["2.1"] = "On #+begin_src press {{org.context_action}}, then y.",
    ["2.2"] = "On #+CALL: press {{org.context_action}}, then y.",
    ["2.3"] = "On the second #+begin_src press {{org.context_action}}, then y and y.",
    ["3.1"] = "Press {{org.babel_tangle}}; on the link press {{org.open_at_point}}, then :q.",
    ["4.1"] = "On Trip notes press {{org.export}}, s, m, M; :q closes the window.",
    ["4.2"] = "Type #+OPTIONS: toc:nil num:nil author:nil below; on Packing press {{org.export}}, s, t, A.",
    ["4.3"] = "On Private press {{org.set_tags}}, type noexport, <CR>; on Diary press {{org.export}}, s, m, M.",
  },
}
