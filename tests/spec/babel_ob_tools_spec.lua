-- ob-dot, ob-sed, ob-sass, ob-octave (and matlab) and ob-forth, checked
-- against Emacs Org 9.8.10 (`emacs --batch`, org-babel-execute-src-block)
-- with the same fake programs (Graphviz, sass and Octave are not
-- installed; sed is the real one). Emacs can't run Forth blocks without
-- forth-mode, so the Forth transcript follows ob-forth's code.
local config = require("org.config")
local h = require("tests.helpers.babel_ob")

--- Lines of `out` after the `n`th #+RESULTS: line.
local function results(out, n)
  local seen = 0
  for i, l in ipairs(out) do
    if l:match("^#%+RESULTS") then
      seen = seen + 1
      if seen == (n or 1) then
        local res = {}
        for j = i + 1, #out do
          if out[j] == "" then
            break
          end
          res[#res + 1] = out[j]
        end
        return res
      end
    end
  end
end

local function silence(fn)
  local notify = vim.notify
  local msgs = {}
  vim.notify = function(m)
    msgs[#msgs + 1] = m
  end
  local ok_, err = pcall(fn)
  vim.notify = notify
  if not ok_ then
    error(err, 0)
  end
  return table.concat(msgs, "\n")
end

describe("babel ob-dot", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("runs CMD IN -TEXT -o FILE, :cmdline and :cmd, $NAME replaced", function()
    local dir = h.tmpdir()
    local log = dir .. "/log"
    local fake = h.fake(dir, "fakedot", 'echo "dot $*" >> ' .. log .. '\ncat "$1" >> ' .. log .. "\necho >> " .. log)
    h.set_lang("dot", { cmd = fake })
    local errs
    local out
    errs = silence(function()
      out = h.run({
        '#+begin_src dot :file g.png :var c="red" :prologue "// pro"',
        "digraph { a [color=$c]; a -> b }",
        "#+end_src",
        "",
        "#+begin_src dot :file g.svg :cmdline -Kneato -Tsvg :cmd " .. fake,
        "digraph { a }",
        "#+end_src",
        "",
        "#+begin_src dot",
        "digraph { a }",
        "#+end_src",
      }, dir)
    end)
    -- Emacs 9.8.10: links for the first two, an error for the third
    eq({ "[[file:g.png]]" }, results(out, 1))
    eq({ "[[file:g.svg]]" }, results(out, 2))
    eq(nil, results(out, 3))
    ok(errs:find("You need to specify a :file parameter", 1, true))
    local l = vim.fn.readfile(log)
    ok(l[1]:match("^dot %S+%.dot %-Tpng %-o g%.png$"), l[1])
    eq({ "// pro", "digraph { a [color=red]; a -> b }" }, vim.list_slice(l, 2, 3))
    ok(l[4]:match("^dot %S+%.dot %-Kneato %-Tsvg %-o g%.svg$"), l[4])
  end)

  it("is the core handler, which the diagrams extension can replace", function()
    local ob = require("org.babel.ob")
    eq("dot", ob.HANDLERS.dot)
    eq(require("org.babel.lang.dot"), ob.get("dot"))
    eq({ results = "file", exports = "results" }, config.opts.babel.languages.dot.default_header_args)
  end)
end)

describe("babel ob-sed", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("runs sed -f SCRIPT :cmd-line :in-file, :stdin feeds a value", function()
    local dir = h.tmpdir()
    vim.fn.writefile({ "one two", "three" }, dir .. "/in.txt")
    local out = h.run({
      "#+name: txt",
      ": hello world",
      "",
      "#+begin_src sed :stdin txt",
      "s/hello/bye/",
      "#+end_src",
      "",
      "#+begin_src sed :stdin txt :results verbatim :cmd-line -n",
      "s/hello/bye/p",
      "#+end_src",
      "",
      "#+begin_src sed :in-file in.txt",
      "s/o/0/g",
      "#+end_src",
    }, dir)
    -- Emacs 9.8.10
    eq({ ": bye world" }, results(out, 1))
    eq({ ": bye world" }, results(out, 2))
    eq({ "| 0ne   | tw0 |", "| three |     |" }, results(out, 3))
  end)
end)

describe("babel ob-sass", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("runs sass CMDLINE IN OUT: the text of OUT, or nothing with :file", function()
    local dir = h.tmpdir()
    local log = dir .. "/log"
    local fake = h.fake(
      dir,
      "fakesass",
      'echo "sass $*" >> '
        .. log
        .. "\n"
        .. 'for a; do :; done\neval "in=\\${$(($# - 1))}"\n'
        .. 'sed \'s/\\$c: red;//; s/\\$c/red/\' "$in" > "$a"'
    )
    h.set_lang("sass", { cmd = fake })
    local out = h.run({
      "#+begin_src sass :cmdline --no-source-map",
      "$c: red;",
      "a { color: $c; }",
      "#+end_src",
      "",
      "#+begin_src sass :file out.css",
      "a { color: blue; }",
      "#+end_src",
    }, dir)
    -- Emacs 9.8.10 (no result for the :file block, whose result is nil)
    eq({ ": ", ": a { color: red; }" }, results(out, 1))
    eq({ "a { color: blue; }" }, vim.fn.readfile(dir .. "/out.css"))
    local l = vim.fn.readfile(log)
    ok(l[1]:match("^sass %-%-no%-source%-map %S+ %S+$"), l[1])
    ok(l[2]:match("^sass %S+ out%.css$"), l[2])
  end)
end)

local FAKE_OCTAVE = [[
code=$(cat)
printf '%s %s\n%s\n----\n' "$(basename "$0")" "$*" "$code" >> "$(dirname "$0")/log"
out=$(printf '%s\n' "$code" | sed -n "s/^else, dlmwrite('\(.*\)', ans, .*/\1/p")
if [ -n "$out" ]; then printf '# comment\n\n1\t2\n3\t4\n' > "$out"; else echo "x = 1"; fi]]

describe("babel ob-octave", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("feeds the code to octave -q, the value through the wrapper's file", function()
    local dir = h.tmpdir()
    h.set_lang("octave", { cmd = h.fake(dir, "octave", FAKE_OCTAVE) .. " -q" })
    h.set_lang("matlab", { cmd = h.fake(dir, "matlab", FAKE_OCTAVE) .. " -nosplash" })
    local out = h.run({
      "#+name: tb",
      "| 1 | 2 |",
      "| 3 | 4 |",
      "",
      '#+begin_src octave :var m=tb s="str" n=3 :results output',
      "disp(n)",
      "#+end_src",
      "",
      "#+begin_src octave :var l='(1 2)",
      "ans = 1",
      "#+end_src",
      "",
      "#+begin_src matlab",
      "ans = 1",
      "#+end_src",
    }, dir)
    -- Emacs 9.8.10
    eq({ ": x = 1" }, results(out, 1))
    eq({ "| 1 | 2 |", "| 3 | 4 |" }, results(out, 2))
    eq({ "| 1 | 2 |", "| 3 | 4 |" }, results(out, 3))
    local log = table.concat(vim.fn.readfile(dir .. "/log"), "\n")
    local blocks = {}
    for _, b in ipairs(vim.split(log, "\n----", { plain = true, trimempty = true })) do
      blocks[#blocks + 1] = (b:gsub("^\n", ""))
    end
    eq("octave -q\nm=[[1,2]; [3,4]];\ns='str';\nn=3;\ndisp(n)", blocks[1])
    local tmp = blocks[2]:match("fopen%('([^']+)'")
    ok(tmp)
    eq(
      "octave -q\nl=[1,2];\nans = 1\nif ischar(ans), fid = fopen('"
        .. tmp
        .. "', 'w'); fdisp(fid, ans); fclose(fid);\nelse, dlmwrite('"
        .. tmp
        .. "', ans, '\\t')\nend",
      blocks[2]
    )
    ok(blocks[3]:match("^matlab %-nosplash\nans = 1\n"), blocks[3])
  end)

  it("prints a graphics :file with print -dpng", function()
    local text = require("org.babel.lang.octave").var_to_octave({ { 1, "a" }, { 2, "b" } })
    eq("[[1,'a']; [2,'b']]", text)
    local dir = h.tmpdir()
    h.set_lang("octave", { cmd = h.fake(dir, "octave", FAKE_OCTAVE) })
    local out = h.run({
      "#+begin_src octave :file p.png :results file graphics",
      "plot(1)",
      "#+end_src",
    }, dir)
    eq({ "[[file:p.png]]" }, results(out, 1))
    local log = vim.fn.readfile(dir .. "/log")
    eq(
      { 'set (0, "defaultfigurevisible", "off");', "plot(1)", 'print -dpng "p.png"', 'ans="p.png"' },
      vim.list_slice(log, 2, 5)
    )
  end)
end)

-- gforth reading the script: a fake running each line through a tiny
-- interpreter (numbers, `+`, `.`, `: name ... ;` definitions spanning
-- lines) and the marker word, enough to check the transcript parsing
local FAKE_GFORTH = [[
compiling=0
while IFS= read -r line; do
  case "$line" in
    ": org-babel-mark"*) continue ;;
    "org-babel-mark "*) [ "$compiling" = 0 ] && printf '\n<<org-babel-forth-line %s>>\n' "${line#org-babel-mark }"; continue ;;
    bye) exit 0 ;;
    ":"*) compiling=1 ;;
  esac
  case "$line" in *";"*) compiling=0; continue ;; esac
  [ "$compiling" = 1 ] && continue
  set -- $line
  stack=""
  for w; do
    case "$w" in
      +) set -- $stack; a=$1; b=$2; stack="$((a + b))" ;;
      .) printf '%s ' "$stack"; stack="" ;;
      *) stack="$stack $w" ;;
    esac
  done
