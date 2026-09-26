-- Formatting, on demand and on save.
--
-- Both paths end at the server's `textDocument/formatting`, which runs `v fmt`
-- over the buffer. The plugin never formats anything by itself, because a second
-- formatter drifts from the first and a project whose format gate disagrees with
-- its editor is worse off than one with no formatter at all.
local config = require('visor.config')

local M = {}

-- serves_formatting reports whether this client said it can format. The server
-- only advertises the provider when it has a compiler that formats, so a client
-- without it is a session where formatting would fail rather than a bug here.
local function serves_formatting(client)
  return client ~= nil and client.server_capabilities.documentFormattingProvider ~= nil
end

-- enabled_for reports whether saving this buffer should format it. The buffer
-- variable wins over the setting, so one file in a project can opt out.
local function enabled_for(bufnr)
  local buffer_value = vim.b[bufnr].visor_format_on_save
  if buffer_value ~= nil then
    return buffer_value
  end
  return config.options.format_on_save
end

-- notify_later says something once the save is out of the way. A message echoed
-- while a command is in flight comes back out of it as an error, and an error
-- in this hook cancels the write, so a warning about a save has to arrive after
-- it rather than during it.
local function notify_later(message, level)
  vim.schedule(function()
    vim.notify(message, level)
  end)
end

-- format_buffer formats one buffer through the visor client and reports whether
-- the server answered and the buffer went through it. The request goes out
-- through the client rather than through vim.lsp.buf.format because the answer
-- has to stay visible: a reply that never arrives leaves the buffer as it was,
-- and a caller that cannot tell that apart from "nothing needed changing" has
-- nothing to say about a save that went through unformatted.
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local visor = require('visor')
  local client = visor.client(bufnr)
  if not client then
    notify_later('visor: no client is attached to this buffer', vim.log.levels.WARN)
    return false
  end
  if not serves_formatting(client) then
    notify_later('visor: this server has no formatting provider', vim.log.levels.WARN)
    return false
  end
  local timeout_ms = config.options.format_timeout_ms
  local params = vim.lsp.util.make_formatting_params({})
  params.textDocument = { uri = vim.uri_from_bufnr(bufnr) }
  local result, err = client:request_sync('textDocument/formatting', params, timeout_ms, bufnr)
  if result == nil then
    -- A cancelled request never applies an edit, so this buffer keeps its own
    -- formatting, and saying so is the difference between a slow server and a
    -- formatter that quietly did nothing.
    notify_later(string.format('visor: no answer to the formatting request in %d ms, so this buffer keeps its own formatting', timeout_ms),
      vim.log.levels.WARN)
    return false
  end
  if err then
    notify_later(string.format('visor: the server refused to format: %s', err), vim.log.levels.WARN)
    return false
  end
  if result.result then
    vim.lsp.util.apply_text_edits(result.result, bufnr, client.offset_encoding)
  end
  return true
end

-- on_save is what the BufWritePre hook calls. Nothing in it may raise: it runs
-- between a save and the file, and an error there cancels the write, leaving
-- the buffer formatted, the file old, and nothing said. A buffer with no client
-- is not a finding either, because most buffers in an editor are not V.
function M.on_save(bufnr)
  local ran = pcall(function()
    if not enabled_for(bufnr) then
      return
    end
    if not require('visor').client(bufnr) then
      return
    end
    if not M.format_buffer(bufnr) then
      notify_later('visor: this save goes through unformatted', vim.log.levels.WARN)
    end
  end)
  if not ran then
    notify_later('visor: formatting failed, so this save goes through as it stands', vim.log.levels.WARN)
  end
end

return M
