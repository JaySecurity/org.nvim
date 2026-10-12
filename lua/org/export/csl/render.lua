---@mod org.export.csl.render CSL rendering elements
--- (port of citeproc-context.el, citeproc-generic-elements.el,
--- citeproc-choose.el, citeproc-macro.el, citeproc-name.el,
--- citeproc-date.el, citeproc-number.el, citeproc-prange.el and the
--- sort-key part of citeproc-sort.el)
---
--- A style element is compiled into a function of the rendering context.
--- Most return a typed value `{ c = rich_text, t = type }` where the type
--- is "text-only", "empty-vars" or "present-var"; `false` stands for an
--- Emacs nil value.
---
--- This file holds the context, text casing, joining, splicing, the
--- generic elements (layout, group, text, macro), conditions, labels and
--- compilation; the rest loads from org/export/csl/render/: names, date,
--- number (numbers and page ranges) and sort (sort keys).

local U = require("org.export.csl.util")
local R = require("org.export.csl.regex")
local rt = require("org.export.csl.rt")
local S = require("org.export.csl.style")

local M = {}
-- The parts in org/export/csl/render/ add their functions to this table
-- and require it back, so it must be in package.loaded before they load.
package.loaded["org.export.csl.render"] = M
local shared = require("org.export.csl.render.shared")

local aget, acons = U.aget, U.acons

--- Emacs nil inside a list is stored as false.
local function nf(x)
  if x == nil then
    return false
  end
  return x
end

local function typed(c, t)
  if c == false then
    c = nil
  end
  return { c = c, t = t }
end
M.typed = typed

local function tcar(v)
  if type(v) == "table" and not v.splice then
    return v.c
  end
  return nil
end

local function tcdr(v)
  if type(v) == "table" and not v.splice then
    return v.t
  end
  return nil
end

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------

--- citeproc-context-create
function M.context_create(vars, style, mode, render_mode, no_external_links)
  return {
    vars = vars,
    macros = style.macros,
    terms = style.terms,
    date_text = style.date_text,
    date_numeric = style.date_numeric,
    opts = S.global_opts(style, mode),
    locale = style.locale,
    locale_opts = style.locale_opts,
    mode = mode,
    render_mode = render_mode,
    render_year_suffix = not style.uses_ys_var,
    no_external_links = no_external_links,
  }
end

local SHORT_LONG = { title = "title-short", ["container-title"] = "container-title-short" }

--- citeproc-var-value
function M.var_value(var, ctx, form)
  local vals = ctx.vars
  if form == "short" or (var == "title" and aget(vals, "use-short-title")) then
    local short = SHORT_LONG[var]
    local sv = short and aget(vals, short)
    if short and sv then
      return sv
    end
    return aget(vals, var)
  end
  local val = aget(vals, var)
  if val and ((var == "locator" and M.var_value("label", ctx) == "page") or var == "page") then
    local fmt = aget(ctx.opts, "page-range-format")
    local sep = S.term_text_from_terms("page-range-delimiter", ctx.terms) or "–"
    return rt.from_str(M.prange_render(val, fmt, sep))
  end
  return val
end

function M.term_get_text(term, ctx)
  return S.term_text_from_terms(term, ctx.terms)
end

local FORM_FALLBACK = { ["verb-short"] = "verb", symbol = "short", verb = "long", short = "long" }

