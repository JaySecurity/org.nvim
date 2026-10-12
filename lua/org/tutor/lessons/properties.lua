-- Checks and hints of the exercises of tutor/org/properties.org, by
-- exercise number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a
-- tutor lesson").

--- The headline titled `title` in the exercise's subtree.
---@param ctx org.tutor.Context
---@param title string
---@return org.Headline|nil
local function headline(ctx, title)
  for _, hl in ipairs(ctx.file.headlines) do
    if hl.line > ctx.exercise.line and hl.line <= ctx.exercise.end_line and hl:plain_title() == title then
      return hl
    end
  end
end

--- A condition: the headline `title` of the exercise has property `name`
--- set to `value` (nil: not set).
---@param title string
---@param name string
---@param value string|nil
---@return org.tutor.Condition
local function property(title, name, value)
  return {
    fn = function(ctx)
      local hl = headline(ctx, title)
      return hl ~= nil and hl:get_property(name, false) == value
    end,
  }
end

--- A condition: the exercise has a columnview block whose table has a
--- row `| title | value |`.
---@param title string
---@param value string
---@return org.tutor.Condition
local function columnview_row(title, value)
  return {
    fn = function(ctx)
      local inside = false
      for _, line in ipairs(ctx.lines) do
        local l = line:lower()
        if l:match("^%s*#%+begin:%s+columnview") then
          inside = true
        elseif l:match("^%s*#%+end:") then
          inside = false
        elseif inside then
          local item, effort = line:match("^%s*|%s*(.-)%s*|%s*(.-)%s*|")
          if item == title and effort == value then
            return true
          end
        end
      end
      return false
    end,
  }
end

--- Whether column view is on in the exercise's buffer.
---@param ctx org.tutor.Context
---@return boolean
local function column_view_open(ctx)
  return require("org.columns.shared").views[ctx.buf] ~= nil
end

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = property("Coffee grinder", "Color", "red"),
    ["1.2"] = property("Blue shirt", "Size", "L"),
    ["1.3"] = property("Red shirt", "Size", "S"),
    ["1.4"] = property("Write the intro", "Effort", "0:45"),
    ["1.5"] = property("Old lamp", "Color", nil),
    -- a view: done once column view has been open on Website (the cursor
    -- condition makes the tutor remember it after q)
    ["2.1"] = { cursor = "Website", fn = column_view_open },
    ["2.2"] = property("Dig the beds", "Owner", "Ben"),
    ["2.3"] = property("Paint the walls", "Effort", "3:00"),
    ["2.4"] = columnview_row("Order paint", "0:20"),
    ["2.5"] = columnview_row("Move", "2:00"),
  },
  hints = {
    ["1.1"] = "On Coffee grinder press {{org.set_property}}, type Color <CR>, then red <CR>.",
    ["1.2"] = "On the :Size: M line press {{org.shift_right}}.",
    ["1.3"] = "On Red shirt press {{org.set_property}}, type Size <CR>, then pick S.",
    ["1.4"] = "On Write the intro press {{org.set_effort}}, type 0:45, then <CR>.",
    ["1.5"] = "On Old lamp press {{org.delete_property}} and pick Color.",
    ["2.1"] = "On Website press {{org.column_view}}; q closes the view.",
    ["2.2"] = "On Garden press {{org.column_view}}; on Dig the beds press l twice, then n; q closes.",
    ["2.3"] = "On Kitchen press {{org.column_view}}; on Paint the walls press l, e, type 3:00, <CR>.",
    ["2.4"] = "On the Report: line press {{emacs.insert_columnview}}, then <CR>.",
    ["2.5"] = "On the #+BEGIN: line press {{org.context_action}}.",
  },
}
