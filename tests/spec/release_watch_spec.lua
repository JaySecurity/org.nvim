-- scripts/emacs-parity/release-watch.sh fetch, against a local org-mode
-- repository and no GNU ELPA tarball (a release only tagged in git).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local script = root .. "/scripts/emacs-parity/release-watch.sh"

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return require("org.utils").realpath(dir)
end

local function run(args, cwd, env)
  local res = vim.system(args, { cwd = cwd, text = true, env = env }):wait()
  return res.code, (res.stdout or "") .. (res.stderr or "")
end

--- A repository like org-mode's: lisp/, a Makefile with `autoloads` and a
--- release_VER tag for each of `versions`.
local function org_repo(versions)
  local repo = tmpdir()
  run({ "git", "init", "-q" }, repo)
  run({ "git", "config", "user.email", "test@example.com" }, repo)
  run({ "git", "config", "user.name", "Test" }, repo)
  run({ "git", "config", "commit.gpgsign", "false" }, repo)
  vim.fn.mkdir(repo .. "/lisp", "p")
  vim.fn.writefile({ "autoloads:", "\t@true" }, repo .. "/Makefile")
  for _, ver in ipairs(versions) do
    vim.fn.writefile({ '(defun org-release () "' .. ver .. '")' }, repo .. "/lisp/org-version.el")
    run({ "git", "add", "-A" }, repo)
    run({ "git", "commit", "-q", "-m", ver }, repo)
    run({ "git", "tag", "release_" .. ver }, repo)
  end
  return repo
end

describe("release-watch.sh fetch", function()
  it("fetches two releases tagged in git into one directory", function()
    skip_on_windows("the script needs bash and make")
    local repo = org_repo({ "9.8.11", "9.8.12" })
    local out = tmpdir()
    local env = { ELPA_URL = "file://" .. tmpdir(), ORG_GIT_URL = "file://" .. repo }
    for _, ver in ipairs({ "9.8.11", "9.8.12" }) do
      local code, output = run({ "bash", script, "fetch", ver, out }, root, env)
      eq(0, code, output)
      ok(output:find(out .. "/org-" .. ver, 1, true), output)
    end
    for _, ver in ipairs({ "9.8.11", "9.8.12" }) do
      local lines = vim.fn.readfile(out .. "/org-" .. ver .. "/org-version.el")
      eq('(defun org-release () "' .. ver .. '")', lines[1])
    end
  end)
end)