done < "$1"]]

describe("babel ob-forth", function()
  before_each(function()
    config.opts.babel.confirm_evaluate = false
  end)
  after_each(h.restore)

  it("splits gforth's output by line: the last for a value, all for output", function()
    local dir = h.tmpdir()
    h.set_lang("forth", { cmd = h.fake(dir, "gforth", FAKE_GFORTH) })
    local out = h.run({
      "#+begin_src forth",
      "1 2 + .",
      "",
      "3 4 + .",
      "#+end_src",
      "",
      "#+begin_src forth :results output",
      "1 2 + .",
      ": foo",
      "  1 ;",
      "5 6 + .",
      "#+end_src",
    }, dir)
    eq({ ": 7 " }, results(out, 1))
    eq({ ": 3 ", ": ", ": ", ": 11 " }, results(out, 2))
  end)

  it("refuses :session none like Emacs, and builds the marked script", function()
    local forth = require("org.babel.lang.forth")
    eq({ "1 .", ": a", "2 ;" }, forth.lines({ "", "1 .", "", ": a", "2 ;", "" }, {}))
    local script = vim.split(forth.script({ "1 .", ": a" }), "\n")
    ok(script[1]:match("^: org%-babel%-mark .* immediate$"))
    eq({ "1 .", "org-babel-mark 1", ": a", "org-babel-mark 2", "bye", "" }, vim.list_slice(script, 2))
    eq({ "3 ", false, "" }, forth.split("3 \n<<org-babel-forth-line 1>>\n\n<<org-babel-forth-line 3>>\n", 3))
    local errs
    errs = silence(function()
      h.run({ "#+begin_src forth :session none", "1 .", "#+end_src" })
    end)
    ok(errs:find("Non-session evaluation not supported for Forth code blocks", 1, true))
  end)
end)

describe("babel languages health", function()
  it("checks the programs of the new languages", function()
    local seen = {}
    local h_ = {
      start = function() end,
      ok = function(m)
        seen[#seen + 1] = m
      end,
      info = function(m)
        seen[#seen + 1] = m
      end,
      warn = function(m)
        seen[#seen + 1] = m
      end,
      error = function(m)
        seen[#seen + 1] = m
      end,
    }
    local health = vim.health
    vim.health = h_
    pcall(require("org.health").check)
    vim.health = health
    local text = table.concat(seen, "\n")
    for _, exe in ipairs({ "dot", "sed", "sass", "octave", "matlab", "gforth" }) do
      ok(text:find("babel: " .. exe .. " ", 1, true), exe)
    end
  end)
end)
