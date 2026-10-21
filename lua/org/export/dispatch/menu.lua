---@mod org.export.dispatch.menu The export dispatcher
---
--- The export menu (org-export-dispatch), its extension entries and the
--- :Org export / :Org publish commands.
---
--- Part of org.export, which loads it.

local utils = require("org.utils")
local shared = require("org.export.dispatch.shared")

local M = require("org.export")

local cfg = shared.cfg

---------------------------------------------------------------------------
-- Dispatcher (org-export-dispatch)
---------------------------------------------------------------------------

--- Extra dispatcher entries, as Emacs back-ends add theirs with
--- `:menu-entry` (ox-hugo's `H`). Each is `{ key, label, items }`, where an
--- item's `value.fn(state, ctx)` runs the export: `state` holds the
--- dispatcher options (subtree, body_only, visible_only, async, force),
--- `ctx.subtree_line` the cursor line. Extensions add theirs with
--- |M.register_menu_entry|.
---@type table[]
M.menu_entries = {}

--- Add (or replace, by key) a dispatcher entry.
---@param entry { key: string, label: string, items: table[] }
function M.register_menu_entry(entry)
  M.unregister_menu_entry(entry.key)
  M.menu_entries[#M.menu_entries + 1] = entry
end

--- Remove the dispatcher entry with `key`.
---@param key string
function M.unregister_menu_entry(key)
  M.menu_entries = vim.tbl_filter(function(e)
    return e.key ~= key
  end, M.menu_entries)
end

local function dispatcher_items(state)
  local function onoff(v)
    return v and "on" or "off"
  end
  local items = {
    { heading = true, label = "Options" },
    { key = "b", label = "Body only", state = onoff(state.body_only), value = { toggle = "body_only" } },
    {
      key = "s",
      label = "Export scope",
      state = state.subtree and "subtree" or "buffer",
      value = { toggle = "subtree" },
    },
    { key = "v", label = "Visible only", state = onoff(state.visible_only), value = { toggle = "visible_only" } },
    { key = "f", label = "Force publishing", state = onoff(state.force), value = { toggle = "force" } },
    { key = "a", label = "Async export", state = onoff(state.async), value = { toggle = "async" } },
    { heading = true, label = "Export" },
    {
      key = "c",
      label = "Export to iCalendar",
      items = {
        { key = "f", label = "Current file", value = { ical = "file" } },
        { key = "a", label = "All agenda files", value = { ical = "agenda" } },
        { key = "c", label = "Combine all agenda files", value = { ical = "combine" } },
      },
    },
    {
      key = "h",
      label = "Export to HTML",
      items = {
        { key = "H", label = "As HTML buffer", value = { fmt = "html", to_buffer = true } },
        { key = "h", label = "As HTML file", value = { fmt = "html" } },
        { key = "o", label = "As HTML file and open", value = { fmt = "html", open = true } },
      },
    },
    {
      key = "l",
      label = "Export to LaTeX",
      items = {
        { key = "L", label = "As LaTeX buffer", value = { fmt = "latex", to_buffer = true } },
        { key = "l", label = "As LaTeX file", value = { fmt = "latex" } },
        { key = "p", label = "As PDF file", value = { fmt = "pdf" } },
        { key = "o", label = "As PDF file and open", value = { fmt = "pdf", open = true } },
        { key = "B", label = "As LaTeX buffer (Beamer)", value = { fmt = "beamer", to_buffer = true } },
        { key = "b", label = "As LaTeX file (Beamer)", value = { fmt = "beamer" } },
        { key = "P", label = "As PDF file (Beamer)", value = { fmt = "beamer-pdf" } },
        { key = "O", label = "As PDF file and open (Beamer)", value = { fmt = "beamer-pdf", open = true } },
      },
    },
    {
      key = "i",
      label = "Export to Texinfo",
      items = {
        { key = "t", label = "As TEXI file", value = { fmt = "texinfo" } },
        { key = "i", label = "As INFO file", value = { fmt = "info" } },
        { key = "o", label = "As INFO file and open", value = { fmt = "info", open = true } },
      },
    },
    {
      key = "k",
      label = "Export with KOMA Scrlttr2",
      items = {
        { key = "L", label = "As LaTeX buffer", value = { fmt = "koma-letter", to_buffer = true } },
        { key = "l", label = "As LaTeX file", value = { fmt = "koma-letter" } },
        { key = "p", label = "As PDF file", value = { fmt = "koma-pdf" } },
        { key = "o", label = "As PDF file and open", value = { fmt = "koma-pdf", open = true } },
      },
    },
    {
      key = "M",
      label = "Export to MAN",
      items = {
        { key = "m", label = "As MAN file", value = { fmt = "man" } },
        { key = "p", label = "As PDF file", value = { fmt = "man-pdf" } },
        { key = "o", label = "As PDF file and open", value = { fmt = "man-pdf", open = true } },
      },
    },
    {
      key = "m",
      label = "Export to Markdown",
      items = {
        { key = "M", label = "To temporary buffer", value = { fmt = "md", to_buffer = true } },
        { key = "m", label = "To file", value = { fmt = "md" } },
        { key = "o", label = "To file and open", value = { fmt = "md", open = true } },
        { key = "G", label = "GitHub flavoured, to temporary buffer", value = { fmt = "gfm", to_buffer = true } },
        { key = "g", label = "GitHub flavoured, to file", value = { fmt = "gfm" } },
      },
    },
    {
      key = "O",
      label = "Export to Org",
      items = {
        { key = "O", label = "As Org buffer", value = { fmt = "org", to_buffer = true } },
        { key = "o", label = "As Org file", value = { fmt = "org" } },
        { key = "v", label = "As Org file and open", value = { fmt = "org", open = true } },
      },
    },
    {
      key = "o",
      label = "Export to ODT",
      items = {
        { key = "o", label = "As ODT file", value = { fmt = "odt" } },
        { key = "O", label = "As ODT file and open", value = { fmt = "odt", open = true } },
      },
    },
    {
      key = "d",
      label = "Export to DOCX (pandoc)",
      items = {
        { key = "d", label = "As DOCX file", value = { fmt = "docx" } },
        { key = "o", label = "As DOCX file and open", value = { fmt = "docx", open = true } },
      },
    },
    {
      key = "t",
      label = "Export to Plain Text",
      items = {
        { key = "A", label = "As ASCII buffer", value = { fmt = "ascii", to_buffer = true } },
        { key = "a", label = "As ASCII file", value = { fmt = "ascii" } },
        { key = "L", label = "As Latin1 buffer", value = { fmt = "latin1", to_buffer = true } },
        { key = "l", label = "As Latin1 file", value = { fmt = "latin1" } },
        { key = "U", label = "As UTF-8 buffer", value = { fmt = "utf8", to_buffer = true } },
        { key = "u", label = "As UTF-8 file", value = { fmt = "utf8" } },
      },
    },
    {
      key = "P",
      label = "Publish",
      items = {
        { key = "f", label = "Current file", value = { publish = "file" } },
        { key = "p", label = "Current project", value = { publish = "current" } },
        { key = "x", label = "Choose project", value = { publish = "choose" } },
        { key = "a", label = "All projects", value = { publish = "all" } },
      },
    },
    { key = "p", label = "Other format via pandoc", value = { fmt = "__pandoc" } },
    { key = "&", label = "Export stack", value = { stack = true } },
    { key = "#", label = "Insert default export template", value = { template = true } },
  }
  -- extensions' entries go before "Publish", ordered by key like the rest
  local publish
  for i, it in ipairs(items) do
    if it.key == "P" and it.items then
      publish = i
    end
  end
  for _, e in ipairs(M.menu_entries) do
    table.insert(items, publish, e)
    publish = publish + 1
  end
  return items
end

--- Ctrl-keys of the dispatcher options (C-b C-s C-v C-f C-a in Emacs).
local CTRL_TOGGLES = { ["\2"] = "b", ["\19"] = "s", ["\22"] = "v", ["\6"] = "f", ["\1"] = "a" }

--- The compact dispatcher of `export.dispatch_use_expert_ui`
--- (org-export-dispatch-use-expert-ui): no menu window, only a prompt
--- "Export command (C-bvsfa) [keys]: " with the active options
--- highlighted. `?` switches to the standard menu.
local function expert_menu(items, state)
  local level = items
  local first
  while true do
    local chunks = { { "Export command (C-", "Question" } }
    for _, k in ipairs({ "b", "v", "s", "f", "a" }) do
      local field = ({ b = "body_only", v = "visible_only", s = "subtree", f = "force", a = "async" })[k]
      chunks[#chunks + 1] = { k, state[field] and "Special" or "Question" }
    end
    local keys = {}
    for _, it in ipairs(level) do
      if not it.heading and not (first == nil and #it.key == 1 and ("bsvfa"):find(it.key, 1, true)) then
        keys[#keys + 1] = it.key
      end
    end
    if not first then
      keys[#keys + 1] = "?"
    end
    -- q quits unless an entry (a user's backend key) takes it
    local q_quits = require("org.ui").q_quits(level)
    if q_quits then
      keys[#keys + 1] = "q"
    end
    chunks[#chunks + 1] = { ") [" .. table.concat(keys) .. "]: ", "Question" }
    vim.api.nvim_echo(chunks, false, {})
    local ok, ch = pcall(vim.fn.getcharstr)
    vim.api.nvim_echo({ { "" } }, false, {})
    if not ok or ch == "\27" or ch == "\3" or (ch == "q" and q_quits) then
      if ch == "q" and first then
        level, first = items, nil
      else
        return nil
      end
    elseif ch == "?" and not first then
      return "standard"
    elseif CTRL_TOGGLES[ch] then
      for _, it in ipairs(items) do
        if not it.heading and it.key == CTRL_TOGGLES[ch] then
          return it.value
        end
      end
    else
      local chosen
      for _, it in ipairs(level) do
        if not it.heading and it.key == ch then
          chosen = it
          break
        end
      end
      if not chosen then
        utils.warn("No menu entry for key: " .. ch)
        return nil
      end
      if chosen.items then
        level, first = chosen.items, ch
      else
        return chosen.value
      end
    end
  end
end

--- Emacs-like export dispatcher (C-c C-e). The options start from
--- `export.initial_scope`, `export.body_only`, `export.visible_only`,
--- `export.force_publishing` and `export.in_background`.
function M.prompt()
  if not utils.ensure_org() then
    return
  end
  local c = cfg()
  local state = {
    subtree = c.initial_scope == "subtree",
    body_only = c.body_only == true,
    visible_only = c.visible_only == true,
    force = c.force_publishing == true,
    async = c.in_background == true,
  }
  local subtree_line = vim.api.nvim_win_get_cursor(0)[1]
  local expert = c.dispatch_use_expert_ui == true
  while true do
    local items = dispatcher_items(state)
    local choice
    if expert then
      choice = expert_menu(items, state)
      if choice == "standard" then
        expert = false
        choice = require("org.ui").menu({ title = "Org Export", items = items })
      end
    else
      choice = require("org.ui").menu({ title = "Org Export", items = items })
    end
    if not choice then
      return
    end
    if choice.toggle then
      state[choice.toggle] = not state[choice.toggle]
    elseif choice.fn then
      return choice.fn(state, { subtree_line = subtree_line })
    elseif choice.stack then
      return M.stack_show()
    elseif choice.template then
      local cats = { "default" }
      for _, n in ipairs({
        "ascii",
        "beamer",
        "html",
        "icalendar",
        "koma-letter",
        "latex",
        "man",
        "md",
        "odt",
        "org",
        "texinfo",
      }) do
        cats[#cats + 1] = n
      end
      local cat = require("org.ui").choose({
        prompt = "Options category: ",
        title = "Insert export template",
        items = cats,
        default = "default",
      })
      if not cat or cat == "" then
        return
      end
      return M.insert_template({ subtree = state.subtree, backend = cat })
    elseif choice.ical then
      local ical = require("org.export.icalendar")
      if choice.ical == "file" then
        return ical.export_file(0, { async = state.async })
      elseif choice.ical == "agenda" then
        return ical.export_agenda_files({ async = state.async })
      end
      return ical.combine_agenda_files({ async = state.async })
    elseif choice.publish then
      local pub = require("org.export.publish")
      local async = state.async or nil
      if choice.publish == "file" then
        return pub.publish_current_file(state.force, async)
      elseif choice.publish == "current" then
        return pub.publish_current_project(state.force, async)
      elseif choice.publish == "all" then
        return pub.publish_all(state.force, async)
      end
      local names = {}
      for _, p in ipairs(pub.projects()) do
        names[#names + 1] = p[1]
      end
      local name = require("org.ui").choose({ prompt = "Publish project: ", items = names })
      if name and name ~= "" then
        return pub.publish_project(name, state.force, async)
      end
      return
    else
      local fmt = choice.fmt
      if fmt == "__pandoc" then
        fmt = utils.input({ prompt = "Pandoc output format: ", default = "rst" })
        if not fmt or fmt == "" then
          return
        end
      end
      local opts = {
        subtree = state.subtree,
        subtree_line = state.subtree and subtree_line or nil,
        body_only = state.body_only,
        visible_only = state.visible_only,
        to_buffer = choice.to_buffer,
        open = choice.open,
        interactive = true,
      }
      if state.async then
        return M.export_async(fmt, opts)
      end
      return M.export(fmt, opts)
    end
  end
end

--- :Org export [format] [subtree] [body] [visible] [buffer] [open] [async]
function M.command(args)
  local words = vim.split(vim.trim(args or ""), "%s+", { trimempty = true })
  if #words == 0 then
    return M.prompt()
  end
  local opts = { interactive = true }
  for i = 2, #words do
    local w = words[i]
    if w == "subtree" then
      opts.subtree = true
    elseif w == "body" or w == "body-only" then
      opts.body_only = true
    elseif w == "visible" or w == "visible-only" then
      opts.visible_only = true
    elseif w == "buffer" then
      opts.to_buffer = true
    elseif w == "open" then
      opts.open = true
    elseif w == "async" then
      opts.async = true
    end
  end
  if opts.async then
    return M.export_async(words[1], opts)
  end
  return M.export(words[1], opts)
end

--- :Org publish [project|all|file] [force]
function M.publish_command(args)
  local words = vim.split(vim.trim(args or ""), "%s+", { trimempty = true })
  local force = vim.tbl_contains(words, "force")
  local pub = require("org.export.publish")
  local target = words[1]
  if not target or target == "force" or target == "current" then
    return pub.publish_current_project(force)
  elseif target == "all" then
    return pub.publish_all(force)
  elseif target == "file" then
    return pub.publish_current_file(force)
  end
  return pub.publish_project(target, force)
end
