---@mod org.extensions.cli.mcp `org mcp`: the commands as an MCP server
---
--- A Model Context Protocol server on stdin and stdout (JSON-RPC 2.0,
--- one message per line) for AI agents: every command of the command line
--- but `schema`, `help`, `version`, `protocol` and `mcp` is a tool, whose
--- `inputSchema` is the command's `input_schema` (`schema.input_schema`).
--- A tool call runs `org COMMAND ... --json` in a new Neovim, as the shell
--- does, so it reads the files as they are on disk, writes them through
--- the guard and the write hooks and runs in the session server when one
--- listens; its result is the JSON envelope. With `--read-only` (or
--- `extensions.cli.mcp.read_only`) the tools that write are left out.

local schema = require("org.extensions.cli.schema")
local shared = require("org.extensions.cli.shared")

local run = require("org.extensions.cli.run")

local M = {}

local fail = run.fail
local state = shared.state

--- Protocol versions the server speaks, newest first: an `initialize` with
--- one of them gets it back, any other the newest.
M.PROTOCOLS = { "2025-06-18", "2025-03-26", "2024-11-05" }

--- How long a tool call may take (ms) before its Neovim is stopped.
M.TIMEOUT = 600000

-- commands that are no tools: descriptions, the URL handler (it needs a
-- running Neovim's windows) and the server itself
local NOT_TOOLS = { schema = true, help = true, version = true, protocol = true, mcp = true }

-- flags no tool takes: --force writes over a running Neovim's unsaved
-- changes (the agent gets file_busy and asks the user), --input reads
-- stdin (the protocol's channel), --list and --csv have their own tools
-- or no use in JSON
local HIDDEN_FLAGS = { force = true, input = true, list = true, csv = true }

-- tools that replace or remove what is there (MCP's destructiveHint)
local DESTRUCTIVE = {
  ["clock cancel"] = true,
  ["set todo"] = true,
  ["set tags"] = true,
  ["set priority"] = true,
  ["set property"] = true,
  ["set scheduled"] = true,
  ["set deadline"] = true,
  refile = true,
  archive = true,
  export = true,
}

-- the same arguments give the same result (MCP's idempotentHint)
local IDEMPOTENT = {
  ["set todo"] = true,
  ["set tags"] = true,
  ["set priority"] = true,
  ["set property"] = true,
  ["set scheduled"] = true,
  ["set deadline"] = true,
  id = true,
  export = true,
}

M.INSTRUCTIONS = table.concat({
  "Tools for the user's Org mode files (org.nvim, Emacs Org mode for Neovim).",
  "Every tool returns the JSON envelope of `org COMMAND --json`:",
  "{ version, ok, command, data, warnings, errors }; on failure errors[0] has a code and a message.",
  "A target is a heading: id:ID, FILE:LINE, FILE::TITLE, FILE::#CUSTOM_ID or title words;",
  "when several headings match (code ambiguous) retry with pick or with the id: of one of details.candidates.",
  "A capture with prompts takes their answers in field (NAME=VALUE); input_needed names the missing one.",
  "file_busy means the user has unsaved changes in that file in Neovim: ask them to save it.",
}, " ")

--- Does the command change files (export writes its output file)?
local function writes(c)
  return c.writes or c.name == "export"
end

--- The flags of a command its tool takes.
local function tool_flags(c)
  local out = {}
  for _, k in ipairs(c.flags or {}) do
    if not HIDDEN_FLAGS[k] then
      out[#out + 1] = k
    end
  end
  return out
end

--- The tool's name: the command's words joined by `_` (set_todo).
local function tool_name(c)
  return (c.name:gsub(" ", "_"))
end

--- Tool name -> command (schema.COMMANDS entry).
local BY_TOOL = {}
for _, c in ipairs(schema.COMMANDS) do
  if not NOT_TOOLS[c.name] then
    BY_TOOL[tool_name(c)] = c
  end
end

--- The MCP tool definition of a command.
---@param c table a schema.COMMANDS entry
---@return table
function M.tool(c)
  local input = schema.input_schema(c)
  for k in pairs(HIDDEN_FLAGS) do
    input.properties[k] = nil
  end
  if #input.required == 0 then
    input.required = nil
  end
  local w = writes(c)
  return {
    name = tool_name(c),
    description = c.summary .. " (org " .. c.name .. ")",
    inputSchema = input,
    annotations = {
      readOnlyHint = not w,
      destructiveHint = w and DESTRUCTIVE[c.name] or false,
      idempotentHint = not w or IDEMPOTENT[c.name] or false,
      openWorldHint = false,
    },
  }
end

--- The tools a server lists: every command's, without those that write
--- when `read_only`.
---@param read_only boolean
---@return table[]
function M.tools(read_only)
  local out = {}
  for _, c in ipairs(schema.COMMANDS) do
    if not NOT_TOOLS[c.name] and not (read_only and writes(c)) then
      out[#out + 1] = M.tool(c)
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Tool arguments -> command line
---------------------------------------------------------------------------

local BadArgs = {}

--- An error in the arguments of a tool call: the call's result says so
--- (isError), for the agent to correct.
local function bad(msg)
  error(setmetatable({ msg = msg }, BadArgs), 0)
end

local function word(v, name)
  local t = type(v)
  if t == "string" then
    return v
  elseif t == "number" then
    return v == math.floor(v) and string.format("%d", v) or tostring(v)
  end
  bad(name .. " must be a string, not " .. (v == vim.NIL and "null" or t))
end

--- The words of a value: a list gives one word per item.
local function words_of(v, name)
  if type(v) == "table" then
    local out = {}
    for i, x in ipairs(v) do
      out[i] = word(x, name)
    end
    return out
  end
  return { word(v, name) }
end

local function given(v)
  return v ~= nil and v ~= vim.NIL
end

--- The `org` arguments of a call of command `c`'s tool with `args`
--- (after the global ones): the command's words, its flags and, after
--- `--`, its arguments in order.
---@param c table a schema.COMMANDS entry
---@param args table|nil the call's `arguments`
---@return string[]
function M.argv(c, args)
  if not given(args) then
    args = {}
  end
  if type(args) ~= "table" or (vim.islist(args) and next(args) ~= nil) then
    bad("arguments must be an object")
  end
  ---@cast args table
  local props = M.tool(c).inputSchema.properties
  local unknown = {}
  for k in pairs(args) do
    if not props[k] then
      unknown[#unknown + 1] = tostring(k)
    end
  end
  if #unknown > 0 then
    table.sort(unknown)
    local known = vim.tbl_keys(props)
    table.sort(known)
    bad(
      string.format(
        "%s takes no argument %s (it takes %s)",
        tool_name(c),
        table.concat(unknown, ", "),
        #known > 0 and table.concat(known, ", ") or "none"
      )
    )
  end
  local argv = vim.split(c.name, " ")
  for _, k in ipairs(tool_flags(c)) do
    local v = args[k]
    local f = schema.BY_KEY[k]
    local name = f.names[#f.names]
    if given(v) then
      if not f.value then
        if type(v) ~= "boolean" then
          bad(k .. " must be true or false")
        end
        if v then
          argv[#argv + 1] = name
        end
      else
        local ws = words_of(v, k)
        if #ws > 1 and not f.repeatable then
          bad(k .. " takes one value")
        end
        for _, w in ipairs(ws) do
          argv[#argv + 1] = name
          argv[#argv + 1] = w
        end
      end
    end
  end
  argv[#argv + 1] = "--"
  local missing
  for _, a in ipairs(c.args or {}) do
    local v = args[a.name]
    if not given(v) then
      if a.required then
        bad("missing argument " .. a.name)
      end
      missing = missing or a.name
    else
      if missing then
        bad(a.name .. " needs " .. missing .. " too")
      end
      local ws = words_of(v, a.name)
      if #ws > 1 and not a.variadic then
        bad(a.name .. " takes one string")
      end
      for _, w in ipairs(ws) do
        if w == "-" then
          bad('"-" (standard input) is not available to a tool; give the text itself')
        end
        argv[#argv + 1] = w
      end
    end
  end
  return argv
end

---------------------------------------------------------------------------
-- Running a tool
---------------------------------------------------------------------------

local MAIN = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")) .. "/main.lua"

local function text_result(text, is_error)
  return { content = { { type = "text", text = text } }, isError = is_error or false }
end

--- Run `org` with `argv` in a new Neovim: its result as a tools/call
--- result.
---@param server table
---@param argv string[]
---@return table
local function run_org(server, argv)
  local cmd = { vim.v.progpath, "--headless", "-l", MAIN }
  vim.list_extend(cmd, server.global_argv)
  vim.list_extend(cmd, argv)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(M.TIMEOUT)
  end)
  if not ok then
    return text_result("could not start Neovim: " .. tostring(res), true)
  end
  local stdout = vim.trim(res.stdout or "")
  local stderr = vim.trim(res.stderr or "")
  if stderr ~= "" and server.verbose then
    run.stderr(stderr .. "\n")
  end
  local dok, env = pcall(vim.json.decode, stdout)
  if not dok or type(env) ~= "table" or env.ok == nil then
    local why = res.code == 124 and ("timed out after " .. M.TIMEOUT / 1000 .. " s")
      or ("exit code " .. tostring(res.code))
    return text_result("org failed (" .. why .. "): " .. (stderr ~= "" and stderr or stdout), true)
  end
  return text_result(stdout, env.ok ~= true)
end

---------------------------------------------------------------------------
-- JSON-RPC
---------------------------------------------------------------------------

local RpcError = {}

local function rpc_error(code, message)
  error(setmetatable({ code = code, message = message }, RpcError), 0)
end

local METHODS = {}

function METHODS.initialize(_, params)
  local asked = type(params) == "table" and params.protocolVersion or nil
  local version = vim.tbl_contains(M.PROTOCOLS, asked) and asked or M.PROTOCOLS[1]
  return {
    protocolVersion = version,
    capabilities = { tools = { listChanged = false } },
    serverInfo = { name = "org.nvim", title = "org.nvim", version = require("org.version").release },
    instructions = M.INSTRUCTIONS,
  }
end

function METHODS.ping()
  return vim.empty_dict()
end

METHODS["tools/list"] = function(server)
  return { tools = M.tools(server.read_only) }
end

METHODS["tools/call"] = function(server, params)
  local name = type(params) == "table" and params.name or nil
  if type(name) ~= "string" then
    rpc_error(-32602, "tools/call needs the name of a tool")
  end
  local c = BY_TOOL[name]
  if not c then
    rpc_error(-32602, "Unknown tool: " .. name)
  end
  if server.read_only and writes(c) then
    return text_result(
      name .. " changes files, and this server is read-only (org mcp --read-only, extensions.cli.mcp.read_only)",
      true
    )
  end
  local ok, argv = pcall(M.argv, c, params.arguments)
  if not ok then
    if getmetatable(argv) == BadArgs then
      ---@cast argv { msg: string }
      return text_result(argv.msg, true)
    end
    error(argv, 0)
  end
  return run_org(server, argv)
end

-- notifications the server takes and does nothing with
for _, n in ipairs({ "notifications/initialized", "notifications/cancelled", "notifications/roots/list_changed" }) do
  METHODS[n] = function() end
end

local function response(id, result)
  return { jsonrpc = "2.0", id = id, result = result }
end

local function error_response(id, code, message)
  return { jsonrpc = "2.0", id = id == nil and vim.NIL or id, error = { code = code, message = message } }
end

--- The response to one decoded message, or nil (a notification, or a
--- response to a request of ours).
local function handle(server, msg)
  if type(msg) ~= "table" or vim.islist(msg) then
    return error_response(nil, -32600, "Invalid Request")
  end
  local id = msg.id
  local notification = id == nil
  if type(msg.method) ~= "string" then
    if msg.result ~= nil or msg.error ~= nil then
      return nil
    end
    return error_response(id, -32600, "Invalid Request")
  end
  local h = METHODS[msg.method]
  if not h then
    if notification then
      return nil
    end
    return error_response(id, -32601, "Method not found: " .. msg.method)
  end
  local params = msg.params
  if params == vim.NIL then
    params = nil
  end
  local ok, result = pcall(h, server, params)
  if notification then
    return nil
  end
  if not ok then
    if getmetatable(result) == RpcError then
      return error_response(id, result.code, result.message)
    end
    return error_response(id, -32603, "Internal error: " .. tostring(result))
  end
  return response(id, result)
end

--- The reply to one line of input (a message or a batch of them), as a
--- line of JSON, or nil.
---@param server table
---@param line string
---@return string|nil
function M.handle_line(server, line)
  local ok, msg = pcall(vim.json.decode, line)
  if not ok then
    return vim.json.encode(error_response(nil, -32700, "Parse error"))
  end
  if type(msg) == "table" and vim.islist(msg) then
    if #msg == 0 then
      return vim.json.encode(error_response(nil, -32600, "Invalid Request"))
    end
    local out = {}
    for _, m in ipairs(msg) do
      out[#out + 1] = handle(server, m)
    end
    return #out > 0 and vim.json.encode(out) or nil
  end
  local reply = handle(server, msg)
  return reply and vim.json.encode(reply) or nil
end

--- A server for the flags `org mcp` got: the global arguments every tool
--- call passes on, and whether it is read-only.
---@param flags table
---@return { global_argv: string[], read_only: boolean, verbose: boolean }
function M.server(flags)
  local g = { "--json" }
  if flags.config then
    vim.list_extend(g, { "--config", run.arg_path(flags.config) })
  end
  for _, f in ipairs(flags.files or {}) do
    vim.list_extend(g, { "--files", run.arg_path(f) })
  end
  if flags.dir then
    vim.list_extend(g, { "--dir", run.arg_path(flags.dir) })
  end
  if flags.no_server then
    g[#g + 1] = "--no-server"
  end
  local opts = shared.cli_opts().mcp or {}
  return {
    global_argv = g,
    read_only = flags.read_only or opts.read_only or false,
    verbose = flags.verbose or false,
  }
end

--- Where the server reads its input; specs replace it.
M.read_line = function()
  return io.stdin:read("*l")
end

--- `org mcp`: answer the messages on stdin until it closes.
function M.cmd_mcp(_, flags)
  if state.session then
    fail("org mcp runs from a shell or an MCP client, not in a running Neovim", "usage")
  end
  if state.machine then
    fail("org mcp speaks JSON-RPC on stdout: it takes no --json or --jsonl", "usage")
  end
  local server = M.server(flags)
  -- nothing but the protocol on stdout
  local saved_print = _G.print
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring((select(i, ...)))
    end
    run.stderr(table.concat(parts, "\t") .. "\n")
  end
  local saved_write = io.write
  local function stderr_write(...)
    for i = 1, select("#", ...) do
      run.stderr(tostring((select(i, ...))))
    end
    return io.stdout
  end
  io.write = stderr_write
  local ok, e = pcall(function()
    while true do
      local line = M.read_line()
      if line == nil then
        break
      end
      line = line:gsub("\r$", "")
      if line:match("%S") then
        local reply = M.handle_line(server, line)
        if reply then
          run.stdout(reply .. "\n")
          io.stdout:flush()
        end
      end
    end
  end)
  _G.print = saved_print
  io.write = saved_write
  if not ok then
    error(e, 0)
  end
  return { text = {} }
end

return M
