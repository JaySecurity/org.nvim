// org.nvim documentation site: the playground page (playground.html, built by
// scripts/site/playground.lua). A small asciicast v2 player for the tutor
// recordings (scripts/playground/record.lua), and the "Try the syntax" box.
//
// The player understands what the recorder writes: text, CUP (ESC[r;cH),
// ED 2 (ESC[2J), EL (ESC[K), SGR with bold, italic, underline, strikethrough
// and 24-bit colors, the cursor shape (ESC[n q) and showing/hiding the
// cursor; "i" events are shown as the keys pressed. "m" markers are the
// exercises, but for those whose label starts with "say: " (a caption, shown
// under the terminal) or "step: " (a step marker, a small tick on the
// timeline). A recording is loaded with a <script> tag (playground/<lesson>.js
// calls window.ORG_CAST) so the page also works from file://.
//
// In a light site theme the recording's colors, Neovim's default
// colorscheme with a dark background, become that colorscheme's light
// background ones (LIGHT). Follow-along mode pauses before each key the
// recording presses until the reader presses it. What has been watched is
// kept in localStorage (when it can be), for the lesson cards and the
// "Continue" button.
(function () {
  "use strict";
  var root = document.body.getAttribute("data-root") || "";
  var CAPTION = "say: ";
  var STEP = "step: ";
  var EXERCISE = /^\d+\.\d+ /;

  // Casts ------------------------------------------------------------------
  var casts = {};
  var waiting = {};
  window.ORG_CAST = function (name, text) {
    casts[name] = parse(text);
    (waiting[name] || []).forEach(function (cb) {
      cb(casts[name]);
    });
    delete waiting[name];
  };

  function load(name, src, cb) {
    if (casts[name]) return cb(casts[name]);
    if (waiting[name]) return waiting[name].push(cb);
    waiting[name] = [cb];
    var s = document.createElement("script");
    s.src = root + src;
    s.onerror = function () {
      cb(null);
    };
    document.head.appendChild(s);
  }

  function parse(text) {
    var lines = text.split("\n").filter(Boolean);
    var header = JSON.parse(lines[0]);
    var events = [];
    for (var i = 1; i < lines.length; i++) events.push(JSON.parse(lines[i]));
    var theme = header.theme || {};
    var cast = {
      cols: header.width,
      rows: header.height,
      fg: theme.fg || "#e0e2ea",
      bg: theme.bg || "#14161b",
      events: events,
      markers: [],
      captions: [],
      steps: [],
      inputs: [],
      duration: events.length ? events[events.length - 1][0] : 0,
    };
    events.forEach(function (e) {
      if (e[1] === "m") {
        var label = e[2];
        if (label.indexOf(CAPTION) === 0) cast.captions.push({ t: e[0], text: label.slice(CAPTION.length) });
        else if (label.indexOf(STEP) === 0) cast.steps.push({ t: e[0], label: label.slice(STEP.length) });
        else cast.markers.push({ t: e[0], label: label });
      } else if (e[1] === "i") cast.inputs.push({ t: e[0], key: e[2] });
    });
    cast.prompts = prompts(cast.inputs);
    cast.duration += 2;
    return cast;
  }

  // Terminal ---------------------------------------------------------------
  // A cell is [char, style]; style is "" or "b i u s fg bg" as a key.
  function Term(cols, rows) {
    this.cols = cols;
    this.rows = rows;
    this.reset();
  }
  Term.prototype.reset = function () {
    this.grid = [];
    for (var r = 0; r < this.rows; r++) this.grid.push(this.blank());
    this.row = 0;
    this.col = 0;
    this.style = "";
    this.cursorShown = true;
    this.shape = 2;
    this.dirty = {};
    for (var k = 0; k < this.rows; k++) this.dirty[k] = true;
  };
  Term.prototype.blank = function () {
    var line = [];
    for (var c = 0; c < this.cols; c++) line.push([" ", ""]);
    return line;
  };
  Term.prototype.touch = function () {
    for (var k = 0; k < this.rows; k++) this.dirty[k] = true;
  };

  // East Asian wide and emoji code points take two cells, as in Neovim.
  function wide(cp) {
    return (
      (cp >= 0x1100 && cp <= 0x115f) ||
      (cp >= 0x2e80 && cp <= 0xa4cf) ||
      (cp >= 0xac00 && cp <= 0xd7a3) ||
      (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xfe30 && cp <= 0xfe4f) ||
      (cp >= 0xff00 && cp <= 0xff60) ||
      (cp >= 0xffe0 && cp <= 0xffe6) ||
      (cp >= 0x1f300 && cp <= 0x1faff) ||
      (cp >= 0x20000 && cp <= 0x3fffd)
    );
  }

  Term.prototype.put = function (ch) {
    var w = wide(ch.codePointAt(0)) ? 2 : 1;
    if (this.row < this.rows && this.col < this.cols) {
      this.grid[this.row][this.col] = [ch, this.style];
      if (w === 2 && this.col + 1 < this.cols) this.grid[this.row][this.col + 1] = ["", this.style];
      this.dirty[this.row] = true;
    }
    this.col += w;
  };

  Term.prototype.sgr = function (params) {
    var p = params.length ? params.split(";").map(Number) : [0];
    var st = this.style ? this.style.split(" ") : ["", "", "", "", "", ""];
    for (var i = 0; i < p.length; i++) {
      var n = p[i];
      if (n === 0) st = ["", "", "", "", "", ""];
      else if (n === 1) st[0] = "b";
      else if (n === 3) st[1] = "i";
      else if (n === 4) st[2] = "u";
      else if (n === 9) st[3] = "s";
      else if (n === 22) st[0] = "";
      else if (n === 23) st[1] = "";
      else if (n === 24) st[2] = "";
      else if (n === 29) st[3] = "";
      else if (n === 39) st[4] = "";
      else if (n === 49) st[5] = "";
      else if ((n === 38 || n === 48) && p[i + 1] === 2) {
        var hex =
          "#" +
          [p[i + 2], p[i + 3], p[i + 4]]
            .map(function (v) {
              return ("0" + (v | 0).toString(16)).slice(-2);
            })
            .join("");
        st[n === 38 ? 4 : 5] = hex;
        i += 4;
      }
    }
    this.style = st.join("").length ? st.join(" ") : "";
  };

  Term.prototype.write = function (data) {
    var i = 0;
    var n = data.length;
    while (i < n) {
      var c = data.charCodeAt(i);
      if (c === 27 && data[i + 1] === "[") {
        var j = i + 2;
        while (j < n && !/[@-~]/.test(data[j])) j++;
        var body = data.slice(i + 2, j);
        var fin = data[j];
        this.csi(body, fin);
        i = j + 1;
      } else if (c === 13) {
        this.col = 0;
        i++;
      } else if (c === 10) {
        this.row = Math.min(this.row + 1, this.rows - 1);
        i++;
      } else if (c < 32) {
        i++;
      } else {
        var cp = data.codePointAt(i);
        var ch = String.fromCodePoint(cp);
        this.put(ch);
        i += ch.length;
      }
    }
  };

  Term.prototype.csi = function (body, fin) {
    var r, c;
    if (fin === "H" || fin === "f") {
      var p = body.split(";");
      r = (parseInt(p[0], 10) || 1) - 1;
      c = (parseInt(p[1], 10) || 1) - 1;
      this.row = Math.min(Math.max(r, 0), this.rows - 1);
      this.col = Math.min(Math.max(c, 0), this.cols - 1);
    } else if (fin === "J") {
      if (body === "2" || body === "3") {
        for (r = 0; r < this.rows; r++) {
          this.grid[r] = this.blank();
          this.dirty[r] = true;
        }
      }
    } else if (fin === "K") {
      var line = this.grid[this.row];
      for (c = this.col; c < this.cols; c++) line[c] = [" ", this.style];
      this.dirty[this.row] = true;
    } else if (fin === "m") {
      this.sgr(body);
    } else if (fin === "q" && / $/.test(body)) {
      this.shape = parseInt(body, 10) || 2;
    } else if (body === "?25l") {
      this.cursorShown = false;
    } else if (body === "?25h") {
      this.cursorShown = true;
    }
  };

  // Theme ------------------------------------------------------------------
  // Neovim's default colorscheme: with 'background' light, each NvimDark*
  // color takes the place of its NvimLight* twin and the other way round
  // (src/nvim/highlight_group.c), so the recording's colors swap pairwise.
  var LIGHT = {};
  [
    ["#07080d", "#eef1f8"], // NvimDarkGrey1 / NvimLightGrey1
    ["#14161b", "#e0e2ea"], // Grey2
    ["#2c2e33", "#c4c6cd"], // Grey3
    ["#4f5258", "#9b9ea4"], // Grey4
    ["#004c73", "#a6dbff"], // Blue
    ["#007373", "#8cf8f7"], // Cyan
    ["#005523", "#b3f6c0"], // Green
    ["#470045", "#ffcaff"], // Magenta
    ["#590008", "#ffc0b9"], // Red
    ["#6b5300", "#fce094"], // Yellow
  ].forEach(function (pair) {
    LIGHT[pair[0]] = pair[1];
    LIGHT[pair[1]] = pair[0];
  });
  var html = document.documentElement;
  var darkQuery = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
  function isLight() {
    var t = html.getAttribute("data-theme");
    if (t === "light") return true;
    if (t === "dark") return false;
    return !(darkQuery && darkQuery.matches);
  }
  var light = isLight();
  function color(c) {
    return light ? LIGHT[c] || c : c;
  }
  function themeChanged() {
    var now = isLight();
    if (now === light) return;
    light = now;
    styleCache = {};
    Object.keys(players).forEach(function (k) {
      if (players[k]) players[k].applyTheme();
    });
  }
  if (window.MutationObserver) {
    new MutationObserver(themeChanged).observe(html, { attributes: true, attributeFilter: ["data-theme"] });
  }
  if (darkQuery) {
    if (darkQuery.addEventListener) darkQuery.addEventListener("change", themeChanged);
    else if (darkQuery.addListener) darkQuery.addListener(themeChanged);
  }

  // Rendering --------------------------------------------------------------
  function esc(s) {
    return s.replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  var styleCache = {};
  function css(style) {
    if (styleCache[style] !== undefined) return styleCache[style];
    var st = style.split(" ");
    var out = [];
    if (st[0]) out.push("font-weight:700");
    if (st[1]) out.push("font-style:italic");
    var deco = [];
    if (st[2]) deco.push("underline");
    if (st[3]) deco.push("line-through");
    if (deco.length) out.push("text-decoration:" + deco.join(" "));
    if (st[4]) out.push("color:" + color(st[4]));
    if (st[5]) out.push("background:" + color(st[5]));
    return (styleCache[style] = out.join(";"));
  }

  function rowHTML(line) {
    var out = "";
    var cur = null;
    var run = "";
    for (var c = 0; c < line.length; c++) {
      var cell = line[c];
      if (cell[0] === "") continue;
      if (cell[1] !== cur) {
        if (run) out += cur ? '<span style="' + css(cur) + '">' + esc(run) + "</span>" : esc(run);
        run = "";
        cur = cell[1];
      }
      run += cell[0];
    }
    if (run) out += cur ? '<span style="' + css(cur) + '">' + esc(run) + "</span>" : esc(run);
    return out;
  }

  function rowText(line) {
    return line
      .map(function (cell) {
        return cell[0];
      })
      .join("")
      .replace(/\s+$/, "");
  }

  // Keys -------------------------------------------------------------------
  // A typed character: one code point, not a key name.
  function isTyped(k) {
    return k.length === 1 || (k.length === 2 && k.codePointAt(0) > 0xffff);
  }

  // The keys shown over the screen: the last few pressed within KEY_SHOW
  // seconds; characters typed in a row are one word.
  var KEY_SHOW = 1.6;
  function recentKeys(inputs, t) {
    var groups = [];
    for (var i = 0; i < inputs.length && inputs[i].t <= t; i++) {
      var k = inputs[i].key;
      var typed = isTyped(k);
      var last = groups[groups.length - 1];
      if (typed && last && last.typed && inputs[i].t - last.t < 0.5) {
        last.text += k;
        last.t = inputs[i].t;
      } else {
        groups.push({ text: k, typed: typed, t: inputs[i].t });
      }
    }
    return groups
      .filter(function (g) {
        return t - g.t <= KEY_SHOW;
      })
      .slice(-3);
  }

  // A recorded key string as keys: <CR>, <M-CR>, <leader> and the like are
  // one key each, anything else a character ("<<" is two "<").
  function splitKeys(s) {
    var out = [];
    var i = 0;
    while (i < s.length) {
      var m = /^<[A-Za-z][\w-]*>/.exec(s.slice(i));
      if (m) {
        out.push(m[0]);
        i += m[0].length;
      } else {
        var ch = String.fromCodePoint(s.codePointAt(i));
        out.push(ch);
        i += ch.length;
      }
    }
    return out;
  }

  var NAMES = {
    cr: "CR",
    enter: "CR",
    return: "CR",
    esc: "Esc",
    tab: "Tab",
    bs: "BS",
    backspace: "BS",
    space: " ",
    leader: " ", // the recordings' leader key
    lt: "<",
    bar: "|",
    bslash: "\\",
    up: "Up",
    down: "Down",
    left: "Left",
    right: "Right",
    del: "Del",
    home: "Home",
    end: "End",
    pageup: "PageUp",
    pagedown: "PageDown",
  };
  // One key in a form both the recording and the keyboard give: "a", " ",
  // "<CR>", "<C-c>", "<M-CR>", "<S-Tab>" (modifiers in the order C, M, S).
  function keyId(mods, base) {
    mods = mods.filter(function (m, i) {
      return mods.indexOf(m) === i;
    });
    mods.sort();
    if (!mods.length) return base.length === 1 || base === " " ? base : "<" + base + ">";
    if (base.length === 1 && mods.indexOf("C") >= 0) base = base.toLowerCase();
    return "<" + mods.join("-") + "-" + (base === " " ? "Space" : base) + ">";
  }
  function canon(tok) {
    var m = /^<((?:[CMASDcmasd]-)*)([^>]+)>$/.exec(tok);
    if (!m) return tok;
    var mods = m[1]
      .toUpperCase()
      .split("-")
      .filter(Boolean)
      .map(function (x) {
        return x === "A" ? "M" : x;
      });
    var name = m[2];
    var lower = name.toLowerCase();
    var base = NAMES[lower] || (/^f\d+$/.test(lower) ? lower.toUpperCase() : name);
    return keyId(mods, base);
  }
  var KEYNAMES = {
    Enter: "CR",
    Escape: "Esc",
    Tab: "Tab",
    Backspace: "BS",
    ArrowUp: "Up",
    ArrowDown: "Down",
    ArrowLeft: "Left",
    ArrowRight: "Right",
    Delete: "Del",
    Home: "Home",
    End: "End",
    PageUp: "PageUp",
    PageDown: "PageDown",
  };
  // The key of a keydown event, as `canon` gives it; null for a modifier
  // alone or a key it can't name.
  function eventKey(e) {
    var k = e.key;
    if (!k || /^(Shift|Control|Alt|Meta|CapsLock|Dead|Process|Unidentified|OS|AltGraph)$/.test(k)) return null;
    var mods = [];
    if (e.ctrlKey) mods.push("C");
    if (e.altKey) mods.push("M");
    var base = KEYNAMES[k] || (/^F\d+$/.test(k) ? k : null);
    if (base) {
      if (e.shiftKey) mods.push("S");
    } else if (k === " " || k === "Spacebar") {
      base = " ";
    } else if (mods.length) {
      // Alt and Ctrl change e.key (Option-j is "∆" on a Mac): the key itself
      var letter = /^Key([A-Z])$/.exec(e.code || "");
      var digit = /^Digit(\d)$/.exec(e.code || "");
      base = letter ? (e.shiftKey ? letter[1] : letter[1].toLowerCase()) : digit ? digit[1] : k;
    } else {
      base = k;
    }
    if (!isTyped(base) && base !== " " && !KEYNAMES[k] && !/^F\d+$/.test(base)) return null;
    return keyId(mods, base);
  }

  // What follow-along mode asks for: each "i" event's keys, characters typed
  // in a row (less than 0.5 s apart) as one prompt.
  function prompts(inputs) {
    var out = [];
    inputs.forEach(function (inp) {
      var k = inp.key;
      var last = out[out.length - 1];
      if (isTyped(k) && last && last.typed && inp.t - last.end < 0.5) {
        last.keys.push({ id: canon(k), label: k, t: inp.t });
        last.text += k;
        last.end = inp.t;
        return;
      }
      var keys = (isTyped(k) ? [k] : splitKeys(k)).map(function (tok) {
        return { id: canon(tok), label: tok, t: inp.t };
      });
      out.push({ t: inp.t, end: inp.t, typed: isTyped(k), text: k, keys: keys });
    });
    return out;
  }

  // A key as the prompt shows it.
  function keyLabel(label) {
    if (label === " ") return "Space";
    if (/^<leader>$/i.test(label)) return "Space";
    return label;
  }

  function fmtTime(s) {
    s = Math.max(0, Math.floor(s));
    return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2);
  }

  function copyText(text, done) {
    var fallback = function () {
      var ta = document.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try {
        if (document.execCommand("copy")) done();
      } catch (e) {}
      document.body.removeChild(ta);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
    else fallback();
  }

  // Progress -----------------------------------------------------------------
  // { lesson: { "1.2 Insert a headline": 1 } }: the exercises played to
  // their end in this browser. The page works the same without storage.
  var STORE = "org-playground-progress";
  var progress = (function () {
    try {
      var v = JSON.parse(localStorage.getItem(STORE) || "{}");
      return v && typeof v === "object" ? v : {};
    } catch (e) {
      return {};
    }
  })();
  function saveProgress() {
    try {
      localStorage.setItem(STORE, JSON.stringify(progress));
    } catch (e) {}
  }
  function watched(lesson, label) {
    return !!(progress[lesson] && progress[lesson][label]);
  }
  function markWatched(lesson, label) {
    if (!EXERCISE.test(label) || watched(lesson, label)) return;
    progress[lesson] = progress[lesson] || {};
    progress[lesson][label] = 1;
    saveProgress();
    showProgress();
  }

  // Player -----------------------------------------------------------------
  var ICON_PLAY = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M7 4.5v15l13-7.5z"/></svg>';
  var ICON_PAUSE = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M6 4h4v16H6zm8 0h4v16h-4z"/></svg>';
  var ICON_PREV = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M6 5h2v14H6zm3.5 7L19 5v14z"/></svg>';
  var ICON_NEXT = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="currentColor" d="M16 5h2v14h-2zM5 5l9.5 7L5 19z"/></svg>';

  function Player(el, cast, section) {
    var self = this;
    this.el = el;
    this.cast = cast;
    this.section = section;
    this.lesson = section.getAttribute("data-lesson");
    this.term = new Term(cast.cols, cast.rows);
    this.t = 0;
    this.next = 0;
    this.playing = false;
    this.speed = 1;
    this.follow = false;
    this.waiting = null; // the prompt follow-along waits on

    var title = el.getAttribute("data-title") || "";
    el.innerHTML =
      '<div class="pg-titlebar"><span class="pg-dots" aria-hidden="true"><i></i><i></i><i></i></span>' +
      '<span class="pg-wtitle">' +
      esc(title ? title + " — nvim" : "nvim") +
      '</span><span class="pg-chapter" aria-live="polite"></span></div>' +
      '<div class="pg-screen"><div class="pg-rows"></div><div class="pg-cursor" aria-hidden="true"></div>' +
      '<div class="pg-keys" aria-live="off"></div>' +
      '<div class="pg-prompt" role="status" aria-live="assertive" hidden></div>' +
      // before the first play: the first screen, dimmed, under a play button
      '<button type="button" class="pg-big-play" aria-label="Play">' +
      '<span class="pg-big-icon">' +
      ICON_PLAY +
      '</span><span class="pg-big-label">Play the lesson · ' +
      fmtTime(cast.duration) +
      "</span></button></div>" +
      '<div class="pg-caption" aria-live="polite"><span></span></div>' +
      '<div class="pg-controls">' +
      '<button type="button" class="pg-btn pg-prev" aria-label="Previous exercise" title="Previous exercise ( [ )">' +
      ICON_PREV +
      "</button>" +
      '<button type="button" class="pg-btn pg-play" aria-label="Play" title="Play / pause (Space)">' +
      ICON_PLAY +
      "</button>" +
      '<button type="button" class="pg-btn pg-next" aria-label="Next exercise" title="Next exercise ( ] )">' +
      ICON_NEXT +
      "</button>" +
      '<span class="pg-time">0:00</span>' +
      '<div class="pg-track"><input type="range" class="pg-seek" min="0" max="' +
      cast.duration +
      '" step="0.05" value="0" aria-label="Position"><div class="pg-ticks"></div></div>' +
      '<span class="pg-dur">' +
      fmtTime(cast.duration) +
      "</span>" +
      '<select class="pg-speed" aria-label="Speed"><option value="0.5">0.5×</option>' +
      '<option value="1" selected>1×</option><option value="1.5">1.5×</option><option value="2">2×</option></select>' +
      '<button type="button" class="pg-btn pg-follow" aria-pressed="false" title="Follow along: the recording waits for you to press each key (f)">Follow along</button>' +
      '<button type="button" class="pg-btn pg-skip" title="Skip this key" hidden>Skip</button>' +
      '<button type="button" class="pg-btn pg-text" title="The transcript: every exercise as text">Transcript</button>' +
      '<button type="button" class="pg-btn pg-copy" title="Copy the text on the screen">Copy</button>' +
      "</div>";

    this.screen = el.querySelector(".pg-screen");
    this.rowsEl = el.querySelector(".pg-rows");
    this.cursorEl = el.querySelector(".pg-cursor");
    this.keysEl = el.querySelector(".pg-keys");
    this.promptEl = el.querySelector(".pg-prompt");
    this.captionEl = el.querySelector(".pg-caption span");
    this.playBtn = el.querySelector(".pg-play");
    this.bigPlay = el.querySelector(".pg-big-play");
    this.seekEl = el.querySelector(".pg-seek");
    this.timeEl = el.querySelector(".pg-time");
    this.chapterEl = el.querySelector(".pg-chapter");
    this.followBtn = el.querySelector(".pg-follow");
    this.skipBtn = el.querySelector(".pg-skip");
    this.rowEls = [];
    for (var r = 0; r < cast.rows; r++) {
      var d = document.createElement("div");
      d.className = "pg-row";
      this.rowsEl.appendChild(d);
      this.rowEls.push(d);
    }
    this.rowsEl.style.width = cast.cols + "ch";
    this.applyTheme(true);

    // the timeline: a tick per exercise, small ones for captions and steps
    var ticks = el.querySelector(".pg-ticks");
    var tick = function (t, label, minor) {
      var tk = document.createElement("span");
      tk.style.left = (100 * t) / cast.duration + "%";
      tk.title = label;
      if (minor) tk.className = "pg-minor";
      ticks.appendChild(tk);
    };
    cast.markers.forEach(function (m) {
      tick(m.t, m.label, false);
    });
    cast.captions.forEach(function (c) {
      tick(c.t, c.text, true);
    });
    cast.steps.forEach(function (s) {
      tick(s.t, s.label, true);
    });

    this.playBtn.addEventListener("click", function () {
      self.toggle();
    });
    this.bigPlay.addEventListener("click", function () {
      self.play();
      // the button hides itself: keep the focus in the player, where
      // Space and the arrows work, rather than dropping it to the page
      self.el.focus({ preventScroll: true });
    });
    this.rowsEl.addEventListener("click", function () {
      // a click that selects text doesn't toggle
      var sel = window.getSelection && window.getSelection();
      if (self.waiting) self.el.focus({ preventScroll: true });
      else if (!sel || sel.isCollapsed) self.toggle();
    });
    this.promptEl.addEventListener("click", function () {
      self.el.focus({ preventScroll: true });
    });
    el.querySelector(".pg-prev").addEventListener("click", function () {
      self.chapter(-1);
    });
    el.querySelector(".pg-next").addEventListener("click", function () {
      self.chapter(1);
    });
    this.seekEl.addEventListener("input", function () {
      self.seek(parseFloat(self.seekEl.value));
    });
    el.querySelector(".pg-speed").addEventListener("change", function (e) {
      self.setSpeed(parseFloat(e.target.value));
    });
    this.followBtn.addEventListener("click", function () {
      self.setFollow(!self.follow);
    });
    this.skipBtn.addEventListener("click", function () {
      if (self.waiting) self.accept(self.waiting.keys.length - self.waiting.pos);
      self.el.focus({ preventScroll: true });
    });
    el.querySelector(".pg-text").addEventListener("click", function () {
      var tr = section.querySelector(".pg-transcript");
      if (!tr) return;
      self.pause();
      tr.open = true;
      tr.scrollIntoView({ block: "start", behavior: scrollBehavior() });
      var summary = tr.querySelector("summary");
      if (summary) summary.focus({ preventScroll: true });
    });
    var copyBtn = el.querySelector(".pg-copy");
    copyBtn.addEventListener("click", function () {
      var text = self.term.grid.map(rowText).join("\n").replace(/\n+$/, "\n");
      copyText(text, function () {
        copyBtn.textContent = "Copied";
        setTimeout(function () {
          copyBtn.textContent = "Copy";
        }, 1200);
      });
    });
    el.addEventListener("keydown", function (e) {
      if (e.metaKey) return;
      if (self.waiting && (e.target === el || e.target === self.promptEl)) {
        self.press(e);
        return;
      }
      if (e.target.tagName === "SELECT" || e.ctrlKey || e.altKey) return;
      // a button handles its own Space and Enter
      if (e.target !== el && e.target.closest && e.target.closest("button")) return;
      if (e.target.tagName === "INPUT" && (e.key === "ArrowLeft" || e.key === "ArrowRight")) return;
      if (e.key === " " || e.key === "k") self.toggle();
      else if (e.key === "ArrowLeft") self.seek(self.t - 5);
      else if (e.key === "ArrowRight") self.seek(self.t + 5);
      else if (e.key === "[") self.chapter(-1);
      else if (e.key === "]") self.chapter(1);
      else if (e.key === "f") self.setFollow(!self.follow);
      else if (e.key === "Escape" && self.follow) self.setFollow(false);
      else return;
      e.preventDefault();
    });
    el.addEventListener("focusin", function () {
      if (self.waiting) self.renderPrompt();
    });
    el.addEventListener("focusout", function () {
      // after the focus has moved
      setTimeout(function () {
        if (self.waiting) self.renderPrompt();
      }, 0);
    });

    this.fit();
    if (window.ResizeObserver) {
      new ResizeObserver(function () {
        self.fit();
      }).observe(el);
    } else {
      window.addEventListener("resize", function () {
        self.fit();
      });
    }
    // the first screen as the poster
    this.seek(0);
  }

  // The recording's default colors, in the site's theme.
  Player.prototype.applyTheme = function (first) {
    this.screen.style.setProperty("--pg-fg", color(this.cast.fg));
    this.screen.style.setProperty("--pg-bg", color(this.cast.bg));
    if (!first) {
      this.term.touch();
      this.render();
    }
  };

  // The font size that fits the columns in the width (up to 18px; on a
  // narrow screen as small as it takes, never cutting columns off).
  var charRatio = null;
  function measureRatio(el) {
    if (charRatio) return charRatio;
    var probe = document.createElement("span");
    probe.className = "pg-probe";
    probe.textContent = "MMMMMMMMMM";
    el.appendChild(probe);
    charRatio = probe.getBoundingClientRect().width / 1000 || 0.6;
    el.removeChild(probe);
    return charRatio;
  }

  Player.prototype.fit = function () {
    var width = this.el.clientWidth - 2 * 10;
    if (width <= 0) return;
    var ratio = measureRatio(this.screen);
    var size = Math.min(18, width / (this.cast.cols * ratio));
    this.screen.style.fontSize = Math.floor(size * 100) / 100 + "px";
    // glyph widths don't scale exactly with the font size: measure the
    // columns at this size and shrink to what fits
    var probe = document.createElement("span");
    probe.className = "pg-probe";
    probe.style.fontSize = "inherit";
    probe.textContent = new Array(this.cast.cols + 1).join("M");
    this.screen.appendChild(probe);
    var need = probe.getBoundingClientRect().width;
    this.screen.removeChild(probe);
    if (need > width) {
      size = Math.min(size, (size * width) / need);
      this.screen.style.fontSize = Math.floor(size * 100) / 100 + "px";
    }
  };

  Player.prototype.apply = function (upTo) {
    var ev = this.cast.events;
    while (this.next < ev.length && ev[this.next][0] <= upTo) {
      var e = ev[this.next];
      if (e[1] === "o") this.term.write(e[2]);
      this.next++;
    }
  };

  // The caption of the moment: the last one at or before it, in the
  // exercise playing.
  Player.prototype.currentCaption = function () {
    var m = this.currentMarker();
    var from = m ? m.t : 0;
    var cur = null;
    var cs = this.cast.captions;
    for (var i = 0; i < cs.length && cs[i].t <= this.t + 1e-6; i++) if (cs[i].t >= from) cur = cs[i];
    return cur;
  };

  Player.prototype.render = function () {
    var term = this.term;
    for (var r = 0; r < term.rows; r++) {
      if (term.dirty[r]) {
        this.rowEls[r].innerHTML = rowHTML(term.grid[r]) || " ";
        term.dirty[r] = false;
      }
    }
    var c = this.cursorEl;
    c.hidden = !term.cursorShown;
    c.style.left = term.col + "ch";
    c.style.top = term.row * 1.25 + "em";
    c.className = "pg-cursor pg-shape-" + term.shape;
    var under = term.grid[term.row] && term.grid[term.row][term.col];
    c.textContent = term.shape <= 2 && under ? under[0] || " " : "";

    var keys = this.waiting ? [] : recentKeys(this.cast.inputs, this.t);
    var html = keys
      .map(function (g) {
        return g.typed ? '<span class="pg-typed">' + esc(g.text) + "</span>" : "<kbd>" + esc(g.text) + "</kbd>";
      })
      .join(" ");
    if (this.keysEl._html !== html) {
      this.keysEl.innerHTML = html;
      this.keysEl._html = html;
      this.keysEl.hidden = !html;
    }

    var cap = this.currentCaption();
    var text = cap ? cap.text : "";
    if (this.captionEl.textContent !== text) this.captionEl.textContent = text;

    this.seekEl.value = this.t;
    this.timeEl.textContent = fmtTime(this.t);
    var m = this.currentMarker();
    var label = m ? m.label : "";
    if (this.chapterEl.textContent !== label) {
      this.chapterEl.textContent = label;
      var items = this.section.querySelectorAll(".pg-steps > li");
      var current = null;
      for (var i = 0; i < items.length; i++) {
        var on = items[i].getAttribute("data-marker") === label;
        items[i].classList.toggle("pg-current", on);
        // the exercises before the current one, as done
        items[i].classList.toggle("pg-seen", !current && !on && !!label);
        if (on) current = items[i];
      }
      if (current) this.reveal(current);
    }
    var playing = this.playing || !!this.waiting;
    if (this.playBtn._playing !== playing) {
      this.playBtn.innerHTML = playing ? ICON_PAUSE : ICON_PLAY;
      this.playBtn.setAttribute("aria-label", playing ? "Pause" : "Play");
      this.playBtn._playing = playing;
    }
    this.bigPlay.hidden = this.playing || this.started || !!this.waiting;
  };

  // Scroll the exercise list beside the player (wide screens, where it
  // scrolls on its own) to put `li` at its top, under the list's heading;
  // the page itself doesn't move.
  Player.prototype.reveal = function (li) {
    var box = this.section.querySelector(".pg-side");
    if (!box || box.scrollHeight <= box.clientHeight + 1) return;
    var head = box.querySelector(".pg-side-head");
    var top = li.offsetTop - (head ? head.offsetHeight : 0) - 4; // .pg-side is its offsetParent
    box.scrollTo({ top: Math.max(0, top), behavior: scrollBehavior() });
  };

  Player.prototype.currentMarker = function () {
    var ms = this.cast.markers;
    var cur = null;
    for (var i = 0; i < ms.length && ms[i].t <= this.t + 1e-6; i++) cur = ms[i];
    return cur;
  };

  Player.prototype.seek = function (t) {
    t = Math.max(0, Math.min(t, this.cast.duration));
    if (this.waiting) this.stopWaiting();
    if (t < this.t || this.next === 0) {
      this.term.reset();
      this.next = 0;
    }
    this.t = t;
    this.apply(t);
    if (this.playing) {
      this.wallStart = performance.now();
      this.tStart = t;
    }
    this.render();
  };

  // The prompt follow-along stops at next, after time `t`.
  Player.prototype.nextPrompt = function (t) {
    var ps = this.cast.prompts;
    for (var i = 0; i < ps.length; i++) if (ps[i].t > t + 1e-6) return ps[i];
    return null;
  };

  Player.prototype.play = function () {
    if (this.playing) return;
    if (this.waiting) return this.el.focus({ preventScroll: true });
    if (this.t >= this.cast.duration - 0.01) this.seek(0);
    this.playing = true;
    this.started = true;
    this.wallStart = performance.now();
    this.tStart = this.t;
    var self = this;
    var last = this.wallStart;
    var tick = function () {
      if (!self.playing) return;
      var now = performance.now();
      // no frames while the tab is hidden (or the machine slept): carry on
      // from where it was rather than jumping ahead
      if (now - last > 250) self.wallStart += now - last - 16;
      last = now;
      var t = self.tStart + ((now - self.wallStart) / 1000) * self.speed;
      var stop = self.follow ? self.nextPrompt(self.t) : null;
      var before = self.currentMarker();
      if (stop && t >= stop.t) {
        // follow-along: up to just before the key, then wait for it
        t = Math.max(self.t, stop.t - 0.001);
        self.playing = false;
      } else if (t >= self.cast.duration) {
        t = self.cast.duration;
        self.playing = false;
      }
      self.t = t;
      self.apply(t);
      var after = self.currentMarker();
      // an exercise played to its end counts as watched
      if (before && after !== before) markWatched(self.lesson, before.label);
      if (t >= self.cast.duration && after) markWatched(self.lesson, after.label);
      if (stop && !self.playing && t < self.cast.duration) self.wait(stop);
      self.render();
      if (self.playing) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    this.render();
  };

  Player.prototype.pause = function () {
    this.playing = false;
    if (this.waiting) this.stopWaiting();
    this.render();
  };

  Player.prototype.toggle = function () {
    if (this.playing || this.waiting) this.pause();
    else this.play();
  };

  Player.prototype.setSpeed = function (s) {
    if (this.playing) {
      this.tStart = this.t;
      this.wallStart = performance.now();
    }
    this.speed = s;
  };

  Player.prototype.chapter = function (dir) {
    var ms = this.cast.markers;
    var cur = -1;
    for (var i = 0; i < ms.length && ms[i].t <= this.t + 0.3; i++) cur = i;
    // "previous" restarts the current exercise unless it has just begun
    if (dir < 0 && cur >= 0 && this.t - ms[cur].t > 1.5) dir = 0;
    var k = Math.max(0, Math.min(ms.length - 1, cur + dir));
    if (ms[k]) this.seek(ms[k].t);
  };

  Player.prototype.jumpTo = function (label) {
    var ms = this.cast.markers;
    for (var i = 0; i < ms.length; i++) {
      if (ms[i].label === label) {
        this.seek(ms[i].t);
        this.play();
        return;
      }
    }
  };

  // Follow along --------------------------------------------------------------
  Player.prototype.setFollow = function (on) {
    this.follow = on;
    this.followBtn.setAttribute("aria-pressed", on ? "true" : "false");
    this.followBtn.classList.toggle("pg-on", on);
    this.skipBtn.hidden = !on;
    this.el.classList.toggle("pg-following", on);
    if (!on && this.waiting) {
      // back to watching: carry on from here
      this.stopWaiting();
      this.play();
    } else if (on && !this.playing) {
      this.play();
    }
    this.render();
  };

  Player.prototype.wait = function (p) {
    p.pos = 0;
    this.waiting = p;
    this.renderPrompt();
  };

  Player.prototype.stopWaiting = function () {
    this.waiting = null;
    this.promptEl.hidden = true;
    this.promptEl.innerHTML = "";
  };

  // The prompt over the screen: the keys to press, the ones pressed done.
  Player.prototype.renderPrompt = function (wrong) {
    var p = this.waiting;
    if (!p) return;
    var focused = document.activeElement === this.el || this.el.contains(document.activeElement);
    var keys;
    if (p.typed && p.keys.length > 1) {
      keys =
        '<span class="pg-prompt-typed"><span class="pg-prompt-done">' +
        esc(p.text.slice(0, p.pos)) +
        "</span>" +
        esc(p.text.slice(p.pos)) +
        "</span>";
    } else {
      keys = p.keys
        .map(function (k, i) {
          return "<kbd" + (i < p.pos ? ' class="pg-prompt-done"' : "") + ">" + esc(keyLabel(k.label)) + "</kbd>";
        })
        .join(" ");
    }
    var what = p.typed && p.keys.length > 1 ? "Type" : "Press";
    var hint =
      p.typed && p.keys.length > 1
        ? "Enter types the rest"
        : p.keys.some(function (k) {
              return /^<leader>/i.test(k.label);
            })
          ? "&lt;leader&gt; is Space here"
          : "";
    this.promptEl.innerHTML =
      '<span class="pg-prompt-what">' +
      (focused ? what : "Click here, then " + what.toLowerCase()) +
      "</span> " +
      keys +
      (wrong ? '<span class="pg-prompt-wrong">Not that one: you pressed ' + esc(keyLabel(wrong)) + "</span>" : "") +
      '<span class="pg-prompt-help">' +
      (hint ? hint + " · " : "") +
      (p.keys[p.pos] && p.keys[p.pos].id === "<Esc>"
        ? "Esc is the key here; the Follow along button stops following"
        : "Esc stops following") +
      "</span>";
    this.promptEl.hidden = false;
    this.render();
  };

  // A key pressed while follow-along waits.
  Player.prototype.press = function (e) {
    var id = eventKey(e);
    if (!id) return;
    var p = this.waiting;
    var want = p.keys[p.pos].id;
    e.preventDefault();
    if (id === want) return this.accept(1);
    if (id === "<Esc>") return this.setFollow(false);
    // Enter types the rest of a word
    if (id === "<CR>" && isTyped(want)) return this.accept(p.keys.length - p.pos);
    this.renderPrompt(id);
  };

  // `n` more keys of the prompt pressed: the screen as after them.
  Player.prototype.accept = function (n) {
    var p = this.waiting;
    if (!p) return;
    var pos = Math.min(p.keys.length, p.pos + n);
    var t = p.keys[pos - 1].t + 0.06; // the frame drawn after the key
    this.waiting = null;
    if (t > this.t) {
      this.t = t;
      this.apply(t);
    }
    if (pos >= p.keys.length) {
      this.stopWaiting();
      this.play();
    } else {
      p.pos = pos;
      this.waiting = p;
      this.renderPrompt();
    }
  };

  // Lessons and tabs ---------------------------------------------------------
  var players = {};
  var ready = {};
  // Load a lesson's player; `cb(player)` once it is there.
  function openLesson(section, cb) {
    var name = section.getAttribute("data-lesson");
    if (players[name]) return cb && cb(players[name]);
    ready[name] = ready[name] || [];
    if (cb) ready[name].push(cb);
    if (players[name] !== undefined) return;
    players[name] = null;
    var el = section.querySelector(".pg-player");
    el.classList.add("pg-loading");
    load(name, section.getAttribute("data-src"), function (cast) {
      el.classList.remove("pg-loading");
      if (!cast) {
        el.innerHTML = '<p class="pg-error">The recording could not be loaded: read the transcript below.</p>';
        return;
      }
      players[name] = new Player(el, cast, section);
      toHashTarget();
      ready[name].forEach(function (f) {
        f(players[name]);
      });
      ready[name] = [];
    });
  }

  var sections = document.querySelectorAll(".pg-lesson");
  var tabs = document.querySelectorAll('.pg-path [role="tab"]');
  // `user`: picked by the reader, so the address names the lesson
  function selectTab(tab, focus, user) {
    for (var i = 0; i < tabs.length; i++) {
      var on = tabs[i] === tab;
      tabs[i].setAttribute("aria-selected", on ? "true" : "false");
      tabs[i].tabIndex = on ? 0 : -1;
      var panel = document.getElementById(tabs[i].getAttribute("aria-controls"));
      if (panel) {
        panel.hidden = !on;
        if (on) openLesson(panel);
        else {
          var p = players[panel.getAttribute("data-lesson")];
          if (p) p.pause();
        }
      }
    }
    if (focus) tab.focus();
    if (user) {
      try {
        history.replaceState(null, "", "#" + tab.id.replace(/^tab-/, ""));
      } catch (e) {}
    }
  }
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  function scrollBehavior() {
    return reduceMotion ? "auto" : "smooth";
  }
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].addEventListener("click", function (e) {
      selectTab(e.currentTarget, false, true);
    });
    tabs[i].addEventListener("keydown", function (e) {
      // one row of tabs across the levels
      var list = Array.prototype.slice.call(tabs);
      var k = list.indexOf(e.currentTarget);
      if (e.key === "ArrowRight" || e.key === "ArrowDown") selectTab(list[(k + 1) % list.length], true, true);
      else if (e.key === "ArrowLeft" || e.key === "ArrowUp")
        selectTab(list[(k - 1 + list.length) % list.length], true, true);
      else if (e.key === "Home") selectTab(list[0], true, true);
      else if (e.key === "End") selectTab(list[list.length - 1], true, true);
      else return;
      e.preventDefault();
    });
  }
  // Play an exercise of a lesson: open its tab, scroll to the player.
  function playExercise(section, label) {
    var tab = document.getElementById(section.getAttribute("aria-labelledby"));
    if (tab) selectTab(tab, false, true);
    openLesson(section, function (p) {
      p.jumpTo(label);
      var el = section.querySelector(".pg-player");
      el.scrollIntoView({ block: "nearest", behavior: scrollBehavior() });
      el.focus({ preventScroll: true });
    });
  }
  for (var s = 0; s < sections.length; s++) {
    (function (section) {
      section.addEventListener("click", function (e) {
        var btn = e.target.closest(".pg-jump");
        if (!btn) return;
        var li = btn.closest("li");
        if (li) playExercise(section, li.getAttribute("data-marker"));
      });
    })(sections[s]);
  }
  // "Try it in Neovim": copy the command
  document.addEventListener("click", function (e) {
    var btn = e.target.closest && e.target.closest(".pg-copy-cmd");
    if (!btn) return;
    copyText(btn.getAttribute("data-copy"), function () {
      btn.textContent = "Copied";
      setTimeout(function () {
        btn.textContent = "Copy";
      }, 1200);
    });
  });

  // Progress on the page: watched exercises ticked, n/total on each lesson
  // card, and "Continue" to the first exercise not watched yet.
  function exercisesOf(section) {
    return Array.prototype.filter.call(section.querySelectorAll(".pg-steps > li[data-marker]"), function (li) {
      return EXERCISE.test(li.getAttribute("data-marker"));
    });
  }
  var resume = document.querySelector(".pg-resume");
  var resumeTarget = null;
  function showProgress() {
    var any = false;
    resumeTarget = null;
    var ordered = Array.prototype.slice.call(sections).sort(function (a, b) {
      return (+a.getAttribute("data-order") || 0) - (+b.getAttribute("data-order") || 0);
    });
    ordered.forEach(function (section) {
      var name = section.getAttribute("data-lesson");
      var done = 0;
      var items = exercisesOf(section);
      items.forEach(function (li) {
        var on = watched(name, li.getAttribute("data-marker"));
        li.classList.toggle("pg-done", on);
        if (on) done++;
        else if (!resumeTarget) resumeTarget = { section: section, li: li };
      });
      any = any || done > 0;
      var tab = document.getElementById("tab-" + name);
      var badge = tab && tab.querySelector(".pg-tab-progress");
      if (badge) {
        badge.textContent = done ? done + "/" + items.length : "";
        badge.classList.toggle("pg-complete", done === items.length && done > 0);
        badge.setAttribute("aria-label", done ? done + " of " + items.length + " exercises watched" : "");
      }
    });
    if (!resume) return;
    resume.hidden = !any;
    var what = resume.querySelector(".pg-continue-what");
    var cont = resume.querySelector(".pg-continue");
    if (resumeTarget) {
      var tab = document.getElementById(resumeTarget.section.getAttribute("aria-labelledby"));
      var num = tab ? tab.querySelector(".pg-tab-num").firstChild.textContent : "";
      what.textContent = num + " · " + resumeTarget.li.getAttribute("data-marker");
      cont.disabled = false;
    } else {
      what.textContent = "every exercise watched";
      cont.disabled = true;
    }
  }
  if (resume) {
    resume.querySelector(".pg-continue").addEventListener("click", function () {
      if (resumeTarget) playExercise(resumeTarget.section, resumeTarget.li.getAttribute("data-marker"));
    });
    resume.querySelector(".pg-forget").addEventListener("click", function () {
      progress = {};
      saveProgress();
      showProgress();
    });
  }
  showProgress();

  // #workflow opens that lesson; an anchor inside a lesson (#workflow-1-1)
  // opens its lesson and scrolls to it; any other (#try-the-syntax) is
  // left to the browser. The address is never rewritten here.
  //
  // A player that loads above the element the address names moves it down:
  // it is scrolled to again then, until the reader scrolls.
  var hashTarget = null;
  function toHashTarget() {
    if (hashTarget) hashTarget.scrollIntoView({ block: "start" });
  }
  ["wheel", "touchstart", "mousedown", "keydown"].forEach(function (ev) {
    window.addEventListener(
      ev,
      function () {
        hashTarget = null;
      },
      { passive: true }
    );
  });
  function followHash(initial) {
    var id = "";
    try {
      id = decodeURIComponent(location.hash.slice(1));
    } catch (e) {}
    var tab = id && document.getElementById("tab-" + id);
    hashTarget = null;
    if (tab) {
      selectTab(tab);
      return true;
    }
    var target = id && document.getElementById(id);
    hashTarget = target || null;
    var section = target && target.closest && target.closest(".pg-lesson");
    if (section) {
      tab = document.getElementById(section.getAttribute("aria-labelledby"));
      if (tab) selectTab(tab);
      if (target.tagName === "DETAILS") target.open = true;
      // it was hidden when the browser tried to scroll to it
      target.scrollIntoView({ block: "start", behavior: initial ? "auto" : scrollBehavior() });
      return true;
    }
    return false;
  }
  // the first lesson of the course (the one the page shows selected)
  if (!followHash(true) && tabs.length)
    selectTab(document.querySelector('.pg-path [role="tab"][aria-selected="true"]') || tabs[0]);
  window.addEventListener("hashchange", function () {
    followHash(false);
  });

  // Try the syntax -----------------------------------------------------------
  // A few of org.nvim's highlight rules, enough to see what Org text looks
  // like: headlines (by level), TODO keywords, priorities, tags, planning
  // lines, timestamps, lists and checkboxes, tables (cells, rules, numbers),
  // #+ keywords, blocks and their code, drawers and properties, comments,
  // footnotes, links and emphasis. Only a highlighter: nothing is run.
  var TODO = /^(TODO|NEXT|WAITING|HOLD|DONE|CANCELLED|CANCELED)$/;
  var DATE =
    "\\d{4}-\\d{2}-\\d{2}(?: [A-Za-z]{2,3}\\.?)?(?: \\d{1,2}:\\d{2}(?:-\\d{1,2}:\\d{2})?)?(?: (?:[.+]?\\+|-{1,2})\\d+[hdwmy](?:/\\d+[hdwmy])?)*";
  var INLINE = new RegExp(
    [
      "(\\[\\[([^\\]]*)\\](?:\\[([^\\]]*)\\])?\\])", // 1 link, 2 target, 3 description
      "(<" + DATE + ">(?:--<" + DATE + ">)?)", // 4 active timestamp (or range)
      "(\\[" + DATE + "\\](?:--\\[" + DATE + "\\])?)", // 5 inactive timestamp
      "(\\b(?:SCHEDULED|DEADLINE|CLOSED):)", // 6 planning keyword
      "(^|[\\s('\"{])([*/_=~+])(\\S|\\S.*?\\S)\\8(?=$|[\\s.,;:!?'\")}\\]-])", // 7 before, 8 marker, 9 body
      "(\\[\\d*/\\d*\\]|\\[\\d*%\\])", // 10 statistics cookie
      "(\\[fn:[^\\]\\s]*\\])", // 11 footnote reference
      "(\\bhttps?://[^\\s\\]>)]+)", // 12 plain link
    ].join("|"),
    "g"
  );
  var EMPHASIS = { "*": "o-b", "/": "o-i", _: "o-u", "=": "o-v", "~": "o-c", "+": "o-s" };
  function span(cls, text) {
    return '<span class="' + cls + '">' + esc(text) + "</span>";
  }
  function inline(s) {
    var out = "";
    var last = 0;
    var m;
    INLINE.lastIndex = 0;
    while ((m = INLINE.exec(s))) {
      out += esc(s.slice(last, m.index));
      if (m[1]) {
        // the description shows; the target is dimmed
        if (m[3] !== undefined)
          out += span("o-link-mark", "[[" + m[2] + "][") + span("o-link", m[3]) + span("o-link-mark", "]]");
        else out += span("o-link-mark", "[[") + span("o-link", m[2]) + span("o-link-mark", "]]");
      } else if (m[4]) out += span("o-date", m[0]);
      else if (m[5]) out += span("o-date-in", m[0]);
      else if (m[6]) out += span("o-plan", m[0]);
      else if (m[8]) out += esc(m[7]) + span(EMPHASIS[m[8]], m[8] + m[9] + m[8]);
      else if (m[10]) out += span("o-cookie", m[0]);
      else if (m[11]) out += span("o-fn", m[0]);
      else if (m[12]) out += span("o-link", m[0]);
      last = m.index + m[0].length;
      if (!m[0].length) INLINE.lastIndex++;
    }
    return out + esc(s.slice(last));
  }

  function tableLine(line) {
    if (/^\s*\|[-+|:]*\s*$/.test(line) && /-/.test(line)) return span("o-tbl-rule", line);
    var lead = line.match(/^\s*/)[0];
    var cells = line.slice(lead.length).split("|");
    var out = esc(lead);
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) out += span("o-tbl-bar", "|");
      var cell = cells[i];
      if (/^\s*-?[\d.,]+%?\s*$/.test(cell) && /\d/.test(cell)) out += span("o-num", cell);
      else out += inline(cell);
    }
    return out;
  }

  // One line, and the block it leaves open for the next.
  function highlightLine(line, state) {
    var begin = line.match(/^(\s*#\+begin_)(\w+)(.*)$/i);
    if (begin && !state.block) {
      state.block = begin[2].toLowerCase();
      var args = begin[3].match(/^(\s*)(\S*)(.*)$/);
      var lang = state.block === "src" ? args[2] : "";
      return (
        span("o-block", begin[1] + begin[2]) +
        (lang ? esc(args[1]) + span("o-lang", lang) + span("o-kwv", args[3]) : span("o-kwv", begin[3]))
      );
    }
    if (state.block) {
      if (new RegExp("^\\s*#\\+end_" + state.block + "\\b", "i").test(line)) {
        state.block = null;
        return span("o-block", line);
      }
      if (state.block === "src" || state.block === "example") return span("o-code", line);
      return inline(line);
    }
    var h = line.match(/^(\*+)(\s+)(.*)$/);
    if (h) {
      var level = h[1].length;
      var rest = h[3];
      var out = '<span class="o-stars">' + h[1] + "</span>" + h[2];
      var words = rest.match(/^(\S+)(\s+)(.*)$/);
      if (words && TODO.test(words[1])) {
        out += '<span class="o-' + (/^(DONE|CANCELL?ED)$/.test(words[1]) ? "done" : "todo") + '">' + words[1] + "</span>" + words[2];
        rest = words[3];
      }
      var pri = rest.match(/^(\[#[A-Z0-9]\])(\s*)(.*)$/);
      if (pri) {
        out += '<span class="o-pri">' + pri[1] + "</span>" + pri[2];
        rest = pri[3];
      }
      var tags = rest.match(/^(.*?)(\s+)(:[\w@#%:]+:)\s*$/);
      var title = tags ? tags[1] : rest;
      out += '<span class="o-h o-h' + (((level - 1) % 4) + 1) + '">' + inline(title) + "</span>";
      if (tags) out += tags[2] + '<span class="o-tag">' + esc(tags[3]) + "</span>";
      return out;
    }
    if (/^\s*\|/.test(line)) return tableLine(line);
    var tblfm = line.match(/^(\s*#\+TBLFM:)(.*)$/i);
    if (tblfm) return span("o-kw", tblfm[1]) + span("o-formula", tblfm[2]);
    var kw = line.match(/^(\s*#\+\w+:)(.*)$/);
    if (kw) return span("o-kw", kw[1]) + span("o-kwv", kw[2]);
    if (/^\s*#(\s|$)/.test(line)) return span("o-comment", line);
    if (/^\s*:(\s|$)/.test(line)) return span("o-code", line); // fixed width
    var drawer = line.match(/^(\s*)(:[\w-]+:)(\s.*)?$/);
    if (drawer) return esc(drawer[1]) + span("o-drawer", drawer[2]) + (drawer[3] ? inline(drawer[3]) : "");
    var fn = line.match(/^(\[fn:[^\]]+\])(.*)$/);
    if (fn) return span("o-fn", fn[1]) + inline(fn[2]);
    var li = line.match(/^(\s*)([-+]|\d+[.)])(\s+)(\[[ X-]\]\s)?(.*)$/);
    if (li) {
      var box = li[4] ? '<span class="o-box' + (li[4][1] === "X" ? " o-box-on" : "") + '">' + li[4] + "</span>" : "";
      return li[1] + '<span class="o-bullet">' + li[2] + "</span>" + li[3] + box + inline(li[5]);
    }
    return inline(line);
  }

  var tryBox = document.querySelector(".pg-try");
  if (tryBox) {
    var input = tryBox.querySelector("textarea");
    var hl = tryBox.querySelector(".pg-try-hl");
    var update = function () {
      var state = { block: null };
      // a trailing newline keeps the last (empty) line's height
      hl.innerHTML =
        input.value
          .split("\n")
          .map(function (line) {
            return highlightLine(line, state);
          })
          .join("\n") + "\n";
      hl.scrollTop = input.scrollTop;
      hl.scrollLeft = input.scrollLeft;
    };
    input.addEventListener("input", update);
    input.addEventListener("scroll", function () {
      hl.scrollTop = input.scrollTop;
      hl.scrollLeft = input.scrollLeft;
    });
    var presetBtns = document.querySelectorAll(".pg-preset");
    Array.prototype.forEach.call(presetBtns, function (btn) {
      btn.addEventListener("click", function () {
        var tpl = document.querySelector('.pg-preset-text[data-preset="' + btn.getAttribute("data-preset") + '"]');
        if (!tpl) return;
        input.value = tpl.content ? tpl.content.textContent : tpl.textContent;
        Array.prototype.forEach.call(presetBtns, function (b) {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        });
        input.scrollTop = 0;
        update();
      });
    });
    tryBox.classList.add("pg-try-ready");
    update();
  }
})();
