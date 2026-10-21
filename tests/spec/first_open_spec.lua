-- What opening an org file loads (tests/helpers/first_open.lua, in a
-- Neovim of its own): the editing, folding and drawing of a plain file,
-- not the subsystems that only a command or an agenda needs. A module on
-- the deny-list here loading again means something now requires it when a
-- buffer is attached, drawn or folded: make that require lazy (see
-- "Performance budgets" in CONTRIBUTING.md). The times are budgeted in
-- perf_budgets_spec.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

--- Run the helper on `file`: the decoded JSON line it prints.
local function first_open(file)
  local res = vim
    .system({ vim.v.progpath, "--clean", "--headless", "-l", root .. "/tests/helpers/first_open.lua", root, file }, {
      text = true,
    })
    :wait(60000)
  eq(0, res.code, res.stderr)
  local line = vim.split(vim.trim(res.stdout), "\n")
  return vim.json.decode(line[#line])
end

-- Prefixes of the modules opening a file must not load (`except`: the
-- light parts that each subsystem keeps for every buffer).
local DENY = {
  { "org.agenda", except = { "org.agenda.index" } },
  { "org.archive" },
  { "org.babel" },
  { "org.calendar" },
  { "org.capture" },
  { "org.clock", except = { "org.clock.attach" } },
  { "org.columns" },
  { "org.completion" },
  { "org.crypt" },
  { "org.customize" },
  { "org.edit" },
  { "org.export" },
  { "org.links", except = { "org.links.schemes" } },
  { "org.lint" },
  { "org.lists.", except = { "org.lists.shared" } },
  { "org.menu_defs" },
  { "org.mobile" },
  { "org.org_mouse" },
  { "org.pickers" },
  { "org.refile" },
  { "org.speed" },
  { "org.structure" },
  { "org.table", except = { "org.table.attach", "org.table.typing" } },
  { "org.textobjects" },
  { "org.timestamps" },
  { "org.ui.images", except = { "org.ui.images.startup" } },
}

--- The modules of `modules` that DENY lists.
local function denied(modules)
  local out = {}
  for _, name in ipairs(modules) do
    for _, d in ipairs(DENY) do
      local prefix = d[1]
      local match = name == prefix
        or name:sub(1, #prefix) == prefix and (prefix:sub(-1) == "." or name:sub(#prefix + 1, #prefix + 1) == ".")
      if match and not vim.tbl_contains(d.except or {}, name) then
        out[#out + 1] = name
      end
    end
  end
  return out
end

-- About what a plain file loads now (42 modules), with room to grow; a
-- large jump means a subsystem started loading with every buffer.
local MAX_MODULES = 60

describe("first open", function()
  local result

  before_each(function()
    result = result or first_open(root .. "/tests/fixtures/first_open.org")
  end)

  it("setup() loads only the entry points", function()
    eq({}, denied(result.setup_modules))
    ok(#result.setup_modules <= 20, ("setup() loaded %d org modules"):format(#result.setup_modules))
  end)

  it("opening a plain file loads none of the subsystems used only on demand", function()
    eq({}, denied(result.modules))
  end)

  it("opening a plain file loads a bounded number of modules", function()
    ok(
      #result.modules <= MAX_MODULES,
      ("%d org modules loaded (at most %d):\n%s"):format(
        #result.modules,
        MAX_MODULES,
        table.concat(result.modules, "\n")
      )
    )
  end)

  it("still realigns a table on InsertLeave and clears the clock display on edits", function()
    local buf = org_buffer({ "* H", "| a | bb |", "| ccc | d |" }, { 2, 2 })
    vim.cmd("doautocmd InsertLeave")
    eq({ "| a   | bb |", "| ccc | d  |" }, vim.list_slice(buf_lines(buf), 2, 3))
    local ns = vim.api.nvim_create_namespace("org.clock.display")
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {})
    vim.cmd("doautocmd TextChanged")
    eq({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
  end)

  it("still starts beamer mode with #+STARTUP: beamer or startup_with_beamer_mode", function()
    local buf = org_buffer({ "#+STARTUP: beamer", "* H" }, { 2, 0 })
    eq(true, vim.b[buf].org_beamer_mode)
    local beamer = require("org.export.beamer_mode")
    beamer.mode(buf, false)
    buf = org_buffer({ "* H" }, { 1, 0 })
    ok(not beamer.enabled(buf))
    local config = require("org.config")
    config.opts.startup_with_beamer_mode = true
    buf = org_buffer({ "* H" }, { 1, 0 })
    config.opts.startup_with_beamer_mode = false
    ok(beamer.enabled(buf))
    beamer.mode(buf, false)
  end)

  it("still runs speed commands and binds the text objects", function()
    local config = require("org.config")
    config.opts.use_speed_commands = true
    org_buffer({ "* A", "** B", "* C" }, { 1, 0 })
    vim.api.nvim_feedkeys("in", "xt", false)
    vim.wait(50, function()
      return vim.api.nvim_win_get_cursor(0)[1] == 2
    end)
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
    config.opts.use_speed_commands = false
    eq(2, vim.api.nvim_win_get_cursor(0)[1])
    local buf = org_buffer({ "* A", "text", "* B" }, { 2, 0 })
    vim.cmd("normal dar")
    eq({ "* B" }, buf_lines(buf))
  end)

  it("builds the menus on the first menu command, not before", function()
    local menu = require("org.menu")
    eq(false, menu._live)
    local function menus()
      local found, m = pcall(vim.fn.menu_get, "Org")
      return found and #m or 0
    end
    org_buffer({ "* H" })
    eq(0, menus())
    eq(true, menu.is_menu_cmdline("emenu Org."))
    eq(true, menu.is_menu_cmdline("silent! popup Org"))
    eq(true, menu.is_menu_cmdline("2nme x y"))
    eq(false, menu.is_menu_cmdline("messages"))
    eq(false, menu.is_menu_cmdline("pop"))
    vim.api.nvim_feedkeys(":emenu Org\27", "xt", false)
    eq(true, menu._live)
    eq(1, menus())
    vim.cmd("enew!")
    eq(0, menus())
  end)

  it("the deny-list matches what it should", function()
    eq(
      { "org.agenda.view", "org.clock", "org.lists.struct", "org.table" },
      denied({
        "org.agenda.index",
        "org.agenda.view",
        "org.clock",
        "org.clock.attach",
        "org.clocks_unrelated",
        "org.lists",
        "org.lists.shared",
        "org.lists.struct",
        "org.table",
        "org.table.attach",
      })
    )
  end)
end)

-- org.lazy.parts: a facade's parts load on first use of one of them.
describe("lazy parts", function()
  local loads

  before_each(function()
    loads = {}
    for _, name in ipairs({ "t_facade", "t_shared", "t_part1", "t_part2" }) do
      package.loaded[name] = nil
    end
    package.preload.t_shared = function()
      return {}
    end
    package.preload.t_facade = function()
      local M = { own = 1 }
      require("org.lazy").parts(M, require("t_shared"), { "t_part1", "t_part2" })
      return M
    end
    package.preload.t_part1 = function()
      loads[#loads + 1] = "t_part1"
      local M = require("t_facade")
      require("t_shared").helper = function()
        return "helper"
      end
      M.one = function()
        return "one"
      end
      M.stub_me = function()
        return "real"
      end
      return true
    end
    package.preload.t_part2 = function()
      loads[#loads + 1] = "t_part2"
      local M = require("t_facade")
      M.two = function()
        return require("t_shared").helper()
      end
      return true
    end
  end)

  after_each(function()
    for _, name in ipairs({ "t_facade", "t_shared", "t_part1", "t_part2" }) do
      package.loaded[name] = nil
      package.preload[name] = nil
    end
  end)

  it("the facade's own fields don't load them", function()
    local M = require("t_facade")
    eq(1, M.own)
    eq({}, loads)
  end)

  it("reading a part's field loads all parts, in order", function()
    local M = require("t_facade")
    eq("helper", M.two())
    eq({ "t_part1", "t_part2" }, loads)
    eq("one", M.one())
    eq(nil, getmetatable(M))
    eq(nil, getmetatable(require("t_shared")))
  end)

  it("a field read from the shared table loads them", function()
    require("t_facade")
    eq("helper", require("t_shared").helper())
    eq({ "t_part1", "t_part2" }, loads)
  end)

  it("a field set on the facade first loads them, so a stub isn't overwritten", function()
    local M = require("t_facade")
    M.stub_me = function()
      return "stub"
    end
    eq("stub", M.stub_me())
    eq({ "t_part1", "t_part2" }, loads)
  end)

  it("a missing field loads them once and is nil", function()
    local M = require("t_facade")
    eq(nil, M.nothing)
    eq(nil, M.nothing)
    eq({ "t_part1", "t_part2" }, loads)
  end)
end)
