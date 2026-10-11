-- :Org migrate_config: converting an nvim-orgmode setup (lua/org/migrate.lua).
local migrate = require("org.migrate")
local config = require("org.config")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

--- nvim-orgmode's own defaults (tests/fixtures/migrate/).
local function their_defaults()
  return dofile(root .. "/tests/fixtures/migrate/nvim_orgmode_defaults.lua")
end

--- The TODO entries of a result, by option name.
local function todos(res)
  local out = {}
  for _, t in ipairs(res.todos) do
    out[t.name] = t.text
  end
  return out
end

--- Run the rendered setup with a stand-in `require("org").setup`, and
--- return the options it is given.
local function run_rendered(lines)
  local got
  local chunk = assert(loadstring(table.concat(lines, "\n")))
  setfenv(
    chunk,
    setmetatable({
      require = function(name)
        assert(name == "org", name)
        return {
          setup = function(opts)
            got = opts
          end,
        }
      end,
    }, { __index = _G })
  )
  chunk()
  return got
end

--- Lines of the rendered setup containing `pat` (plain).
local function grep(lines, pat)
  local out = {}
  for _, l in ipairs(lines) do
    if l:find(pat, 1, true) then
      out[#out + 1] = l
    end
  end
  return out
end

--- Is `path` ("agenda.span") an org.nvim option? Options whose default is
--- nil are found by their `name = nil` line in lua/org/config/.
local nil_defaults
local function is_option(path)
  local t = config.defaults
  local parts = vim.split(path, ".", { plain = true })
  for i, p in ipairs(parts) do
    if type(t) ~= "table" then
      return false
    end
    if t[p] == nil then
      if i < #parts then
        return false
      end
      if not nil_defaults then
        nil_defaults = {}
        for _, f in ipairs(vim.fn.glob(root .. "/lua/org/config/*.lua", false, true)) do
          for _, l in ipairs(vim.fn.readfile(f)) do
            local name = l:match("^%s+([%w_]+) = nil,")
            if name then
              nil_defaults[name] = true
            end
          end
        end
      end
      return nil_defaults[p] == true
    end
    t = t[p]
  end
  return true
end

describe("migrate: options", function()
  it("renames options to their org.nvim names", function()
    local res = migrate.convert({
      org_deadline_warning_days = 7,
      org_agenda_span = "day",
      org_agenda_start_on_weekday = false,
      org_agenda_start_day = "-1d",
      org_hide_leading_stars = true,
      org_hide_emphasis_markers = true,
      org_startup_indented = true,
      org_log_into_drawer = "LOGBOOK",
      org_tags_column = -70,
      org_archive_location = "~/org/archive.org::",
      org_id_method = "ts",
      org_id_prefix = "ID",
      org_id_link_to_org_use_id = true,
      org_edit_src_filetype_map = { julia = "julia" },
      org_todo_keyword_faces = { WAITING = ":foreground blue :weight bold" },
      win_border = "double",
    })
    local o = res.out
    eq(7, o.deadline_warning_days)
    eq("day", o.agenda.span)
    eq(false, o.agenda.start_on_weekday)
    eq("-1d", o.agenda.start_day)
    eq(true, o.ui.hide_leading_stars)
    eq(true, o.ui.hide_emphasis_markers)
    eq(true, o.ui.indent_mode)
    eq("LOGBOOK", o.log_into_drawer)
    eq(-70, o.tags_column)
    eq("~/org/archive.org::", o.archive_location)
    eq({ method = "ts", prefix = "ID" }, o.id)
    eq(true, o.links.use_id)
    eq({ julia = "julia" }, o.src_lang_modes)
    eq({ WAITING = ":foreground blue :weight bold" }, o.ui.todo_keyword_faces)
    eq("double", o.win_border)
    eq(16, res.converted)
    eq({}, res.todos)
  end)

  it("takes agenda files as a string or a list, and drops empty ones", function()
    eq({ "~/org/**/*" }, migrate.convert({ org_agenda_files = "~/org/**/*" }).out.agenda_files)
    eq({ "~/a/*", "~/b.org" }, migrate.convert({ org_agenda_files = { "~/a/*", "~/b.org" } }).out.agenda_files)
    local res = migrate.convert({ org_agenda_files = "", org_default_notes_file = "" })
    eq(nil, res.out.agenda_files)
    eq(nil, res.out.default_notes_file)
    eq("~/r.org", migrate.convert({ org_default_notes_file = "~/r.org" }).out.default_notes_file)
  end)

  it("writes TODO keyword lists as Emacs sequences", function()
    local o = migrate.convert({ org_todo_keywords = { "TODO(t)", "NEXT", "|", "DONE(d)" } }).out
    eq({ "TODO(t) NEXT | DONE(d)" }, o.todo_keywords)
    -- without "|", the last keyword is the done state
    o = migrate.convert({ org_todo_keywords = { "TODO", "WAITING", "DONE" } }).out
    eq({ "TODO WAITING | DONE" }, o.todo_keywords)
  end)

  it("gives keywords of several sequences nvim-orgmode's fast-selection keys", function()
    local res = migrate.convert({
      org_todo_keywords = { { "TODO", "|", "DONE" }, { "BUG(b)", "TEST", "|", "FIXED" } },
    })
    eq({ "TODO(t) | DONE(d)", "BUG(b) TEST | FIXED(f)" }, res.out.todo_keywords)
    ok(res.notes.todo_keywords)
  end)

  it("converts the time grid and its separators", function()
    local o = migrate.convert({
      org_agenda_use_time_grid = false,
      org_agenda_time_grid = {
        type = { "daily" },
        times = { 900, 1700 },
        time_separator = "--",
        time_label = "......",
      },
    }).out
    eq(
      { enabled = false, type = { "daily" }, times = { 900, 1700 }, separator = " -- ", time_string = "......" },
      o.agenda.time_grid
    )
  end)

  it("drops sorting strategies org.nvim doesn't have", function()
    local res = migrate.convert({
      org_agenda_sorting_strategy = {
        agenda = { "time-up", "clocked-up", "priority-down" },
        todo = { "todo-state-up" },
      },
    })
    eq({ agenda = { "time-up", "priority-down" }, todo = { "todo-state-up" } }, res.out.agenda.sorting)
    ok(res.notes["agenda.sorting"][1]:find("clocked-up", 1, true))
  end)

  it("sets the agenda and capture windows from win_split_mode", function()
    local o = migrate.convert({ win_split_mode = "vertical" }).out
    eq("vsplit", o.agenda.window)
    eq("vsplit", o.capture.window)
    eq("split", migrate.convert({ win_split_mode = "horizontal" }).out.agenda.window)
    eq("float", migrate.convert({ win_split_mode = { "float", 0.9 } }).out.capture.window)
    eq("tab", migrate.convert({ win_split_mode = "tabnew" }).out.agenda.window)
    local res = migrate.convert({ win_split_mode = function() end })
    eq(nil, res.out.agenda)
    ok(todos(res).win_split_mode)
  end)

  it("converts values whose form differs", function()
    local o = migrate.convert({
      org_time_stamp_rounding_minutes = 15,
      org_babel_default_header_args = { [":tangle"] = "yes", [":noweb"] = "no" },
      org_highlight_latex_and_related = "entities",
      org_src_window_setup = "vnew",
      org_agenda_show_future_repeats = "next",
    }).out
    eq({ 0, 15 }, o.time_stamp_rounding_minutes)
    eq({ tangle = "yes", noweb = "no" }, o.babel.default_header_args)
    eq({ "latex", "entities" }, o.ui.highlight_latex_and_related)
    eq("vsplit", o.win_split_mode)
    eq("next", o.agenda.show_future_repeats)
    local res = migrate.convert({ org_agenda_show_future_repeats = 3 })
    eq(true, res.out.agenda.show_future_repeats)
    ok(res.notes["agenda.show_future_repeats"])
  end)

  it("converts notifications", function()
    local fn = function() end
    local res = migrate.convert({
      notifications = {
        enabled = true,
        reminder_time = 15,
        notifier = fn,
        cron_enabled = true,
        scheduled_reminder = false,
      },
    })
    eq({ enabled = true, reminder_time = { 15 }, notifier = fn }, res.out.notifications)
    local t = todos(res)
    ok(t["notifications.cron_enabled"])
    ok(t["notifications.scheduled_reminder"])
  end)

  it("lists options without an equivalent, and unknown ones, as TODOs", function()
    local res = migrate.convert({
      org_agenda_min_height = 20,
      org_custom_exports = { f = { label = "RTF" } },
      org_startup_folded = "inherit",
      calendar_week_start_day = 0,
      org_typo_option = true,
      org_id_uuid_program = "uuidgen",
    })
    local t = todos(res)
    ok(t.org_agenda_min_height)
    ok(t.org_custom_exports)
    ok(t.org_startup_folded)
    ok(t.calendar_week_start_day)
    eq("not an nvim-orgmode option", t.org_typo_option)
    -- not needed: neither converted nor a TODO
    eq(nil, t.org_id_uuid_program)
    eq({}, res.out)
  end)

  it("knows every option of nvim-orgmode's defaults", function()
    local res = migrate.convert(their_defaults())
    for _, t in ipairs(res.todos) do
      ok(not t.text:find("not an nvim-orgmode", 1, true), t.name .. ": " .. t.text)
    end
  end)

  it("converts nvim-orgmode's defaults to existing org.nvim options", function()
    local res = migrate.convert(their_defaults())
    local bad = {}
    local function walk(t, path)
      for k, v in pairs(t) do
        local p = path == "" and k or path .. "." .. k
        -- free-form tables: their entries aren't options
        local free = p:match("^capture%.templates")
          or p:match("^agenda%.custom_commands")
          or p:match("^mappings")
          or p:match("^babel%.default_header_args%.")
          or p:match("^agenda%.sorting%.")
          or p:match("^agenda%.time_grid%.")
        if not free and not is_option(p) then
          bad[#bad + 1] = p
        end
        if type(v) == "table" and not vim.islist(v) and not free then
          walk(v, p)
        end
      end
    end
    walk(res.out, "")
    table.sort(bad)
    eq({}, bad)
    eq({}, require("org.health").unknown_options(res.out))
  end)
end)

describe("migrate: capture templates", function()
  it("keeps the fields org.nvim shares", function()
    local o = migrate.convert({
      org_capture_templates = {
        t = { description = "Task", template = "* TODO %?\n  %u", target = "~/org/todo.org", headline = "Inbox" },
        n = { description = "Note", template = { "* %?", "%U" }, prepend = true, regexp = "^appendhere$" },
      },
    }).out
    eq({
      t = { description = "Task", template = "* TODO %?\n  %u", target = "~/org/todo.org", headline = "Inbox" },
      n = { description = "Note", template = { "* %?", "%U" }, prepend = true, regexp = "^appendhere$" },
    }, o.capture.templates)
  end)

  it("turns %(function body) into an expression", function()
    local res = migrate.convert({
      org_capture_templates = {
        r = { description = "R", template = "* %(return vim.fn.getreg('w'))\n%(local x = 1 return x)" },
      },
    })
    eq("* %(vim.fn.getreg('w'))\n%(local x = 1 return x)", res.out.capture.templates.r.template)
    -- the body that isn't one `return` is left with a TODO
    ok(res.notes["capture.templates.r"][1]:find("local x", 1, true))
  end)

  it("notes %n, which is the user name in nvim-orgmode", function()
    local res = migrate.convert({ org_capture_templates = { a = { template = "* %n %?" } } })
    ok(res.notes["capture.templates.a"][1]:find("%n", 1, true))
  end)

  it("expands %<...> in targets with a function", function()
    local res = migrate.convert({
      org_capture_templates = { j = { template = "* %?", target = "~/org/journal/%<%Y-%m>.org" } },
    })
    local opts = run_rendered(migrate.render(res))
    local target = opts.capture.templates.j.target
    eq("function", type(target))
    eq("~/org/journal/" .. os.date("%Y-%m") .. ".org", target())
  end)

  it("converts datetree options", function()
    local res = migrate.convert({
      org_capture_templates = {
        a = { template = "* %?", datetree = true },
        b = { template = "* %?", datetree = { time_prompt = true, tree_type = "week" } },
        c = { template = "* %?", datetree = { tree_type = "day", reversed = true } },
        d = { template = "* %?", datetree = { tree_type = "custom", tree = {} } },
      },
    })
    local t = res.out.capture.templates
    eq({ template = "* %?", datetree = true }, t.a)
    eq({ template = "* %?", datetree = true, time_prompt = true, tree_type = "week" }, t.b)
    eq({ template = "* %?", datetree = true }, t.c)
    ok(res.notes["capture.templates.c"][1]:find("reversed", 1, true))
    ok(res.notes["capture.templates.d"][1]:find("custom", 1, true))
  end)

  it("moves empty_lines out of properties", function()
    local res = migrate.convert({
      org_capture_templates = {
        a = { template = "* %?", properties = { empty_lines = 1 } },
        b = { template = "* %?", properties = { empty_lines = { before = 2, after = 1 } } },
      },
    })
    eq(1, res.out.capture.templates.a.empty_lines)
    eq(nil, res.out.capture.templates.a.properties)
    eq(2, res.out.capture.templates.b.empty_lines_before)
    eq(1, res.out.capture.templates.b.empty_lines_after)
  end)

  it("flattens subtemplates into keys under a group label", function()
    local res = migrate.convert({
      org_capture_templates = {
        e = {
          description = "Event",
          subtemplates = {
            r = { description = "recurring", template = "** %?", headline = "recurring" },
            o = { description = "one-time", template = "** %?", headline = "one-time" },
          },
        },
        w = "Work",
        wt = { description = "Work task", template = "* TODO %?" },
      },
    })
    local t = res.out.capture.templates
    eq("Event", t.e)
    eq({ description = "recurring", template = "** %?", headline = "recurring" }, t.er)
    eq({ description = "one-time", template = "** %?", headline = "one-time" }, t.eo)
    eq("Work", t.w)
    eq({ description = "Work task", template = "* TODO %?" }, t.wt)
  end)

  it("leaves out unknown template fields with a TODO", function()
    local res = migrate.convert({ org_capture_templates = { a = { template = "* %?", whatever = 1 } } })
    eq({ template = "* %?" }, res.out.capture.templates.a)
    ok(res.notes["capture.templates.a"][1]:find("whatever", 1, true))
  end)
end)

describe("migrate: agenda custom commands", function()
  it("renames block options and converts filter presets", function()
    local res = migrate.convert({
      org_agenda_custom_commands = {
        c = {
          description = "Combined",
          types = {
            {
              type = "tags_todo",
              match = '+PRIORITY="A"',
              org_agenda_overriding_header = "High priority",
              org_agenda_todo_ignore_deadlines = "far",
            },
            { type = "agenda", org_agenda_span = "day", org_agenda_files = "~/work/*" },
            {
              type = "tags",
              match = "WORK",
              org_agenda_tag_filter_preset = "NOTES-REFACTOR",
              org_agenda_category_filter_preset = "todos",
              org_agenda_sorting_strategy = { "todo-state-up", "clocked-down" },
              org_agenda_remove_tags = true,
            },
          },
        },
        g = "Group",
      },
    })
    local c = res.out.agenda.custom_commands
    eq("Group", c.g)
    eq("Combined", c.c.description)
    eq({
      type = "tags_todo",
      match = '+PRIORITY="A"',
      header = "High priority",
      todo_ignore_deadlines = "far",
      -- nvim-orgmode applies them to tags_todo blocks
      tags_todo_honor_ignore_options = true,
    }, c.c.types[1])
    eq({ type = "agenda", span = "day", files = { "~/work/*" } }, c.c.types[2])
    eq({
      type = "tags",
      match = "WORK",
      tag_filter_preset = { "+NOTES", "-REFACTOR" },
      category_filter_preset = { "+todos" },
      sorting = { "todo-state-up" },
      remove_tags = true,
    }, c.c.types[3])
  end)

  it("runs a converted command in org.nvim", function()
    local res = migrate.convert({
      org_agenda_custom_commands = {
        w = { description = "Work", types = { { type = "tags", match = "work", org_agenda_overriding_header = "W" } } },
      },
    })
    local block = require("org.agenda").normalize_block(res.out.agenda.custom_commands.w.types[1])
    eq("tags", block.type)
    eq("W", block.header)
  end)
end)

describe("migrate: mappings", function()
  it("moves keys to the org.nvim action names", function()
    local res = migrate.convert({
      mappings = {
        prefix = "<Leader>m",
        global = { org_agenda = "gA", org_capture = { "gC", desc = "Capture" } },
        org = { org_todo = "t", org_schedule = false, org_next_visible_heading = { "}", "gj" } },
        agenda = { org_agenda_later = "L", org_agenda_preview = "p" },
        capture = { org_capture_finalize = "<C-s>" },
        edit_src = { org_edit_src_save_exit = "<C-s>" },
        text_objects = { inner_heading = "iH" },
      },
    })
    local m = res.out.mappings
    eq("<Leader>m", m.prefix)
    eq({ agenda = "gA", capture = "gC" }, m.global)
    eq({ todo_next = "t", schedule = false, next_heading = { "}", "gj" } }, m.org)
    eq({ later = "L", show = "p" }, m.agenda)
    eq({ finalize = "<C-s>" }, m.capture)
    eq({ save_exit = "<C-s>" }, m.edit_src)
    eq({ inner_heading = "iH" }, m.text_objects)
    -- `desc` is dropped with a note
    ok(res.notes["mappings.global.capture"][1]:find("desc", 1, true))
  end)

  it("notes a key that is another action's default in org.nvim", function()
    local res = migrate.convert({ mappings = { org = { org_toggle_archive_tag = "<prefix>A" } } })
    eq("<prefix>A", res.out.mappings.org.toggle_archive_tag)
    ok(res.notes["mappings.org.toggle_archive_tag"][1]:find("attach", 1, true))
    -- with the user's prefix too
    res = migrate.convert({ mappings = { prefix = ",", org = { org_deadline = ",id" } } })
    ok(res.notes["mappings.org.deadline"][1]:find("insert_drawer", 1, true))
  end)

  it("lists mappings without an equivalent as TODOs", function()
    local res = migrate.convert({
      mappings = {
        disable_all = true,
        org_return_uses_meta_return = true,
        org = { org_return = "<CR>", org_bogus = "x" },
        note = { org_note_finalize = "<C-s>" },
        text_objects = { inner_subtree_from_root = "Or" },
        frobnicate = {},
      },
    })
    eq({ disable_all = true }, res.out.mappings)
    local t = todos(res)
    ok(t["mappings.org_return_uses_meta_return"])
    ok(t["mappings.org.org_return"])
    eq("not an nvim-orgmode mapping", t["mappings.org.org_bogus"])
    ok(t["mappings.note.org_note_finalize"])
    ok(t["mappings.text_objects.inner_subtree_from_root"])
    ok(t["mappings.frobnicate"])
  end)

  it("maps every default nvim-orgmode key to an existing action", function()
    local view = require("org.agenda.view")
    local actions = require("org.actions").list
    local objects = {}
    for _, o in ipairs(require("org.textobjects").list) do
      objects[o[1]] = true
    end
    local missing, bad = {}, {}
    for section, keys in pairs(their_defaults().mappings) do
      if type(keys) == "table" then
        for name in pairs(keys) do
          local to = migrate.MAPS[section] and migrate.MAPS[section][name]
          if to == nil then
            missing[#missing + 1] = section .. "." .. name
          elseif type(to) == "table" then
            local known = (to[1] == "agenda" and view.actions[to[2]])
              or (to[1] == "text_objects" and objects[to[2]])
              or ((to[1] == "capture" or to[1] == "edit_src") and config.defaults.mappings[to[1]][to[2]] ~= nil)
              or ((to[1] == "org" or to[1] == "global") and actions[to[2]])
            if not known then
              bad[#bad + 1] = section .. "." .. name .. " -> " .. to[1] .. "." .. to[2]
            end
          end
        end
      end
    end
    eq({}, missing)
    eq({}, bad)
  end)

  it("suggests nvim-orgmode's default keys that differ", function()
    local res = migrate.convert({ mappings = { org = { org_deadline = "<prefix>d" } } })
    local org = table.concat(res.mapping_defaults.org, "\n")
    -- set by the user: not suggested
    ok(not org:find("deadline =", 1, true))
    ok(org:find('schedule = "<prefix>is"', 1, true))
    ok(org:find("insert_subheading", 1, true))
    -- a key whose owner moves away isn't a conflict
    local agenda = table.concat(res.mapping_defaults.agenda, "\n")
    ok(agenda:find('goto_date = "J", -- org.nvim: gd\n', 1, true))
  end)
end)

describe("migrate: rendering", function()
  it("writes a setup() that runs and gives the converted options", function()
    local res = migrate.convert({
      org_agenda_files = { "~/org/*" },
      org_agenda_span = 14,
      org_todo_keywords = { "TODO", "|", "DONE" },
      org_capture_templates = { t = { description = 'say "hi"\\', template = "* TODO %?\n\t%u" } },
      mappings = { agenda = { org_agenda_goto = "<Tab>" } },
    })
    local lines = migrate.render(res, { source = "init.lua" })
    local opts = run_rendered(lines)
    eq({ "~/org/*" }, opts.agenda_files)
    eq(14, opts.agenda.span)
    eq({ "TODO | DONE" }, opts.todo_keywords)
    eq({ description = 'say "hi"\\', template = "* TODO %?\n\t%u" }, opts.capture.templates.t)
    eq("<Tab>", opts.mappings.agenda["goto"])
    eq("~/org", opts.org_directory)
    ok(#grep(lines, "-- from init.lua") == 1)
  end)

  it("writes TODO comments and the values of options it can't convert", function()
    local res = migrate.convert({ org_agenda_min_height = 20, org_capture_templates = { a = { template = "%n" } } })
    local lines = migrate.render(res)
    ok(#grep(lines, "-- TODO: org_agenda_min_height:") == 1)
    ok(#grep(lines, "-- org_agenda_min_height = 20,") == 1)
    ok(#grep(lines, "-- TODO: %n is your user name") == 1)
    -- nvim-orgmode's defaults are offered, commented out
    ok(#grep(lines, "-- adapt_indentation = true,") == 1)
    -- TODO comments are wrapped
    for _, l in ipairs(lines) do
      if l:match("^%s*%-%- TODO") or l:match("^%s*%-%-      ") then
        ok(#l <= 80, l)
      end
    end
    ok(#grep(lines, "  --       ") > 0)
    run_rendered(lines)
  end)

  it("does not offer nvim-orgmode's default for an option that is set", function()
    local lines = migrate.render(migrate.convert({ org_adapt_indentation = false }))
    eq(0, #grep(lines, "-- adapt_indentation = true,"))
    eq(1, #grep(lines, "  adapt_indentation = false,"))
  end)
end)

describe("migrate: reading a config", function()
  it("records require('orgmode').setup()", function()
    local opts = assert(migrate.read_setup("require('orgmode').setup({ org_agenda_span = 'day' })", "=t"))
    eq({ org_agenda_span = "day" }, opts)
  end)

  it("reads a lazy.nvim spec: opts table, opts function, config function", function()
    eq(
      { org_agenda_span = "day" },
      migrate.read_setup('return { "nvim-orgmode/orgmode", opts = { org_agenda_span = "day" } }', "=t")
    )
    eq(
      { org_ellipsis = "…" },
      migrate.read_setup('return { "nvim-orgmode/orgmode", opts = function(_, o) o.org_ellipsis = "…" end }', "=t")
    )
    eq(
      { org_tags_column = 0 },
      migrate.read_setup(
        [[return {
          { "folke/lazy.nvim" },
          { "nvim-orgmode/orgmode", config = function() require("orgmode").setup({ org_tags_column = 0 }) end },
        }]],
        "=t"
      )
    )
  end)

  it("reads a returned table of options", function()
    eq({ org_agenda_files = "~/x" }, migrate.read_setup('return { org_agenda_files = "~/x" }', "=t"))
  end)

  it("fails when there is no nvim-orgmode setup", function()
    local opts, err = migrate.read_setup("local x = 1", "=t")
    eq(nil, opts)
    ok(err:find("no nvim-orgmode setup", 1, true))
    opts, err = migrate.read_setup("this is not lua", "=t")
    eq(nil, opts)
    ok(err)
    opts, err = migrate.read_setup("error('boom')", "=t")
    eq(nil, opts)
    ok(err:find("boom", 1, true))
  end)

  it("ignores keymaps, options, commands and other plugins of the config", function()
    local before = vim.o.conceallevel
    local opts = migrate.read_setup(
      [[
      vim.keymap.set("n", "<leader>Zq", "<cmd>echo 1<CR>")
      vim.opt.conceallevel = 2
      vim.o.conceallevel = 2
      vim.api.nvim_create_user_command("ZzMigrate", "echo 1", {})
      vim.api.nvim_create_autocmd("FileType", { callback = function() end })
      vim.cmd("let g:zz_migrate = 1")
      require("cmp").setup({ sources = {} })
      require("orgmode").setup({ org_agenda_files = { vim.fn.expand("~") .. "/org/*" } })
    ]],
      "=t"
    )
    eq({ vim.fn.expand("~") .. "/org/*" }, opts.org_agenda_files)
    eq(before, vim.o.conceallevel)
    eq("", vim.fn.maparg("<leader>Zq", "n"))
    eq(0, vim.fn.exists(":ZzMigrate"))
    eq(nil, vim.g.zz_migrate)
  end)

  it("copies functions from the config into the result", function()
    local text = table.concat({
      "require('orgmode').setup({",
      "  notifications = {",
      "    notifier = function(tasks)",
      "      return #tasks",
      "    end,",
      "  },",
      "  win_split_mode = function(name) vim.cmd('new') end,",
      "})",
    }, "\n")
    local lines = assert(migrate.convert_source(text, "init.lua"))
    local s = table.concat(lines, "\n")
    ok(s:find("    notifier = function(tasks)\n      return #tasks\n    end,", 1, true))
    ok(s:find("-- TODO: copied from init.lua:3", 1, true))
    -- a function with no equivalent is shown commented out
    ok(s:find("-- win_split_mode = function(name) vim.cmd('new') end,", 1, true))
    local opts = run_rendered(lines)
    eq(2, opts.notifications.notifier({ 1, 2 }))
  end)
end)

describe("migrate: :Org migrate_config", function()
  local dir = vim.fn.tempname()
  local ts_start = vim.treesitter.start

  before_each(function()
    -- the lua ftplugin starts tree-sitter, whose parser the test runtime may lack
    vim.treesitter.start = function() end
  end)

  after_each(function()
    vim.treesitter.start = ts_start
    vim.cmd("silent! %bwipeout!")
  end)

  it("converts a file into a new scratch buffer and leaves the file alone", function()
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/orgmode.lua"
    local text = {
      "require('orgmode').setup({",
      "  org_agenda_files = '~/orgfiles/**/*',",
      "  org_agenda_min_height = 10,",
      "})",
    }
    vim.fn.writefile(text, file)
    local stat = vim.uv.fs_stat(file)
    local notified
    local notify = vim.notify
    vim.notify = function(msg)
      notified = msg
    end
    require("org.commands").run({ fargs = { "migrate_config", file }, args = "migrate_config " .. file })
    vim.notify = notify
    local buf = vim.api.nvim_get_current_buf()
    eq("nofile", vim.bo[buf].buftype)
    eq("lua", vim.bo[buf].filetype)
    local lines = buf_lines(buf)
    ok(#grep(lines, 'agenda_files = { "~/orgfiles/**/*" },') == 1)
    ok(#grep(lines, "-- TODO: org_agenda_min_height:") == 1)
    ok(notified:find("converted 1 option", 1, true))
    eq(text, vim.fn.readfile(file))
    eq(stat.mtime.nsec, vim.uv.fs_stat(file).mtime.nsec)
  end)

  it("converts the current Lua buffer, unsaved changes included", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_name(buf, dir .. "/unsaved.lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "require('orgmode').setup({ org_agenda_span = 'month' })" })
    local notify = vim.notify
    vim.notify = function() end
    require("org.actions").run("migrate_config")
    vim.notify = notify
    local out = vim.api.nvim_get_current_buf()
    ok(out ~= buf)
    ok(#grep(buf_lines(out), 'span = "month",') == 1)
    eq(true, vim.bo[buf].modified)
  end)

  it("refuses a buffer that isn't Lua", function()
    org_buffer({ "* Not lua" })
    local errors = {}
    local utils = require("org.utils")
    local err = utils.error
    utils.error = function(msg)
      errors[#errors + 1] = msg
    end
    local before = #vim.api.nvim_list_bufs()
    require("org.migrate").command("")
    utils.error = err
    eq(before, #vim.api.nvim_list_bufs())
    ok(errors[1]:find("Lua file", 1, true))
  end)

  it("completes file names", function()
    local items = require("org.commands").complete(root .. "/README", "Org migrate_config " .. root .. "/README")
    ok(vim.tbl_contains(items, root .. "/README.md"))
  end)
end)
