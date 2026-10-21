-- The test runner's quarantine of flaky spec files (tests/quarantine.lua):
-- a second run only for listed files that failed, reported apart.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local quarantine = dofile(root .. "/tests/quarantine.lua")

describe("test runner quarantine", function()
  local list = {
    { file = "flaky_spec.lua", reason = "x" },
    { file = "win_spec.lua", os = "windows", reason = "y" },
  }

  it("finds a listed file by its name, on its OS only", function()
    ok(quarantine.find("tests/spec/flaky_spec.lua", "linux", list))
    ok(quarantine.find("C:\\a\\tests\\spec\\flaky_spec.lua", "windows", list))
    ok(quarantine.find("tests/spec/win_spec.lua", "windows", list))
    eq(nil, quarantine.find("tests/spec/win_spec.lua", "macos", list))
    eq(nil, quarantine.find("tests/spec/other_spec.lua", "linux", list))
  end)

  it("lists only spec files that exist", function()
    for _, e in ipairs(quarantine.list) do
      eq(1, vim.fn.filereadable(root .. "/tests/spec/" .. e.file), e.file)
      ok(e.reason and e.reason ~= "", e.file .. " has a reason")
    end
  end)

  it("reruns a quarantined file only when it failed and reruns are on", function()
    local saved = vim.env.ORG_TEST_RERUN_QUARANTINED
    local name = quarantine.list[1].file
    vim.env.ORG_TEST_RERUN_QUARANTINED = "1"
    local fail = { result = { passed = 1, failed = 1 } }
    local pass = { result = { passed = 2, failed = 0 } }
    ok(quarantine.should_rerun("tests/spec/" .. name, fail))
    ok(quarantine.should_rerun("tests/spec/" .. name, { crash = "timed out" }))
    ok(not quarantine.should_rerun("tests/spec/" .. name, pass))
    ok(not quarantine.should_rerun("tests/spec/not_listed_spec.lua", fail))
    vim.env.ORG_TEST_RERUN_QUARANTINED = nil
    ok(not quarantine.should_rerun("tests/spec/" .. name, fail))
    vim.env.ORG_TEST_RERUN_QUARANTINED = saved
  end)

  describe("runs", function()
    local dir
    before_each(function()
      dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
    end)
    after_each(function()
      vim.fn.delete(dir, "rf")
    end)

    -- a spec file that fails the first `fails` times it runs
    local function spec_file(name, fails)
      local path = dir .. "/" .. name
      local count = dir .. "/" .. name .. ".count"
      local f = assert(io.open(path, "wb"))
      f:write(([[
local count = %q
local n = tonumber((io.open(count, "rb") or { read = function() end }):read("*a") or "") or 0
local f = assert(io.open(count, "wb"))
f:write(tostring(n + 1))
f:close()
describe("maybe", function()
  it("passes after %d failures", function()
    assert(n >= %d, "failure " .. (n + 1))
  end)
end)
]]):format(count, fails, fails))
      f:close()
      return path
    end

    local function run(file, env)
      local cmd = { vim.v.progpath, "--headless", "-u", root .. "/tests/minimal_init.lua" }
      vim.list_extend(cmd, { "-l", root .. "/tests/run.lua", file })
      -- a runner of its own, not a worker of this run
      local opts = {
        text = true,
        env = vim.tbl_extend("force", {
          ORG_TEST_WORKER = "",
          ORG_TEST_JOBS = "1",
          -- CI shards its run (Windows): the one file here must not land in another share
          ORG_TEST_SHARD = "",
          ORG_TEST_PERF = "",
          ORG_TEST_PROGRESS = "",
          ORG_TEST_RESULT = dir .. "/outer.json",
          ORG_COVERAGE_DIR = "",
          GITHUB_ACTIONS = "",
          XDG_DATA_HOME = dir .. "/data",
        }, env),
      }
      local res = vim.system(cmd, opts):wait(120000)
      return res.code, (res.stdout or "") .. (res.stderr or "")
    end

    it("reports a quarantined file that passes on its second run as flaky", function()
      local file = spec_file("flaky_once_spec.lua", 1)
      local code, out = run(file, { ORG_TEST_RERUN_QUARANTINED = "1", ORG_TEST_QUARANTINE = "flaky_once_spec.lua" })
      eq(0, code, out)
      ok(out:find("FLAKY: [^\n]*flaky_once_spec%.lua"), out)
      ok(out:find("failure 1", 1, true), out)
      ok(out:find("1 passed, 0 failed, 1 flaky", 1, true), out)
    end)

    it("fails a quarantined file that fails twice", function()
      local file = spec_file("flaky_twice_spec.lua", 2)
      local code, out = run(file, { ORG_TEST_RERUN_QUARANTINED = "1", ORG_TEST_QUARANTINE = "flaky_twice_spec.lua" })
      eq(1, code, out)
      ok(out:find("QUARANTINED: [^\n]*flaky_twice_spec%.lua failed twice"), out)
      ok(out:find("failure 2", 1, true), out)
      ok(not out:find("FLAKY:", 1, true), out)
    end)

    it("gives a file that isn't quarantined no second run", function()
      local file = spec_file("not_quarantined_spec.lua", 1)
      local code, out = run(file, { ORG_TEST_RERUN_QUARANTINED = "1" })
      eq(1, code, out)
      ok(out:find("0 passed, 1 failed", 1, true), out)
      eq("1", vim.fn.readfile(file .. ".count")[1])
    end)

    it("gives no second run without ORG_TEST_RERUN_QUARANTINED", function()
      local file = spec_file("flaky_off_spec.lua", 1)
      local code, out = run(file, { ORG_TEST_RERUN_QUARANTINED = "", ORG_TEST_QUARANTINE = "flaky_off_spec.lua" })
      eq(1, code, out)
      eq("1", vim.fn.readfile(file .. ".count")[1])
    end)
  end)
end)
