---@mod org.links.schemes The built-in link types

--- The link types org.nvim knows (`org.links.URL_SCHEMES`), name -> true.
local URL_SCHEMES = {
  http = true,
  https = true,
  ftp = true,
  mailto = true,
  news = true,
  doi = true,
  file = true,
  id = true,
  shell = true,
  elisp = true,
  help = true,
  man = true,
  attachment = true,
  info = true,
  irc = true,
  docview = true,
  bibtex = true,
  ["file+sys"] = true,
  ["file+emacs"] = true,
}

return URL_SCHEMES
