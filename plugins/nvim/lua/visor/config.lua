-- The plugin's settings, and the one place they are merged.
--
-- Nothing here reads a global variable. A user who wants to configure the
-- plugin calls setup() once, and a user who does not gets these values.
local M = {}

M.defaults = {
  -- cmd is the server executable, as a path or as an argv list. Leaving it nil
  -- hands the search to visor.find_server(), which checks $VISOR_BIN and then
  -- PATH. That search is what lets a plugin checkout find a server built from
  -- the same tree without a path in anyone's config.
  cmd = nil,

  -- autostart starts the server for every V buffer the filetype event reaches.
  -- Turn it off to start clients by hand with :VisorStart.
  autostart = true,

  -- format_on_save writes the file through `v fmt` on every save. Off by
  -- default: it rewrites the whole buffer, and a project whose own format gate
  -- disagrees has a reason to run :VisorFormat by hand instead.
  format_on_save = false,

  -- format_timeout_ms is how long a formatting request may take. Neovim's own
  -- default is one second, which is a keystroke's worth of patience: on a cold
  -- machine `v fmt` over a large file can take longer, and a save that skips
  -- formatting is worse than one that waits.
  format_timeout_ms = 10000,

  -- semantic_tokens asks for highlighting tokens on attach, when the server
  -- said in initialize that it has them. Neovim starts the lane for such a
  -- client anyway (see the README), so this is the plugin saying so itself:
  -- false stops that, it does not turn the highlighting off.
  semantic_tokens = true,

  -- root_markers decide the project root for a buffer, nearest one first. A
  -- server holds one root per client, so two projects stay two clients.
  root_markers = { 'v.mod', '.git' },
}

M.options = vim.deepcopy(M.defaults)

-- setup merges the caller's table over the defaults and returns the result.
-- Repeating it replaces the settings rather than layering a second time.
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