--- citeproc-term-inflected-text
function M.term_inflected_text(term, form, number, ctx)
  local matches = {}
  for _, t in ipairs(ctx.terms or {}) do
    if t.name == term then
      matches[#matches + 1] = t
    end
  end
  if #matches == 0 then
    return nil
  end
  local match
  while not match and form do
    for _, t in ipairs(matches) do
      if t.form == form and (not t.number or t.number == number) then
        match = t
        break
      end
    end
    if not match then
      form = FORM_FALLBACK[form]
    end
  end
  return match and match.text or nil
end

function M.term_get_gender(term, ctx)
  for _, t in ipairs(ctx.terms or {}) do
    if t.name == term and t.gender and t.form == "long" then
      return t.gender
    end
  end
  return nil
end

--- citeproc-rt-quote (on a list of rich texts)
local function rt_quote(rts, ctx)
  local oq = M.term_get_text("open-quote", ctx)
  local cq = M.term_get_text("close-quote", ctx)
  local oiq = M.term_get_text("open-inner-quote", ctx)
  local ciq = M.term_get_text("close-inner-quote", ctx)
  local function q(s)
    return (s or ""):gsub("[%^%$%.%*%+%?%[%]\\]", "\\%0")
  end
  local re = string.format("\\(%s\\|%s\\|%s\\|%s\\)", q(oq), q(cq), q(oiq), q(ciq))
  local out = { oq }
  for _, r in ipairs(rt.replace_all_sim({ { oq, oiq }, { cq, ciq }, { oiq, oq }, { ciq, cq } }, re, rts)) do
    out[#out + 1] = r
  end
  out[#out + 1] = cq
  return out
end

--- citeproc-s-capitalize-first
local function capitalize_first(s)
  if U.blank(s) then
    return s
  end
  local done = false
  return U.map_words(s, function(w)
    if done then
      return nil
    end
    done = true
    if U.lowercase_p(w) then
      return U.capitalize_word(w)
    end
  end)
end
M.capitalize_first = capitalize_first

local function capitalize_all(s)
  if U.blank(s) then
    return s
  end
  return U.map_words(s, function(w)
    if U.lowercase_p(w) then
      return U.capitalize_word(w)
    end
  end)
end

local function sentence_case(s)
  if U.blank(s) then
    return s
  end
  local first = true
  return U.map_words(s, function(w)
    local r
    if U.uppercase_p(w) then
      r = U.capitalize_word(w)
    elseif first and U.lowercase_p(w) then
      r = U.capitalize_word(w)
    end
    first = false
    return r
  end)
end

local STOPWORDS = U.set({
  "a",
  "according to",
  "across",
  "afore",
  "after",
  "against",
  "ahead of",
  "along",
  "alongside",
  "amid",
  "amidst",
  "among",
  "amongst",
  "an",
  "and",
  "anenst",
  "apart from",
  "apropos",
  "around",
  "as",
  "as regards",
  "aside",
  "astride",
  "at",
  "athwart",
  "atop",
  "back to",
  "barring",
  "because of",
  "before",
  "behind",
  "below",
  "beneath",
  "beside",
  "besides",
  "between",
  "beyond",
  "but",
  "by",
  "c",
  "ca",
  "circa",
  "close to",
  "d'",
  "de",
  "despite",
  "down",
  "due to",
  "during",
  "et",
  "except",
  "far from",
  "for",
  "forenenst",
  "from",
  "given",
  "in",
  "inside",
  "instead of",
  "into",
  "lest",
  "like",
  "modulo",
  "near",
  "next",
  "nor",
  "of",
  "off",
  "on",
  "onto",
  "or",
  "out",
  "outside of",
  "over",
  "per",
  "plus",
  "prior to",
  "pro",
  "pursuant\n    to",
  "qua",
  "rather than",
  "regardless of",
  "sans",
  "since",
  "so",
  "such as",
  "than",
  "that of",
  "the",
  "through",
  "throughout",
  "thru",
  "thruout",
  "till",
  "to",
  "toward",
  "towards",
  "under",
  "underneath",
  "until",
  "unto",
  "up",
  "upon",
  "v.",
  "van",
  "versus",
  "via",
  "vis-à-vis",
  "von",
  "vs.",
  "where as",
  "with",
  "within",
  "without",
  "yet",
})

--- citeproc-s-title-case
local function title_case(s)
  if U.blank(s) then
    return s
  end
  local first = true
  local after_colon = false
  return U.map_words(s, function(w, span, cps)
    local r
    local nextc = cps[span[2]]
    if not (first or after_colon) and STOPWORDS[U.downcase(w)] and (w ~= "A" or nextc == nil or nextc ~= 46) then
      r = U.downcase(w)
    elseif U.lowercase_p(w) then
      r = U.capitalize_word(w)
    end
    first = false
    if nextc ~= nil then
      after_colon = nextc == 58 or nextc == 46
    end
    return r
  end)
end

--- citeproc-rt-textcased
local function textcased(rts, case, ctx)
  if case == "uppercase" then
    return rt.map_strings(U.upcase, rts, true)
  elseif case == "lowercase" then
    return rt.map_strings(U.downcase, rts, true)
  end
  local fn
  if case == "capitalize-first" then
    fn = capitalize_first
  elseif case == "capitalize-all" then
    fn = capitalize_all
  elseif case == "sentence" then
    fn = sentence_case
  elseif case == "title" then
    local locale = ctx and ctx.locale
    local language = ctx and M.var_value("language", ctx)
    if
      (language and U.starts_with(language, "en")) or (not language and (not locale or U.starts_with(locale, "en")))
    then
      fn = title_case
    else
      return rts
    end
  else
    return rts
  end
  local out = {}
  for i, r in ipairs(rts) do
    out[i] = rt.change_case(r, fn)
  end
  return out
end

--- citeproc-rt-join-formatted
function M.join_formatted(attrs, rts, ctx)
  local result = {}
  for i = 1, rts.n or #rts do
    local r = rts[i]
    if r ~= nil and r ~= false then
      result[#result + 1] = r
    end
  end
  local text_case = aget(attrs, "text-case")
  if text_case then
    result = textcased(result, text_case, ctx)
  end
  if aget(attrs, "strip-periods") == "true" then
    result = rt.strip_periods(result)
  end
  if aget(attrs, "quotes") == "true" then
    result = rt_quote(result, ctx)
  end
  local node = { rt.select_attrs(attrs, rt.EXT_FORMAT_ATTRS) }
  for _, r in ipairs(result) do
    node[#node + 1] = r
  end
  if aget(attrs, "delimiter") and #node > 2 then
    return node
  end
  return rt.simplify_shallow(node)
end

--- citeproc-rt-format-single
function M.format_single(attrs, r, ctx)
  if r == nil or r == false or r == "" then
    return nil
  end
  return M.join_formatted(attrs, { r }, ctx)
end

local function combined_type(values)
  local all_text, any_present = true, false
  for i = 1, values.n or #values do
    local t = tcdr(values[i])
    if t ~= "text-only" then
      all_text = false
    end
    if t == "present-var" then
      any_present = true
    end
  end
  if all_text then
    return "text-only"
  elseif any_present then
    return "present-var"
  end
  return "empty-vars"
end

local function cars(values)
  local out = { n = values.n or #values }
  for i = 1, out.n do
    out[i] = tcar(values[i])
  end
  return out
end

--- citeproc-rt-typed-join
function M.typed_join(attrs, values, ctx)
  return typed(M.join_formatted(attrs, cars(values), ctx), combined_type(values))
end

--- citeproc-context-int-link-attrval
function M.int_link_attrval(style, internal_links, mode, cite_pos)
  local note = S.cite_note(style)
  if
    (internal_links and internal_links ~= "auto" and internal_links ~= "bib-links")
    or (note and mode == "bib" and (not internal_links or internal_links == "auto"))
  then
    return nil
  end
  if note and internal_links ~= "bib-links" then
    return cite_pos == "first" and "bib-item-no" or "cited-item-no"
  end
  return mode == "cite" and "cited-item-no" or "bib-item-no"
end

local STOP = {}

--- citeproc-context-maybe-stop-rendering
function M.maybe_stop_rendering(trigger, ctx, result, var)
  if
    trigger == aget(ctx.vars, "stop-rendering-at")
    and (not var or var == trigger)
    and tcdr(result) == "present-var"
  then
    local r = tcar(result)
    if type(r) ~= "table" then
      r = { {}, r }
    end
    r[1] = acons("stopped-rendering", true, r[1])
    error({ [STOP] = true, value = rt.render_affixes(r) }, 0)
  end
  return result
end

--- citeproc-render-varlist-in-rt
function M.render_varlist_in_rt(vars, style, mode, render_mode, internal_links, no_external_links)
  local unprocessed = aget(vars, "unprocessed-with-id")
  if unprocessed then
    return { {}, "NO_ITEM_DATA:" .. unprocessed }
  end
  local ctx = M.context_create(vars, style, mode, render_mode, no_external_links)
  local layout = mode == "cite" and style.cite_layout or style.bib_layout
  if not layout then
    return "[NO BIBLIOGRAPHY LAYOUT IN CSL STYLE]"
  end
  local ok, rendered = pcall(layout, ctx)
  if not ok then
    if type(rendered) == "table" and rendered[STOP] then
      rendered = rendered.value
    else
      error(rendered, 0)
    end
  end
  if mode == "bib" and not no_external_links then
    local found
    for _, v in ipairs(rt.LINKED_VARS) do
      local p = U.assoc(vars, v)
      if p then
        found = p
        break
      end
    end
    if found then
      local rendered_vars = U.set(rt.rendered_vars(rendered))
      local inter = false
      for _, v in ipairs(rt.LINKED_VARS) do
        if rendered_vars[v] then
          inter = true
        end
      end
      if not inter then
        rt.link_title(rendered, (rt.LINK_PREFIX[found[1]] or "") .. tostring(aget(vars, found[1])))
      end
    end
  end
  local attr = M.int_link_attrval(style, internal_links, mode, aget(vars, "position"))
  if attr then
    local val = { attr, aget(vars, "citation-number") }
    if type(rendered) == "table" then
      local a = {}
      for _, p in ipairs(rendered[1]) do
        a[#a + 1] = p
      end
      a[#a + 1] = val
      rendered[1] = a
    elseif type(rendered) == "string" then
      rendered = { { val }, rendered }
    end
  end
  local ys = aget(vars, "year-suffix")
  if ys then
    return (rt.add_year_suffix(rendered, style.uses_ys_var and "" or ys))
  end
  return rendered
end

---------------------------------------------------------------------------
-- Splicing
---------------------------------------------------------------------------

local function splice_into(body)
  local out = { n = 0 }
  for i = 1, body.n or #body do
    local elt = body[i]
    if type(elt) == "table" and elt.splice then
      for j = 1, elt.n or #elt do
        out.n = out.n + 1
        out[out.n] = elt[j]
      end
    else
      out.n = out.n + 1
      out[out.n] = nf(elt)
    end
  end
  return out
end

local function add_splice_tag(list)
  local n = list.n or #list
  if n > 1 then
    local s = { splice = true, n = n }
    for i = 1, n do
      s[i] = list[i]
    end
    return s
  end
  local v = list[1]
  if v == nil then
    return false
  end
  return v
end

---------------------------------------------------------------------------
-- Generic elements
---------------------------------------------------------------------------

local E = {}
M.elements = E

function E.layout(attrs, ctx, body)
  if ctx.mode ~= "bib" then
    attrs = {}
  end
  local spliced = splice_into(body)
  local suffix = aget(attrs, "suffix")
  local wo_suffix = U.aremove(attrs, "suffix")
  local rendered = cars(spliced)
  if aget(ctx.opts, "second-field-align") and rendered.n > 1 then
    local rest = { { { "display", "right-inline" } } } ---@type any[]
    for i = 2, rendered.n do
      rest[#rest + 1] = nf(rendered[i])
    end
    rendered = { { { { "display", "left-margin" } }, nf(rendered[1]) }, rest, n = 2 }
  end
  local affixed = rt.render_affixes(rt.dedup(M.join_formatted(wo_suffix, rendered, ctx)))
  local last_elt = type(affixed) == "table" and affixed[#affixed] or nil
  local last_display = type(last_elt) == "table"
    and #last_elt[1] > 0
    and (function()
      for _, p in ipairs(last_elt[1]) do
        if type(p) == "table" and p[1] == "display" then
          return true
        end
      end
      return false
    end)()
  if suffix then
    if last_display then
      local n = {}
      for i = 1, #last_elt do
        n[i] = last_elt[i]
      end
      n[#n + 1] = suffix
      affixed[#affixed] = n
    elseif type(affixed) == "table" then
      affixed[#affixed + 1] = suffix
    elseif affixed == nil then
      affixed = nil
    else
      affixed = affixed .. suffix
    end
  end
  return affixed
end

function E.group(attrs, ctx, body)
  local spliced = splice_into(body)
  local t = combined_type(spliced)
  local c
  if t == "text-only" or t == "present-var" then
    c = M.join_formatted(attrs, cars(spliced), ctx)
  end
  return typed(c, t)
end

local URL_PREFIX_RE = "https?://\\S *\\'"

function E.text(attrs, ctx)
  local content
  local ty = "text-only" ---@type string?
  local value = aget(attrs, "value")
  local variable = aget(attrs, "variable")
  local term = aget(attrs, "term")
  local macro = aget(attrs, "macro")
  local prefix = aget(attrs, "prefix")
  local form = aget(attrs, "form")
  if value then
    content = value
  elseif variable then
    local val = M.var_value(variable, ctx, form)
    content = val
    if val then
      ty = "present-var"
      attrs = acons("rendered-var", variable, attrs)
      if not ctx.no_external_links and U.set(rt.LINKED_VARS)[variable] then
        local target = (rt.LINK_PREFIX[variable] or "") .. rt.to_plain(content)
        if prefix then
          local b = R.search(URL_PREFIX_RE, prefix)
          if b then
            content = U.substring(prefix, b) .. rt.to_plain(content)
            attrs = acons("prefix", U.substring(prefix, 0, b), attrs)
          end
        end
        attrs = acons("href", target, attrs)
      end
    elseif variable ~= "year-suffix" then
      ty = "empty-vars"
    end
  elseif term then
    local f = form or "long"
    local plural = aget(attrs, "plural")
    local number = (not plural or plural == "false") and "single" or "multiple"
    local cont = M.term_inflected_text(term, f, number, ctx)
    if term == "no date" then
      ty = "present-var"
      content = { { { "rendered-var", "issued" } }, nf(cont) }
    else
      content = cont
    end
  elseif macro then
    local v = M.macro_output(macro, ctx)
    content = tcar(v)
    ty = tcdr(v)
  end
  local result = typed(M.format_single(attrs, content, ctx), ty)
  return M.maybe_stop_rendering("title", ctx, result, variable or true)
end

function E.macro(attrs, ctx, body)
  local spliced = splice_into(body)
  local val = M.typed_join(attrs, spliced, ctx)
  if val.t == "empty-vars" then
    return typed(nil, "text-only")
  end
  return val
end

function M.macro_output(name, ctx)
  local fn = ctx.macros and ctx.macros[name]
  if not fn then
    error(string.format("There is no macro called `%s' in style", tostring(name)), 0)
  end
  return fn(ctx)
end

function M.macro_output_as_text(name, ctx)
  return rt.to_plain(rt.render_affixes(tcar(M.macro_output(name, ctx))))
end

---------------------------------------------------------------------------
-- Conditions (cs:choose)
---------------------------------------------------------------------------

local NUMERIC_RE =
  "\\`[[:alpha:]]?[[:digit:]]+[[:alpha:]]*\\(\\( *\\([,&-]\\|--\\) *\\)?[[:alpha:]]?[[:digit:]]+[[:alpha:]]*\\)?\\'"

--- citeproc-lib-numeric-p
function M.numeric_p(val)
  if type(val) == "number" then
    return true
  end
  return type(val) == "string" and R.test(NUMERIC_RE, val)
end

local function eval_elementary(ty, param, ctx)
  if ty == "variable" then
    local v = M.var_value(param, ctx)
    return v ~= nil and v ~= false
  elseif ty == "type" then
    return param == M.var_value("type", ctx)
  elseif ty == "locator" then
    return param == M.var_value("label", ctx)
  elseif ty == "is-numeric" then
    return M.numeric_p(M.var_value(param, ctx))
  elseif ty == "is-uncertain-date" then
    local dates = M.var_value(param, ctx)
    return type(dates) == "table" and dates[1] ~= nil and dates[1].circa and true or false
  elseif ty == "position" then
    if ctx.mode ~= "cite" then
      return false
    end
    if param == "near-note" and M.var_value("near-note", ctx) then
      return true
    end
    local pos = M.var_value("position", ctx)
    return param == pos
      or (param == "subsequent" and (pos == "ibid" or pos == "ibid-with-locator"))
      or (param == "ibid" and pos == "ibid-with-locator")
  elseif ty == "disambiguate" then
    return M.var_value("disambiguate", ctx) and true or false
  end
  return false
end

--- citeproc-choose-eval-conditions
function M.eval_conditions(attrs, ctx)
  local values = {}
  local match = "all"
  for _, p in ipairs(attrs) do
    if type(p) == "table" then
      if p[1] == "match" then
        match = p[2]
      else
        for _, param in ipairs(R.split(p[2], " ", false)) do
          values[#values + 1] = eval_elementary(p[1], param, ctx)
        end
      end
    end
  end
  if match == "all" then
    for _, v in ipairs(values) do
      if not v then
        return false
      end
    end
    return true
  elseif match == "any" then
    for _, v in ipairs(values) do
      if v then
        return true
      end
    end
    return false
  elseif match == "none" then
    for _, v in ipairs(values) do
      if v then
        return false
      end
    end
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------

local function var_plural_p(var, ctx)
  local content = rt.to_plain(M.var_value(var, ctx))
  if var == "number-of-pages" or var == "number-of-volumes" then
    return U.to_number(content) > 1
  end
  local and_term = M.term_get_text("and", ctx) or ""
  local q = and_term:gsub("[%^%$%.%*%+%?%[%]\\]", "\\%0")
  return R.test("[[:digit:]] *\\([-,;–&—―]+\\|[,;]? *" .. q .. "\\) *[a-zA-Z]?[[:digit:]]", content)
end

function E.label(attrs, ctx)
  local variable = aget(attrs, "variable")
  local form = aget(attrs, "form")
  local plural = aget(attrs, "plural")
  local label = variable
  local number
  if label == "editortranslator" or (label and M.var_value(label, ctx)) then
    form = form or "long"
    if variable == "locator" then
      variable = M.var_value("label", ctx)
    end
    if plural == "never" then
      number = "single"
    elseif plural == "always" then
      number = "multiple"
    else
      number = var_plural_p(label, ctx) and "multiple" or "single"
    end
    if label == "locator" and ctx.mode == "cite" then
      attrs = acons("rendered-locator-label", true, attrs)
    end
    return typed(M.format_single(attrs, M.term_inflected_text(variable, form, number, ctx), ctx), "text-only")
  end
  return typed(nil, "text-only")
end

shared.nf = nf
shared.tcar = tcar
shared.tcdr = tcdr

require("org.export.csl.render.names")
require("org.export.csl.render.date")
require("org.export.csl.render.number")
require("org.export.csl.render.sort")

---------------------------------------------------------------------------
-- Compilation
---------------------------------------------------------------------------

local function compile(tree)
  if type(tree) ~= "table" then
    return function()
      return tree
    end
  end
  local tag = tree.tag
  local attrs = tree.attrs or {}
  if tag == "names" then
    return shared.compile_names(tree)
  end
  local kids = {}
  for _, c in ipairs(tree) do
    kids[#kids + 1] = compile(c)
  end
  local function eval_kids(ctx)
    local out = { n = #kids }
    for i, k in ipairs(kids) do
      local v = k(ctx)
      if v == nil then
        v = false
      end
      out[i] = v
    end
    return out
  end
  if tag == "choose" then
    return function(ctx)
      local vals = eval_kids(ctx)
      for i = 1, vals.n do
        local v = vals[i]
        if type(v) == "table" and v.ok then
          return v.value
        end
      end
      return typed(nil, "text-only")
    end
  elseif tag == "if" or tag == "else-if" then
    return function(ctx)
      if M.eval_conditions(attrs, ctx) then
        return { ok = true, value = add_splice_tag(splice_into(eval_kids(ctx))) }
      end
      return false
    end
  elseif tag == "else" then
    return function(ctx)
      return { ok = true, value = add_splice_tag(splice_into(eval_kids(ctx))) }
    end
  end
  local fn = E[tag]
  if not fn then
    error(string.format("Unsupported CSL element: %s", tostring(tag)), 0)
  end
  return function(ctx)
    return fn(attrs, ctx, eval_kids(ctx))
  end
end
M.compile = compile

return M
