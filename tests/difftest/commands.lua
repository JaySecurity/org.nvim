-- The "commands" oracle of the differential test: a short seeded sequence
-- of editing commands (promote, move, TODO, priority, clock, checkbox,
-- timestamp, sort, insert heading, archive sibling, refile) replayed on a
-- document, in org.nvim through the action registry (lua/org/actions.lua)
-- and in Emacs through the interactive commands
-- (scripts/emacs-parity/difftest.el, `difftest-oracle-commands`); the
-- buffers after each step are compared. Keep the two sides in step.
--
-- A plan is a list of steps { cmd, k[, k2] }: `k` picks the target as the
-- k-th (mod the count) line of its kind in the buffer *at that step*, so
-- a plan still applies when the minimiser shrinks the document:
--
--   heading   a line "^\*{1,14} " (not an inline task)
--   checkbox  a list item with a checkbox ("- [ ]", "1. [X]", ...)
--   timestamp the first <yyyy-mm-dd or [yyyy-mm-dd of a line, the
--             cursor on its day
--
-- `refile`'s k2 picks the destination among the headings outside the
-- subtree at k. A step with no target leaves the buffer alone.
--
-- The plan comes from the document's seed (its file is d<seed>.org) and
-- travels to Emacs as the fourth field of the request (plan encoded as
-- "cmd k[ k2];cmd k..."). The output is, per step, "=== <i> <step>" and
-- the buffer after it.

local fuzz = require("tests.helpers.fuzz")

local M = {}

---@class difftest.Step
---@field cmd string
---@field k integer
---@field k2? integer

--- The commands: name, kind of target, and org.nvim's side (the cursor is
--- on the target; `buf` the buffer, `dest` refile's destination line).
---@type { name: string, target: string, run: fun(ctx: table) }[]
M.COMMANDS = {
  {
    name = "promote-subtree",
    target = "heading",
    run = function(c)
      c.action("promote_subtree")
    end,
  },
  {
    name = "demote-subtree",
    target = "heading",
    run = function(c)
      c.action("demote_subtree")
    end,
  },
  {
    name = "move-subtree-up",
    target = "heading",
    run = function(c)
      c.action("move_subtree_up")
    end,
  },
  {
    name = "move-subtree-down",
    target = "heading",
    run = function(c)
      c.action("move_subtree_down")
    end,
  },
  {
    -- C-c C-t: the next state
    name = "todo",
    target = "heading",
    run = function(c)
      c.action("todo")
    end,
  },
  {
    -- C-c C-t with org-log-done 'time
    name = "todo-logdone",
    target = "heading",
    run = function(c)
      c.with_config({ log_done = "time" }, function()
        c.action("todo")
      end)
    end,
  },
  {
    -- S-up on a headline: org-priority-up
    name = "priority-up",
    target = "heading",
    run = function(c)
      c.action("shift_up")
    end,
  },
  {
    name = "priority-down",
    target = "heading",
    run = function(c)
      c.action("shift_down")
    end,
  },
  {
    -- clock in, then out at the same (frozen) time
    name = "clock-in-out",
    target = "heading",
    run = function(c)
      c.action("clock_in")
      c.action("clock_out")
    end,
  },
  {
    -- C-c C-c on a checkbox, statistics cookies updated
    name = "toggle-checkbox",
    target = "checkbox",
    run = function(c)
      c.action("toggle_checkbox")
    end,
  },
  {
    -- S-up / S-down on the day of a timestamp
    name = "timestamp-up",
    target = "timestamp",
    run = function(c)
      c.action("shift_up")
    end,
  },
  {
    name = "timestamp-down",
    target = "timestamp",
    run = function(c)
      c.action("shift_down")
    end,
  },
  {
    -- C-c ^ a: the children, alphabetically
    name = "sort-alpha",
    target = "heading",
    run = function(c)
      c.action("sort", "a")
    end,
  },
  {
    -- C-RET
    name = "insert-heading",
    target = "heading",
    run = function(c)
      c.action("insert_heading")
      vim.cmd("stopinsert")
    end,
  },
  {
    -- C-c C-x A
    name = "archive-sibling",
    target = "heading",
    run = function(c)
      c.action("archive_to_sibling")
    end,
  },
  {
    -- C-c C-w to another headline of the file (the last child there)
    name = "refile",
    target = "heading",
    run = function(c)
      if not c.dest then
        return
      end
      c.action("refile", nil, {
        dest = { bufnr = c.buf, lnum = c.dest, level = #c.line(c.dest):match("^%*+") },
      })
    end,
  },
}

M.BY_NAME = {}
for _, cmd in ipairs(M.COMMANDS) do
  M.BY_NAME[cmd.name] = cmd
end

--- The plan for `seed`: one to three steps.
---@param seed integer
---@return difftest.Step[]
function M.plan(seed)
  local rng = fuzz.rng(seed * 31 + 7)
  local out = {}
  for _ = 1, rng:int(1, 3) do
    local cmd = rng:pick(M.COMMANDS).name
    out[#out + 1] = { cmd = cmd, k = rng:int(1, 40), k2 = cmd == "refile" and rng:int(1, 40) or nil }
  end
  return out
end

---@param step difftest.Step
function M.step_string(step)
  return step.cmd .. " " .. step.k .. (step.k2 and (" " .. step.k2) or "")
end

---@param plan difftest.Step[]
function M.encode(plan)
  return table.concat(vim.tbl_map(M.step_string, plan), ";")
end

--- The seed of a document file (d<seed>.org), 0 for another name.
function M.seed_of(file)
  return tonumber(vim.fs.basename(file):match("^d(%d+)%.org$")) or 0
end

--- The plan of a document file.
function M.plan_of(file)
  return M.plan(M.seed_of(file))
end

--- Heading level of a line (1..14), nil if it isn't a headline.
local function level(l)
  local stars = l:match("^(%*+) ")
  if stars and #stars < 15 then
    return #stars
  end
end

local function is_checkbox(l)
  local rest = l:match("^%s*[%-%+] (.*)$") or l:match("^%s*%d+[%.%)] (.*)$")
  return rest ~= nil and (rest:match("^%[[ X%-]%] ") or rest:match("^%[[ X%-]%]$")) ~= nil
end

--- The first <yyyy-mm-dd or [yyyy-mm-dd of a line: its day's column (0-based).
local function timestamp_col(l)
  local s = l:find("[<%[]%d%d%d%d%-%d%d%-%d%d")
  return s and (s - 1 + 9)
end

--- The targets of `kind` in `lines`: { lnum, col0 } each.
function M.targets(kind, lines)
  local out = {}
  for i, l in ipairs(lines) do
    if kind == "heading" and level(l) then
      out[#out + 1] = { i, 0 }
    elseif kind == "checkbox" and is_checkbox(l) then
      out[#out + 1] = { i, 0 }
    elseif kind == "timestamp" then
      local col = timestamp_col(l)
      if col then
        out[#out + 1] = { i, col }
      end
    end
  end
  return out
end

--- The k-th of `list` (mod its length), nil when empty.
local function nth(list, k)
  if #list == 0 then
    return nil
  end
  return list[(k - 1) % #list + 1]
end

--- refile's destination: the k2-th headline outside the subtree at `lnum`.
function M.refile_dest(lines, lnum, k2)
  local lv = level(lines[lnum])
  local last = #lines
  for i = lnum + 1, #lines do
    local l2 = level(lines[i])
    if l2 and l2 <= lv then
      last = i - 1
      break
    end
  end
  local cands = {}
  for i, l in ipairs(lines) do
    if level(l) and (i < lnum or i > last) then
      cands[#cands + 1] = i
    end
  end
  return nth(cands, k2)
end

--- org.nvim's side: the output for `file` (see the top of this file).
---@param file string
---@return string
function M.run(file)
  local actions = require("org.actions")
  local config = require("org.config")
  local clock = require("org.clock")
  local utils = require("org.utils")
  -- Emacs has org-inlinetask loaded (scripts/emacs-parity/common.el)
  local saved_inline = config.opts.inlinetask_min_level
  config.opts.inlinetask_min_level = 15
  vim.cmd("silent! only!")
  vim.cmd("silent! %bwipeout!")
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local buf = vim.api.nvim_get_current_buf()
  -- never write the document (Emacs reads it meanwhile), never prompt
  local saved = {
    save = utils.save_buffer,
    input = vim.fn.input,
    confirm = vim.fn.confirm,
    select = vim.ui.select,
    uinput = vim.ui.input,
    getchar = vim.fn.getchar,
    getcharstr = vim.fn.getcharstr,
  }
  local function prompted()
    error("prompted", 0)
  end
  utils.save_buffer = function()
    return true
  end
  vim.fn.input, vim.fn.confirm, vim.ui.select, vim.ui.input = prompted, prompted, prompted, prompted
  vim.fn.getchar, vim.fn.getcharstr = prompted, prompted
  local out = {}
  local okc, err = pcall(function()
    for i, step in ipairs(M.plan_of(file)) do
      out[#out + 1] = ("=== %d %s"):format(i, M.step_string(step))
      local cmd = assert(M.BY_NAME[step.cmd], step.cmd)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local t = nth(M.targets(cmd.target, lines), step.k)
      if t then
        -- everything shown, as in Emacs (difftest.el)
        vim.cmd("silent! normal! zR")
        vim.api.nvim_win_set_cursor(0, t)
        -- a command of its own, as in Emacs (`last-command` is another
        -- one): a shift after a removal starts again from the default
        require("org.priority").forget_cycle()
        local ctx = {
          buf = buf,
          dest = step.k2 and M.refile_dest(lines, t[1], step.k2) or nil,
          line = function(l)
            return lines[l]
          end,
          action = function(name, ...)
            actions.run(name, ...)
          end,
          with_config = function(over, fn)
            local o = config.opts
            local prev = {}
            for key, v in pairs(over) do
              prev[key] = o[key]
              o[key] = v
            end
            local okf, e = pcall(fn)
            for key in pairs(over) do
              o[key] = prev[key]
            end
            if not okf then
              error(e, 0)
            end
          end,
        }
        local okr, e = pcall(cmd.run, ctx)
        -- as in Emacs: an error that left the buffer alone is a command
        -- that declined
        if not okr and not vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) then
          out[#out + 1] = "!error " .. tostring(e):gsub("\n", " ")
        end
      end
      vim.list_extend(out, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end
  end)
  utils.save_buffer = saved.save
  vim.fn.input, vim.fn.confirm, vim.ui.select, vim.ui.input = saved.input, saved.confirm, saved.select, saved.uinput
  vim.fn.getchar, vim.fn.getcharstr = saved.getchar, saved.getcharstr
  -- no clock left running into the next document
  clock.state, clock.last, clock.history, clock.interrupted, clock.leftover = nil, nil, {}, nil, nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modified = false
  end
  vim.cmd("silent! %bwipeout!")
  config.opts.inlinetask_min_level = saved_inline
  if not okc then
    error(err, 0)
  end
  return table.concat(out, "\n") .. "\n"
end

return M
