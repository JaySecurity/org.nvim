-- Checks and hints of the exercises of tutor/org/writing.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson"). Exercises without a check get no mark.

--- Whether a line of the exercise matches `pattern`.
local function has_line(pattern)
  return function(ctx)
    for _, line in ipairs(ctx.lines) do
      if line:match(pattern) then
        return true
      end
    end
    return false
  end
end

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = { contains = "*important*" },
    ["1.2"] = { contains = "/in italics/" },
    -- the long line is filled: it ends on another line
    ["2.1"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.lines) do
          if line:match("^Org files are plain text") then
            return not line:find("twenty years", 1, true)
          end
        end
        return false
      end,
    },
    ["2.2"] = { fn = has_line("^%s*%-%-%-%-%-+%s*$") },
    ["2.3"] = { contains = "# Draft:" },
    -- the keyword goes at the top of the file, out of the exercise
    ["3.1"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.file.lines) do
          if line:match("^#%+[Aa][Uu][Tt][Hh][Oo][Rr]:%s*%S") then
            return true
          end
          if line:match("^%*") then
            return false
          end
        end
        return false
      end,
    },
    ["3.2"] = {
      fn = function(ctx)
        return table.concat(ctx.lines, "\n"):lower():find("#+begin_quote\nhope is", 1, true) ~= nil
      end,
    },
    ["3.3"] = { fn = has_line("^%s*#%+[Bb][Ee][Gg][Ii][Nn]_[Ss][Rr][Cc]%s+python") },
    ["3.4"] = { contains = 'print("world")' },
    ["4.1"] = { contains = "Tea is ready.[fn:", fn = has_line("^%[fn:[^%]]+%]%s*Green or black") },
    ["4.2"] = { fn = has_line("^%[fn:milk%]%s*%S") },
  },
  hints = {
    ["1.1"] = "On important press viw, then {{org.emphasize}} and *.",
    ["1.2"] = "On the line below Notes: press {{org.emphasize}}, /, type in italics, then <Esc>.",
    ["2.1"] = "On the long line press gqip.",
    ["2.2"] = "On First part press o, type -----, then <Esc>.",
    ["2.3"] = "On Draft: press gcc.",
    ["3.1"] = "Press gg, then o, type #+AUTHOR: Ada, then <Esc>.",
    ["3.2"] = "On Hope press Vj, then {{org.insert_structure_template}} and q.",
    ["3.3"] = "Below Code: press {{org.insert_structure_template}}, s, type python <CR> and the code, <Esc>.",
    ["3.4"] = "In the block press {{org.edit_special}}, change hello to world, then {{edit_src.save_exit}}.",
    ["4.1"] = "At the end of Tea is ready. press {{org.insert_footnote}}, type the note, then <Esc>.",
    ["4.2"] = "On [fn:milk] press {{org.insert_footnote}}, then A, type a space and the note, <Esc>.",
  },
}
