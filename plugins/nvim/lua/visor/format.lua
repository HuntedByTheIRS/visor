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

-- format_buffer formats one buffer through the visor client. It blocks until the
-- edit lands, because a caller that asked for formatting wants the buffer
-- formatted when it returns, not at some later point.
function M.format_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local visor = require('visor')
  local client = visor.client(bufnr)
  if not client then
    vim.notify('visor: no client is attached to this buffer', vim.log.levels.WARN)
    return false
  end
  if not serves_formatting(client) then
    vim.notify('visor: this server has no formatting provider', vim.log.levels.WARN)
    return false
  end
  vim.lsp.buf.format({
    bufnr = bufnr,
    async = false,
    filter = function(candidate)
      return candidate.id == client.id
    end,
  })
  return true
end

-- on_save is what the BufWritePre hook calls. A buffer with no client is not a
-- finding: most buffers in an editor are not V.
function M.on_save(bufnr)
  if not enabled_for(bufnr) then
    return
  end
  if not require('visor').client(bufnr) then
    return
  end
  M.format_buffer(bufnr)
end

return M
