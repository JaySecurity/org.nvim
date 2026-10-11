-- Drawers written in lower case (":properties:" ... ":end:"). Emacs matches
-- org-property-drawer-re, org-logbook-drawer-re and ":END:" with
-- case-fold-search, so every module that finds a drawer by its text reads
-- these the same as the upper-case spelling (checked against Org 9.8.10:
-- org-at-encrypted-entry-p, org-babel-ref-headline-body, header-args from
-- the file's drawer, org-thing-at-point in a drawer).

describe("lower-case drawers", function()
  it("crypt finds an encrypted entry after a lower-case property drawer", function()
    org_buffer({
      "* Secret :crypt:",
      ":properties:",
      ":ID: x",
      ":end:",
      "-----BEGIN PGP MESSAGE-----",
      "abc",
      "-----END PGP MESSAGE-----",
    }, { 1, 0 })
    local s, e = require("org.crypt").at_encrypted_entry()
    eq(5, s)
    eq(7, e)
  end)

  it("completes property names inside a lower-case property drawer", function()
    local buf = org_buffer({ "* H", ":properties:", ":Alpha: 1", ":", ":end:" }, { 4, 1 })
    local ctx = require("org.completion").get(":", 1, buf)
    local words = {}
    for _, item in ipairs(ctx.items) do
      words[#words + 1] = item.word
    end
    -- property names (Alpha is set already), not drawer names
    eq("END:", words[#words])
    ok(not vim.tbl_contains(words, "LOGBOOK:"))
    ok(not vim.tbl_contains(words, "Alpha: "))
  end)

  it("babel reads header-args from a lower-case file property drawer", function()
    local buf = org_buffer({
      ":properties:",
      ":header-args: :results output",
      ":end:",
      "#+begin_src sh",
      "echo",
      "#+end_src",
    }, { 5, 0 })
    local b = require("org.babel").at_block(buf, 5)
    eq("output", b.args.results_spec.collection)
  end)

  it("a headline reference skips a lower-case property drawer", function()
    local buf = org_buffer({ "* Data", ":properties:", ":ID: data-1", ":end:", "body", "* Other" }, { 1, 0 })
    eq("body", require("org.babel").headline_body(buf, "data-1", true))
  end)

  it("roam promotes a subtree with a lower-case property drawer", function()
    local out = require("org.extensions.roam.node").promote_subtree_lines({
      "* Title",
      ":properties:",
      ":ID: n1",
      ":end:",
      "text",
    })
    eq({ ":properties:", ":ID: n1", ":end:", "#+title: Title", "text" }, out)
  end)

  it("feed reads a status drawer closed by a lower-case :end:", function()
    local buf = org_buffer({ "* Inbox", ":FEEDSTATUS:", "nil", ":end:", "* Next" }, { 1, 0 })
    eq({}, require("org.feed").read_status(buf, 1, "FEEDSTATUS"))
  end)

  it("deleting the last clock line removes a lower-case logbook drawer", function()
    require("org.clock")
    local buf = org_buffer({ "* T", ":logbook:", "CLOCK: [2024-01-01 Mon 10:00]", ":end:", "body" }, { 1, 0 })
    require("org.clock.shared").delete_clock_line(buf, 3)
    eq({ "* T", "body" }, buf_lines(buf))
  end)

  it("MobileOrg entry text drops a lower-case drawer and keeps the body", function()
    local buf = org_buffer({ "* T", ":properties:", ":ID: x", ":end:", "body" }, { 1, 0 })
    local file = require("org.files").get_buffer(buf)
    eq({ "body" }, require("org.mobile").entry_text(file.headlines[1], 10, ""))
  end)
end)
