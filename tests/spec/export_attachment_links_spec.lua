-- attachment: links on export (org-attach-expand-links in
-- org-export-before-parsing-functions): they become file: links into the
-- attachment directory of their entry.

local ox = require("org.export.ox")
local config = require("org.config")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/img", "p")
  vim.fn.mkdir(dir .. "/data/ab/cdef", "p")
  return require("org.utils").realpath(dir)
end

local function export(backend, dir, lines, opts)
  opts = vim.tbl_extend("force", { filename = dir .. "/a.org", body_only = true }, opts or {})
  return (ox.export_as(backend, lines, opts))
end

local DOC = {
  "* With DIR",
  ":PROPERTIES:",
  ":DIR: img",
  ":END:",
  "[[attachment:pic.png]]",
  "",
  "[[attachment:doc.pdf][the doc]] =attachment:x.png=",
  "* With ID",
  ":PROPERTIES:",
  ":ID: abcdef",
  ":END:",
  "attachment:p.png",
}

describe("attachment: links on export", function()
  local dir
  before_each(function()
    dir = tmpdir()
  end)
  after_each(function()
    config.setup({})
  end)

  it("html inlines the image of the entry's DIR and ID directories", function()
    local out = export("html", dir, DOC)
    ok(out:find('<img src="file://' .. dir .. '/img/pic.png" alt="pic.png" />', 1, true))
    ok(out:find('<img src="file://' .. dir .. '/data/ab/cdef/p.png" alt="p.png" />', 1, true))
    -- the description stays; verbatim text isn't a link
    ok(out:find('<a href="file://' .. dir .. '/img/doc.pdf">the doc</a>', 1, true))
    ok(out:find("<code>attachment:x.png</code>", 1, true))
    eq(nil, out:find('href="attachment:', 1, true))
  end)

  it("latex includes the graphics", function()
    local out = export("latex", dir, DOC)
    ok(out:find("\\includegraphics[width=.9\\linewidth]{" .. dir .. "/img/pic.png}", 1, true))
    ok(out:find("\\includegraphics[width=.9\\linewidth]{" .. dir .. "/data/ab/cdef/p.png}", 1, true))
    eq(nil, out:find("\\url{attachment:", 1, true))
  end)

  it("md writes image links", function()
    local out = export("md", dir, DOC)
    ok(out:find("![img](" .. dir .. "/img/pic.png)", 1, true))
    ok(out:find("![img](" .. dir .. "/data/ab/cdef/p.png)", 1, true))
    ok(out:find("[the doc](file://" .. dir .. "/img/doc.pdf)", 1, true))
  end)

  it("uses the file's directory when the entry has none, or it doesn't exist", function()
    local out = export("ascii", dir, {
      "attachment:top.png",
      "* No directory",
      "attachment:a.png",
      "* Missing directory",
      ":PROPERTIES:",
      ":DIR: nowhere",
      ":END:",
      "attachment:b.png",
    })
    ok(out:find("<file:" .. dir .. "/top.png>", 1, true))
    ok(out:find("<file:" .. dir .. "/a.png>", 1, true))
    ok(out:find("<file:" .. dir .. "/b.png>", 1, true))
  end)

  it("follows attach.use_inheritance, also from above an exported subtree", function()
    local lines = {
      "* Parent",
      ":PROPERTIES:",
      ":DIR: img",
      ":END:",
      "** Child",
      "attachment:c.png",
    }
    ok(export("ascii", dir, lines):find("<file:" .. dir .. "/c.png>", 1, true))
    config.setup({ attach = { use_inheritance = true } })
    ok(export("ascii", dir, lines):find("<file:" .. dir .. "/img/c.png>", 1, true))
    -- the subtree's own text and its children see the parent's DIR
    ok(export("ascii", dir, lines, { subtree_line = 5 }):find("<file:" .. dir .. "/img/c.png>", 1, true))
  end)

  it("reads the DIR of an exported subtree's own heading", function()
    local out = export("ascii", dir, {
      "* Entry",
      ":PROPERTIES:",
      ":DIR: img",
      ":END:",
      "attachment:e.png",
    }, { subtree_line = 1 })
    ok(out:find("<file:" .. dir .. "/img/e.png>", 1, true))
  end)

  it("keeps a search option", function()
    local seen
    config.opts.export.filters = {
      ["parse-tree"] = function(tree)
        require("org.export.element").map(tree, "link", function(l)
          seen = { l.link_type, l.path, l.search_option, l.raw_link }
        end)
        return tree
      end,
    }
    export("ascii", dir, { "* E", ":PROPERTIES:", ":DIR: img", ":END:", "[[attachment:notes.org::*Top][n]]" })
    config.opts.export.filters = {}
    eq({ "file", dir .. "/img/notes.org", "*Top", "file:" .. dir .. "/img/notes.org::*Top" }, seen)
  end)
end)
