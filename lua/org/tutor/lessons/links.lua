-- Checks and hints of the exercises of tutor/org/links.org, by exercise
-- number (see `org.tutor.Condition`; CONTRIBUTING.md, "Writing a tutor
-- lesson").

---@type { checks: org.tutor.Checks, hints: table<string, string> }
return {
  checks = {
    ["1.1"] = { cursor = "Shopping list" },
    ["1.2"] = { contains = "[[https://orgmode.org][Org manual]]" },
    ["1.3"] = { contains = "Visitors: [[door code]]" },
    ["1.4"] = { contains = "Meeting notes]]" },
    ["1.5"] = { contains = "[[file:ideas.txt]]" },
    -- the property, not the text: the exercise's text names :ID: too
    ["2.1"] = {
      heading = "Project plan",
      fn = function(ctx)
        for _, hl in ipairs(ctx.file.headlines) do
          if hl:plain_title() == "Project plan" then
            return (hl:get_property("ID") or "") ~= ""
          end
        end
        return false
      end,
    },
    ["2.2"] = { contains = "[[id:" },
    ["3.1"] = { heading = "Receipts", tags = { "ATTACH" } },
    -- the link goes under Receipts, in 3.1's subtree: an attachment: link
    -- resolves in the folder of the entry it is in
    ["3.2"] = {
      fn = function(ctx)
        for _, line in ipairs(ctx.file.lines) do
          if line:find("[[attachment:march.txt]]", 1, true) then
            return true
          end
        end
        return false
      end,
    },
  },
  hints = {
    ["1.1"] = "On the link press {{org.open_at_point}}.",
    ["1.2"] = "At the end of Manual: press {{org.insert_link}}, type the URL, <CR>, Org manual, <CR>.",
    ["1.3"] = "At the end of Visitors: press {{org.insert_link}}, type door code, <CR>, <CR>.",
    ["1.4"] = "On Meeting notes press {{org.store_link}}; after Notes: press {{org.insert_last_stored_link}}.",
    ["1.5"] = "At the end of Ideas: press {{org.insert_link}}, type file:ideas.txt, <CR>, <CR>.",
    ["2.1"] = "On Project plan press {{org.id_get_create}}.",
    ["2.2"] = "On Project plan run :Org id_store_link; after Plan: press {{org.insert_last_stored_link}}.",
    ["3.1"] = "On Receipts press {{org.attach}}, n, type march.txt, <CR>; type a line, then :wq.",
    ["3.2"] = "After March: press {{org.insert_link}}, type attachment:march.txt, <CR>, <CR>.",
  },
}
