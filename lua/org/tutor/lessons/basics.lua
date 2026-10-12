-- Checks and hints of the exercises of tutor/org/basics.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson"). Exercises without a check get no mark.

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    -- folding changes no text: done once Kitchen has been folded
    ["1.1"] = { heading = "Kitchen", folded = true },
    ["1.2"] = { heading = "Pears", parent = "Fruit" },
    ["1.3"] = {
      { heading = "Carrot", parent = "Vegetables" },
      { heading = "Spoon", parent = "Drawer", depth = 2 },
    },
    ["1.4"] = { children = { "Monday", "Tuesday", "Wednesday" } },
    ["2.1"] = { heading = "Buy milk", todo = "DONE" },
    ["2.2"] = { heading = "Write a letter", todo = "TODO" },
    ["2.3"] = { heading = "Pay rent", priority = "A" },
    ["3.1"] = { heading = "Prepare slides", tags = { "work" } },
    ["4.1"] = { heading = "Water the plants", scheduled = true },
    ["4.2"] = { heading = "File the tax return", deadline = true },
    ["5.1"] = { item = "Butter" },
    ["5.2"] = { checked = "Eggs" },
    ["6.1"] = { table_aligned = true },
    ["6.2"] = { table_row = "Kiwi", table_aligned = true },
    ["7.1"] = { contains = "[[*Treasure chest]" },
    -- the link of 7.1 is there, and the cursor went to its target
    ["7.2"] = {
      { cursor = "Treasure chest" },
      {
        fn = function(ctx)
          return table.concat(ctx.file.lines, "\n"):find("[[*Treasure chest]", 1, true) ~= nil
        end,
      },
    },
  },
  hints = {
    ["1.1"] = "On Kitchen press {{org.cycle}} until it folds; {{org.global_cycle}} cycles the whole file.",
    ["1.2"] = "On Apples (not at the line start) press {{org.meta_return}}, type Pears, then <Esc>.",
    ["1.3"] = "On Carrot press {{org.demote_heading}}; on Spoon press {{org.promote_heading}}.",
    ["1.4"] = "On Tuesday press {{org.meta_down}} (or on Monday {{org.meta_up}}).",
    ["2.1"] = "On Buy milk press {{org.todo_next}}.",
    ["2.2"] = "On Write a letter press {{org.todo_next}}.",
    ["2.3"] = "On Pay rent press {{org.priority}}, then A.",
    ["3.1"] = "On Prepare slides press {{org.set_tags}}, type work, then <CR>.",
    ["4.1"] = "On Water the plants press {{org.schedule}}, then <CR> for today.",
    ["4.2"] = "On File the tax return press {{org.deadline}}, then <CR> for today.",
    ["5.1"] = "On Bread press {{org.meta_return}}, type Butter, then <Esc>.",
    ["5.2"] = "On Eggs press {{org.context_action}}.",
    ["6.1"] = "In the table press {{org.context_action}}.",
    ["6.2"] = "On the Lemon row press A, {{org_insert.insert_tab}}, type Kiwi, {{org_insert.insert_tab}}, 5, <Esc>.",
    ["7.1"] = "At the end of Map: press {{org.insert_link}}, type *Treasure chest <CR>, the treasure <CR>.",
    ["7.2"] = "On the link press {{org.open_at_point}}.",
  },
}
