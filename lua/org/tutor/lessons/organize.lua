-- Checks and hints of the exercises of tutor/org/organize.org, by
-- exercise number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a
-- tutor lesson"). Exercises without a check get no mark.

-- The headlines of the file with this plain title.
local function find(file, title)
  local out = {}
  for _, hl in ipairs(file.headlines) do
    if hl:plain_title() == title then
      out[#out + 1] = hl
    end
  end
  return out
end

-- Whether a headline with this plain title is under the exercise.
local function in_exercise(ctx, title)
  for _, hl in ipairs(find(ctx.file, title)) do
    if hl.line > ctx.exercise.line and hl.line <= ctx.exercise.end_line then
      return true
    end
  end
  return false
end

-- Whether a headline with this plain title is under the top-level Errands.
local function in_errands(ctx, title)
  for _, hl in ipairs(find(ctx.file, title)) do
    if hl.parent and hl.parent.level == 1 and hl.parent:plain_title() == "Errands" then
      return true
    end
  end
  return false
end

-- Whether a window on the lesson shows a sparse tree whose title (in its
-- location list, "Sparse tree: ...") contains `what`.
local function sparse_tree(what)
  return function(ctx)
    for _, win in ipairs(vim.fn.win_findbuf(ctx.buf)) do
      local title = vim.fn.getloclist(win, { title = 1 }).title or ""
      if vim.startswith(title, "Sparse tree: ") and title:lower():find(what, 1, true) then
        return true
      end
    end
    return false
  end
end

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = {
      fn = function(ctx)
        return in_errands(ctx, "Buy stamps") and not in_exercise(ctx, "Buy stamps")
      end,
    },
    ["1.2"] = {
      fn = function(ctx)
        return in_errands(ctx, "Renew the passport") and in_exercise(ctx, "Renew the passport")
      end,
    },
    ["2.1"] = { heading = "Old ideas", tags = { "ARCHIVE" } },
    ["2.2"] = { heading = "Fix the fence", parent = "Archive" },
    ["2.3"] = {
      fn = function(ctx)
        if in_exercise(ctx, "Pay the rent") or not ctx.file.filename then
          return false
        end
        local path = ctx.file.filename .. "_archive"
        if vim.fn.filereadable(path) == 0 then
          return false
        end
        for _, line in ipairs(vim.fn.readfile(path)) do
          if line:match("^%*+ %u*%s*Pay the rent") then
            return true
          end
        end
        return false
      end,
    },
    -- the folds alone could also come from global cycling: the location
    -- list says which sparse tree it was (a view check: it stays done)
    ["3.1"] = { { heading = "Water the garden", folded = true }, { fn = sparse_tree("todo") } },
    ["3.2"] = { { heading = "Garden", folded = true }, { fn = sparse_tree("invoice") } },
    ["3.3"] = { { heading = "Read the contract", folded = true }, { fn = sparse_tree("phone") } },
    ["4.1"] = { cursor = "What next" },
    ["4.2"] = { item = "Sunscreen" },
    ["4.3"] = { cursor = "Return the books" },
  },
  hints = {
    ["1.1"] = "On Buy stamps press {{org.refile}} and pick Errands.",
    ["1.2"] = "On Renew the passport press {{org.refile_copy}} and pick Errands.",
    ["2.1"] = "On Old ideas press {{org.toggle_archive_tag}}.",
    ["2.2"] = "On Fix the fence press {{emacs.archive_to_sibling}}.",
    ["2.3"] = "On Pay the rent press {{org.archive_subtree}}.",
    ["3.1"] = "Press {{org.sparse_tree}}, then t.",
    ["3.2"] = "Press {{org.sparse_tree}}, r, type invoice and press <CR>.",
    ["3.3"] = "Press {{org.sparse_tree}}, m, type phone and press <CR>.",
    ["3.4"] = "Press {{org.sparse_tree}}, C, then {{org.global_cycle}} until everything shows.",
    ["4.1"] = "Press {{org.buffer_goto}}, type What next, then <CR> twice.",
    ["4.2"] = "On Packing list press {{org.narrow_subtree}}, add - Sunscreen, then {{edit_src.save_exit}}.",
    ["4.3"] = "Press {{global.agenda}}, <, m, type errand, <CR>; on Return the books press {{agenda.goto}}.",
  },
}
