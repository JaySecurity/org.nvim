---@mod org.export.latex.math LaTeX math blocks and matrices
---
--- The parse tree filters that wrap math snippets in a latex-math-block
--- and collect matrix tables (org-latex-math-block-tree-filter, org-latex-matrices-tree-filter).
---
--- Part of org.export.latex, which loads it.

local ox = require("org.export.ox")
local element = require("org.export.element")
local entities = require("org.export.entities")

local M = require("org.export.latex")

---------------------------------------------------------------------------
-- Math blocks and matrices (parse tree filters)
---------------------------------------------------------------------------

local function valid_math_object(o)
  if o.type == "entity" then
    local e = entities[o.name]
    return e and e[2] == true
  elseif o.type == "latex-fragment" then
    local v = o.value
    return v:sub(1, 2) == "\\(" or v:match("^%$[^%$]") ~= nil
  end
  return false
end

--- Merge contiguous math objects in latex-math-block pseudo objects.
function M.wrap_math_block(d, info)
  if d == nil then
    return nil
  end
  -- the objects at the top of a caption have no parent: the caption line
  -- (a list) holding each
  local in_caption = {}
  element.map(d, "*", function(e)
    for _, cap in ipairs(e.caption or {}) do
      for _, list in pairs({ cap[1], cap[2] }) do
        for _, o in ipairs(list) do
          in_caption[o] = list
        end
      end
    end
  end)
  local objs = element.map(d, { entity = true, ["latex-fragment"] = true }, function(o)
    return o
  end, { with_affiliated = true })
  for _, object in ipairs(objs) do
    -- A top-level object of a secondary string (TITLE, AUTHOR, DATE) has no
    -- parent; it is wrapped too, like Emacs does.
    if (object.parent == nil or object.parent.type ~= "latex-math-block") and valid_math_object(object) then
      local sib = element.siblings(object) or in_caption[object] or (d.type == nil and d or nil)
      if sib then
        local idx
        for i, x in ipairs(sib) do
          if x == object then
            idx = i
          end
        end
        if idx then
          local block = element.node("latex-math-block", {})
          block.parent = object.parent
          local members = { object }
          local last = object
          if (object.post_blank or 0) == 0 then
            local k = idx + 1
            while sib[k] and valid_math_object(sib[k]) and not info.ignore[sib[k]] do
              members[#members + 1] = sib[k]
              last.post_blank = 1
              last = sib[k]
              k = k + 1
              if (last.post_blank or 0) > 0 then
                break
              end
            end
          end
          block.post_blank = last.post_blank
          for _, m in ipairs(members) do
            m.parent = block
          end
          block.contents = members
          sib[idx] = block
          for _ = 2, #members do
            table.remove(sib, idx + 1)
          end
        end
      end
    end
  end
  return d
end

--- Merge contiguous tables with :mode math into latex-matrices elements.
function M.wrap_matrices(tree, info)
  local tables = element.map(tree, "table", function(t)
    return t
  end, { ignore = info.ignore })
  for _, tbl in ipairs(tables) do
    if tbl.table_type == "org" and tbl.parent and tbl.parent.type ~= "latex-matrices" then
      local mode = ox.read_attribute("attr_latex", tbl, "mode") or info.latex_default_table_mode
      if mode == "inline-math" or mode == "math" then
        local caption = mode ~= "inline-math" and tbl.caption
        local name = mode ~= "inline-math" and tbl.name
        local markup = mode == "inline-math" and "inline" or ((caption or name) and "equation" or "math")
        local sib = element.siblings(tbl)
        local idx
        for i, x in ipairs(sib) do
          if x == tbl then
            idx = i
          end
        end
        local matrices = element.node("latex-matrices", { name = name, markup = markup })
        matrices.parent = tbl.parent
        local members = { tbl }
        local prev = tbl
        local k = idx + 1
        while (prev.post_blank or 0) == 0 and sib[k] and sib[k].type == "table" and sib[k].table_type == "org" do
          local m2 = ox.read_attribute("attr_latex", sib[k], "mode") or info.latex_default_table_mode
          if m2 ~= mode then
            break
          end
          members[#members + 1] = sib[k]
          prev = sib[k]
          k = k + 1
        end
        matrices.post_blank = prev.post_blank
        prev.post_blank = 0
        for _, m in ipairs(members) do
          m.name = nil
          m.caption = nil
          m.parent = matrices
        end
        matrices.contents = members
        sib[idx] = matrices
        for _ = 2, #members do
          table.remove(sib, idx + 1)
        end
      end
    end
  end
  return tree
end
