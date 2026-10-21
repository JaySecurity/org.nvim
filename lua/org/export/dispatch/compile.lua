---@mod org.export.dispatch.compile Compiling exported files
---
--- PDF from LaTeX (org-latex-compile), Info from Texinfo
--- (org-texinfo-export-to-info) and PDF from man (org-man-compile), in the
--- background on the export stack when asynchronous.
---
--- Part of org.export, which loads it.

local utils = require("org.utils")
local shared = require("org.export.dispatch.shared")

local M = require("org.export")

local cfg = shared.cfg

--- The failure message of a compilation: `err` and the error lines of its
--- output (`log`).
local function failure(err, log)
  local excerpt = require("org.export.process").error_excerpt(log or "")
  if #excerpt > 0 then
    return err .. "\n" .. table.concat(excerpt, "\n")
  end
  return err
end

--- Compile a .tex file to PDF (org-latex-compile). Asynchronous with
--- `opts.async` (or `export.latex.async_compile`): the UI does not block,
--- the compilation is on the export stack while it runs (where it can be
--- cancelled) and a notification is shown when the PDF is ready. Returns
--- the PDF (to be) and, when asynchronous, the running process.
function M.compile_pdf(tex, opts)
  opts = opts or {}
  local latex = require("org.export.latex")
  local pdf = tex:gsub("%.tex$", ".pdf")
  local async = opts.async
  if async == nil then
    async = ((cfg().latex or {}).async_compile ~= false) and #vim.api.nvim_list_uis() > 0
  end
  local entry, proc
  local function done(result, err, warnings, log)
    if not result then
      if not (proc and proc.cancelled) then
        utils.error(failure(err or "PDF compilation failed", log))
      end
      M.stack_job_done(entry, opts, nil, err)
      return
    end
    local msg = "PDF file produced"
    if warnings == "error" then
      msg = msg .. " with errors."
    elseif type(warnings) == "table" and #warnings > 0 then
      msg = msg .. " with warnings: " .. table.concat(warnings, " ")
    else
      msg = msg .. "."
    end
    utils.notify(msg .. " " .. result)
    if opts.open or cfg().open_after_export then
      vim.ui.open(result)
    end
    M.stack_job_done(entry, opts, result)
  end
  utils.notify("Processing LaTeX file " .. tex .. "...")
  if async then
    proc = latex.compile(tex, done)
    entry = M.stack_job(proc, opts.backend or "latex", opts)
    return pdf, proc
  end
  local result, err, warnings, log = latex.compile(tex)
  done(result, err, warnings, log)
  return result
end

--- Process a .texi file into an Info file with makeinfo
--- (org-texinfo-export-to-info). With `opts.open` the manual is shown with
--- `info` in a terminal window. With `opts.async` makeinfo runs in the
--- background, on the export stack.
function M.compile_info(texi, opts)
  opts = opts or {}
  local texinfo = require("org.export.texinfo")
  local entry, proc
  local function done(result, err)
    if not result then
      if not (proc and proc.cancelled) then
        utils.error(err or "Info file was not produced")
      end
      M.stack_job_done(entry, opts, nil, err)
      return
    end
    utils.notify("Exported to " .. result)
    if opts.open or cfg().open_after_export then
      if vim.fn.executable("info") == 1 and #vim.api.nvim_list_uis() > 0 then
        vim.cmd("new")
        vim.fn.jobstart({ "info", "-f", result }, { term = true })
        vim.cmd("startinsert")
      else
        vim.ui.open(result)
      end
    end
    M.stack_job_done(entry, opts, result)
  end
  if opts.async then
    utils.notify("Processing Texinfo file " .. vim.fn.fnamemodify(texi, ":t") .. " …")
    proc = texinfo.compile(texi, done)
    entry = M.stack_job(proc, "texinfo", opts)
    return texi:gsub("%.texi$", "") .. ".info", proc
  end
  local result, err = texinfo.compile(texi)
  done(result, err)
  return result
end

--- Process a man file into a PDF with `export.man.pdf_process`
--- (org-man-compile); in the background with `opts.async`.
function M.compile_man_pdf(file, opts)
  opts = opts or {}
  local man = require("org.export.man")
  local entry, proc
  local function done(result, err)
    if not result then
      if not (proc and proc.cancelled) then
        utils.error(err or "PDF file was not produced")
      end
      M.stack_job_done(entry, opts, nil, err)
      return
    end
    utils.notify("PDF file produced. " .. result)
    if opts.open or cfg().open_after_export then
      vim.ui.open(result)
    end
    M.stack_job_done(entry, opts, result)
  end
  if opts.async then
    utils.notify("Processing Groff file " .. vim.fn.fnamemodify(file, ":t") .. " …")
    proc = man.compile(file, done)
    entry = M.stack_job(proc, "man", opts)
    return (file:gsub("%.[^/.]*$", "")) .. ".pdf", proc
  end
  local result, err = man.compile(file)
  done(result, err)
  return result
end
