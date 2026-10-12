---@mod org.export.csl.render.names CSL names
---
--- cs:names, cs:name and cs:et-al (port of citeproc-name.el): name
--- rendering, initials, et-al and the substitute list.
---
--- Part of org.export.csl.render, which loads it.

local U = require("org.export.csl.util")
local R = require("org.export.csl.regex")
local rt = require("org.export.csl.rt")
local S = require("org.export.csl.style")
local M = require("org.export.csl.render")
local shared = require("org.export.csl.render.shared")

local E = M.elements
local aget, acons = U.aget, U.acons
local nf, typed, tcar, tcdr = shared.nf, M.typed, shared.tcar, shared.tcdr

---------------------------------------------------------------------------
-- Names
---------------------------------------------------------------------------

local function nil_or_num(s)
  if s == nil then
    return 0
  end
  return U.to_number(s)
end

local function render_et_al(attrs, ctx)
  if ctx.render_mode == "sort" then
    return ""
  end
  local term = aget(attrs, "term") or "et-al"
  return M.format_single(attrs, M.term_get_text(term, ctx), ctx)
end

--- citeproc-name--conc-nps
local function conc_nps(...)
  local nonnils = {}
  for i = 1, select("#", ...) do
    local x = select(i, ...)
    if x ~= nil and x ~= false then
      nonnils[#nonnils + 1] = x
    end
  end
  if #nonnils > 1 then
    local len = #nonnils
    local particle = nonnils[len - 1]
    local pstr = type(particle) == "table" and particle[2] or particle
    if type(pstr) == "string" and U.ends_with(pstr, "ʼ") then
      local family = nonnils[len]
      return { { {}, particle, family } }
    end
  end
  return nonnils
end

local LCG_RE = "^\\(\\cl\\|\\cy\\|\\cg\\|ʼ\\)*$"

local function lat_cyr_greek_p(name_alist)
  for _, p in ipairs(name_alist) do
    local v = p[2]
    if type(v) == "table" then
      v = v[2]
    end
    if type(v) == "string" and not R.test(LCG_RE, v) then
      return false
    end
  end
  return true
end

local function initialize_hyphenated(name, suffix, remove_hyphens)
  local inner = U.trim(suffix)
  local parts = {}
  for _, p in ipairs(R.split(name, "-", false)) do
    parts[#parts + 1] = U.substring(p, 0, math.min(1, U.len(p)))
  end
  return table.concat(parts, remove_hyphens and inner or (inner .. "-"))
end

--- citeproc-name--initialize
local function initialize(names, suffix, remove_hyphens)
  local trimmed = U.trim(suffix)
  local parts = {}
  for _, it in ipairs(R.split(names, " +", false)) do
    if R.test("-", it) then
      parts[#parts + 1] = initialize_hyphenated(it, suffix, remove_hyphens)
    else
      parts[#parts + 1] = U.substring(it, 0, math.min(1, U.len(it)))
    end
  end
  return table.concat(parts, suffix) .. trimmed
end

local function initials_add_suffix(suffix, names)
  suffix = U.trim(suffix)
  local out = {}
  for _, x in ipairs(R.slice_by_matches(names, "[ \\-]", 0, true)) do
    if x[2] and R.test("^[[:alpha:]]$", x[1]) then
      out[#out + 1] = x[1] .. suffix
    else
      out[#out + 1] = x[1]
    end
  end
  return table.concat(out)
end

local function show_givenname_level(id, ctx)
  local sg = aget(ctx.vars, "show-given-names")
  return aget(sg, id)
end

local function parts_w_sep(c1, c2, sep, ctx)
  local joined = M.join_formatted({ { "delimiter", " " } }, c1, ctx)
  local none = true
  for i = 1, c2.n or #c2 do
    local x = c2[i]
    if type(x) == "table" and x[2] ~= nil and x[2] ~= false then
      none = false
    end
  end
  if none then
    return joined
  end
  return M.join_formatted(
    { { "delimiter", sep } },
    { joined, M.join_formatted({ { "delimiter", " " } }, c2, ctx), n = 2 },
    ctx
  )
end

--- citeproc-name--render-formatted
local function render_formatted(name_alist, attrs, sort_o, ctx)
  local gopts = ctx.opts
  local f = aget(name_alist, "family")
  local g_un = aget(name_alist, "given")
  local s = aget(name_alist, "suffix")
  local d = aget(name_alist, "dropping-particle")
  local n = aget(name_alist, "non-dropping-particle")
  local nid = aget(name_alist, "name-id")
  local all = U.concat(attrs, gopts)
  local sort_sep = aget(all, "sort-separator") or ", "
  local init = aget(all, "initialize") ~= "false"
  local init_with = aget(all, "initialize-with")
  local form = aget(all, "form")
  local name_form = aget(all, "name-form")
  local dnd = aget(gopts, "demote-non-dropping-particle")
  local id = type(nid) == "table" and nid[2] or nil
  local show_given = show_givenname_level(id, ctx)
  if show_given then
    form = "long"
  else
    form = form or name_form or "long"
  end
  local rmode = ctx.render_mode
  if lat_cyr_greek_p(name_alist) then
    local g
    if g_un == nil or (show_given and show_given == 2) then
      g = g_un
    elseif init_with and init then
      g = {
        rt.attrs(g_un) or {},
        initialize(rt.first_content(g_un), init_with, aget(gopts, "initialize-with-hyphen") == "false"),
      }
    elseif init_with then
      g = { rt.attrs(g_un) or {}, initials_add_suffix(init_with, rt.first_content(g_un)) }
    else
      g = g_un
    end
    if form == "long" then
      if sort_o then
        if dnd == "never" or (dnd == "sort-only" and rmode == "display") then
          return parts_w_sep(conc_nps(n, f), { g, d, s, n = 3 }, sort_sep, ctx)
        end
        return parts_w_sep({ f }, { g, d, n, s, n = 4 }, sort_sep, ctx)
      end
      local list = { n = 1 }
      list[1] = g
      for _, x in ipairs(conc_nps(d, n, f)) do
        list.n = list.n + 1
        list[list.n] = x
      end
      list.n = list.n + 1
      list[list.n] = s
      return M.join_formatted({ { "delimiter", " " } }, list, ctx)
    end
    return M.join_formatted({ { "delimiter", " " } }, conc_nps(n, f), ctx)
  end
  if form == "long" then
    return M.join_formatted({ { "delimiter", " " } }, { f, g_un, n = 2 }, ctx)
  end
  return f
end

--- citeproc-name--format-nameparts
local function format_nameparts(name_alist, part_attrs, ctx)
  local given_attrs = aget(part_attrs, "given")
  local family_attrs = aget(part_attrs, "family")
  -- an empty attribute list is Emacs nil
  if given_attrs and #given_attrs == 0 then
    given_attrs = nil
  end
  if family_attrs and #family_attrs == 0 then
    family_attrs = nil
  end
  local out = {}
  for _, p in ipairs(name_alist or {}) do
    local part, content = p[1], p[2]
    local v
    if given_attrs and (part == "given" or part == "dropping-particle") then
      v = M.format_single(given_attrs, content, ctx)
    elseif family_attrs and (part == "family" or part == "non-dropping-particle") then
      v = M.format_single(family_attrs, content, ctx)
    else
      v = { {}, nf(content) }
    end
    out[#out + 1] = { part, v }
  end
  return out
end

local FORMAT_PLUS_AFFIXES = U.concat({ "prefix", "suffix" }, rt.FORMAT_ATTRS)

local function render_name(name, attrs, part_attrs, sort_o, ctx)
  local fattrs = rt.select_attrs(attrs, FORMAT_PLUS_AFFIXES)
  return M.format_single(
    acons("name-id", aget(name, "name-id"), fattrs),
    render_formatted(format_nameparts(name, part_attrs, ctx), attrs, sort_o, ctx),
    ctx
  )
end

--- citeproc-name--render-names
local function render_names(names, attrs, et_al_attrs, part_attrs, ctx)
  local all = U.concat(attrs, ctx.opts)
  local sort_o = ctx.render_mode == "sort" and "all" or aget(all, "name-as-sort-order")
  local count = #(names or {})
  local first = render_name(names[1] or {}, attrs, part_attrs, sort_o, ctx)
  if count == 1 then
    return first
  end
  local delimiter = aget(all, "delimiter") or aget(all, "name-delimiter") or ", "
  local add_names = aget(all, "add-names") or 0
  local position = M.var_value("position", ctx)
  local et_al_min = aget(all, "et-al-min")
  local et_al_use_first = aget(all, "et-al-use-first")
  if position ~= nil and position ~= "first" then
    et_al_min = aget(all, "et-al-subsequent-min") or et_al_min
    et_al_use_first = aget(all, "et-al-subsequent-use-first") or et_al_use_first
  end
  et_al_min = aget(all, "names-min") or et_al_min
  et_al_use_first = aget(all, "names-use-first") or et_al_use_first
  local et_al_use_last = aget(all, "names-use-last") == "true" or aget(all, "et-al-use-last") == "true"
  local et_al_min_val = aget(ctx.vars, "ignore-et-al") and 100 or nil_or_num(et_al_min)
  local use_first_val = add_names + nil_or_num(et_al_use_first)
  local et_al = et_al_min and et_al_use_first and count >= et_al_min_val and use_first_val < count
  local middle_end = et_al and use_first_val or (count - 1)
  local sort_latters = sort_o == "all"
  local middle
  if middle_end >= 2 then
    local ms = {}
    for k = 2, middle_end do
      ms[#ms + 1] = render_name(names[k], attrs, part_attrs, sort_latters, ctx)
    end
    ms.n = middle_end - 1
    middle = M.join_formatted({ { "delimiter", delimiter }, { "prefix", delimiter } }, ms, ctx)
  end
  local last_after_inverted = sort_latters or (sort_o == "first" and middle == nil)
  local last_delim = et_al and aget(all, "delimiter-precedes-et-al")
    or (not et_al and aget(all, "delimiter-precedes-last"))
  if last_delim == false then
    last_delim = nil
  end
  local last_pref = " "
  if
    ((not last_delim or last_delim == "contextual") and middle_end > 1)
    or last_delim == "always"
    or (last_delim == "after-inverted-name" and last_after_inverted)
  then
    last_pref = delimiter
  end
  local last
  local and_ = aget(all, "and")
  if et_al then
    if et_al_use_last then
      last = M.join_formatted(
        nil,
        { delimiter, "… ", render_name(names[count], attrs, part_attrs, sort_latters, ctx), n = 3 },
        ctx
      )
    else
      last = render_et_al(acons("prefix", last_pref, et_al_attrs), ctx)
    end
  elseif and_ then
    local and_str = and_ == "text" and M.term_get_text("and", ctx) or "&"
    last = M.join_formatted(
      { { "prefix", last_pref } },
      { and_str, " ", render_name(names[count], attrs, part_attrs, sort_latters, ctx), n = 3 },
      ctx
    )
  else
    last =
      M.join_formatted(nil, { delimiter, render_name(names[count], attrs, part_attrs, sort_latters, ctx), n = 2 }, ctx)
  end
  return M.join_formatted(U.aremove(attrs, "delimiter"), { first, middle, last, n = 3 }, ctx)
end

--- citeproc-name--render-var
local function render_var(var, attrs, part_attrs, et_al_attrs, with_label, label_before, label_attrs, ctx, ed_trans)
  local add_names = M.var_value("add-names", ctx)
  if add_names then
    local v = aget(add_names, var)
    if v then
      attrs = acons("add-names", v, attrs)
    end
  end
  local value = M.var_value(var, ctx)
  local rendered = render_names(value or {}, attrs, et_al_attrs, part_attrs, ctx)
  if type(rendered) ~= "table" then
    rendered = { {}, nf(rendered) }
  end
  rendered[1] = acons("rendered-names", nil, rendered[1])
  label_attrs = acons("variable", ed_trans and "editortranslator" or var, label_attrs)
  local plural = aget(label_attrs, "plural")
  if not plural or plural == "contextual" then
    label_attrs = acons("plural", #(value or {}) > 1 and "always" or "never", label_attrs)
  end
  if with_label then
    local label = tcar(E.label(label_attrs, ctx))
    local list = label_before and { label, rendered, n = 2 } or { rendered, label, n = 2 }
    return M.join_formatted({ { "rendered-var", var } }, list, ctx)
  end
  rendered[1] = acons("rendered-var", var, rendered[1])
  return rendered
end
M.name_render_var = render_var

--- citeproc-name-render-vars
function M.name_render_vars(
  varstring,
  attrs,
  name_attrs,
  part_attrs,
  et_al_attrs,
  with_label,
  label_before,
  label_attrs,
  ctx
)
  local vars = R.split(varstring or "", " ", false)
  local present = {}
  for _, v in ipairs(vars) do
    if M.var_value(v, ctx) then
      present[#present + 1] = v
    end
  end
  local ed_trans = false
  local has = U.set(present)
  if has.editor and has.translator and #present == 2 then
    local function ids(v)
      local out = {}
      for _, nm in ipairs(M.var_value(v, ctx) or {}) do
        out[#out + 1] = aget(nm, "name-id")
      end
      return out
    end
    if vim.deep_equal(ids("editor"), ids("translator")) then
      present = { "editor" }
      ed_trans = true
    end
  end
  if not aget(attrs, "delimiter") then
    local nd = aget(ctx.opts, "names-delimiter")
    if nd then
      attrs = acons("delimiter", nd, attrs)
    end
  end
  if #present > 0 then
    local rendered = {}
    for _, v in ipairs(present) do
      rendered[#rendered + 1] =
        render_var(v, name_attrs, part_attrs, et_al_attrs, with_label, label_before, label_attrs, ctx, ed_trans)
    end
    return typed(M.join_formatted(attrs, rendered, ctx), "present-var")
  end
  return typed(nil, "empty-vars")
end

--- citeproc-style--transform-names
local function compile_names(frag)
  local names_attrs = frag.attrs
  local vars = aget(names_attrs, "variable")
  local name_attrs, name_parts, et_al_attrs, label_attrs
  local is_label, label_before = false, false
  local substs = {}
  for _, it in ipairs(frag) do
    if type(it) == "table" then
      if it.tag == "name" then
        name_attrs = it.attrs
        name_parts = S.named_parts(it)
        label_before = true
      elseif it.tag == "et-al" then
        et_al_attrs = it.attrs
      elseif it.tag == "label" then
        is_label = true
        label_attrs = it.attrs
        label_before = false
      elseif it.tag == "substitute" then
        substs = {}
        for _, x in ipairs(it) do
          if type(x) == "table" then
            if x.tag == "names" then
              local v = aget(x.attrs, "variable")
              substs[#substs + 1] = function(ctx)
                return M.name_render_vars(
                  v,
                  names_attrs,
                  name_attrs,
                  name_parts,
                  et_al_attrs,
                  is_label,
                  label_before,
                  label_attrs,
                  ctx
                )
              end
            else
              substs[#substs + 1] = M.compile(x)
            end
          end
        end
      end
    end
  end
  return function(ctx)
    if M.var_value("suppress-author", ctx) then
      return typed(nil, "empty-vars")
    end
    local count = aget(name_attrs, "form") == "count"
    local val = M.name_render_vars(
      vars,
      names_attrs,
      name_attrs,
      name_parts,
      et_al_attrs,
      is_label,
      label_before,
      label_attrs,
      ctx
    )
    local result
    if tcar(val) then
      result = val
    else
      local evaluated = {}
      for i, s in ipairs(substs) do
        evaluated[i] = s(ctx)
      end
      for _, e in ipairs(evaluated) do
        if type(e) == "table" and (e.splice or tcar(e)) then
          local cont = e.splice and "splice" or tcar(e)
          result = typed({ { { "subst", true } }, cont }, tcdr(e))
          break
        end
      end
      result = result or typed(nil, "empty-vars")
    end
    local final = result
    if count then
      local number = rt.count_names(tcar(result))
      final = typed(number == 0 and "" or tostring(number), tcdr(result))
    end
    return M.maybe_stop_rendering("names", ctx, final)
  end
end

shared.compile_names = compile_names

return M
