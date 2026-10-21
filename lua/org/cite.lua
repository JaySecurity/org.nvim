---@mod org.cite Citations in the buffer (Emacs oc.el and oc-basic.el)
---
--- The insert, follow and activate capabilities of citation processors:
--- org-cite-insert (C-c C-x @) inserts or edits a `[cite:@key]` citation
--- with keys completed from the bibliography, org-open-at-point on a
--- citation opens the bibliography entry (org-cite-follow), and citations
--- are highlighted, unknown keys flagged (org-cite-activate). The processor
--- used for each is set by `export.cite.insert_processor`,
--- `follow_processor` and `activate_processor` ("basic" by default).
---
--- Positions follow Emacs points: in a string `s`, point `p` sits before
--- the character `s:sub(p, p)`.
---
--- This file holds the options, the processor registry and the basic
--- processor's table; it loads the rest from org/cite/: syntax (parsing
--- citations), region (the text around the cursor and editing it),
--- bibliography (bibliography files and the basic processor's key
--- helpers), insert (styles and the insert capability), follow (the
--- follow capability and mouse clicks) and activate (highlights). What
--- every org buffer sets up is in org/cite/attach.lua, which doesn't load
--- this module.

local utils = require("org.utils")

local M = {}
-- The parts in org/cite/ add their functions to this table and require
-- it back, so it must be in package.loaded before they load.
package.loaded["org.cite"] = M

local function ccfg()
  return (require("org.config").opts.export or {}).cite or {}
end

--- Report `msg` and abort the running action (Emacs user-error).
local function user_error(msg)
  utils.error(msg)
  utils.abort()
end
M.user_error = user_error

local function opt(name, default)
  local v = ccfg()[name]
  if v == nil then
    return default
  end
  return v
end

---------------------------------------------------------------------------
-- Processors
---------------------------------------------------------------------------

--- Citation processors for the buffer capabilities, by name. A processor
--- is a table with any of `activate(citation_marks_ctx)`,
--- `follow(ctx, arg)` and `insert(ctx, arg)` (org-cite-register-processor).
M.processors = {}

--- org-cite-register-processor (buffer capabilities).
---@param name string
---@param spec { activate?: function, follow?: function, insert?: function }
function M.register_processor(name, spec)
  M.processors[name] = spec
end

local function processor_for(capability, option, what)
  local name = opt(option, "basic")
  if not name or name == "" then
    user_error(string.format("No processor set to %s citations", what))
  end
  local p = M.processors[name]
  if not p then
    user_error(string.format("Unknown processor %s", name))
  end
  if not p[capability] then
    user_error(string.format("Processor %s cannot %s citations", name, what))
  end
  return p
end

--- The basic processor (oc-basic.el); the parts add its functions.
local basic = {}
M.basic = basic

--- Activate citations in an org buffer (called for every org buffer).
function M.attach(bufnr)
  require("org.cite.attach").attach(bufnr)
end

-- Local functions the parts below share
local shared = require("org.cite.shared")
shared.opt = opt
shared.processor_for = processor_for

require("org.cite.syntax")
require("org.cite.region")
require("org.cite.bibliography")
require("org.cite.insert")
require("org.cite.follow")
require("org.cite.activate")

M.register_processor("basic", {
  activate = basic.activate,
  follow = basic.follow,
  insert = basic.insert,
})

return M
