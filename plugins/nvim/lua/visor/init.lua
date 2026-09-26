-- visor, the Neovim side.
--
-- The plugin owns three things: finding the server, attaching a client to a V
-- buffer, and handing the buffer to the server when the user asks. Everything
-- else the server does arrives through the client Neovim already has.
local config = require('visor.config')

local M = {}

-- warned_once keeps a missing executable from repeating itself on every buffer.
local warned_once = false

local function notify(message, level)
  vim.notify('visor: ' .. message, level or vim.log.levels.INFO)
end

-- find_server returns the command to run, or nil when there is none. Precedence
-- is the caller's setting, then $VISOR_BIN, then PATH.
function M.find_server()
  if config.options.cmd then
    return config.options.cmd
  end
  local from_env = vim.env.VISOR_BIN
  if from_env and from_env ~= '' then
    return from_env
  end
  local on_path = vim.fn.exepath('visor')
  if on_path ~= '' then
    return on_path
  end
  return nil
end

-- as_argv spells a command the way the client wants it: a list, so an argv list
-- passes through unchanged and a lone path becomes a one-element list.
function M.as_argv(command)
  if type(command) == 'table' then
    return command
  end
  return { command }
end

-- root_dir is the project a buffer belongs to. Without a marker the buffer's own
-- directory is the root, which keeps a stray file open on its own instead of
-- pulling it into whatever project the editor was launched from.
function M.root_dir(bufnr)
  local root = vim.fs.root(bufnr, config.options.root_markers)
  if root then
    return root
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    return vim.fs.dirname(name)
  end
  return vim.fn.getcwd()
end

-- client_list returns every visor client, including one whose initialize reply
-- has not arrived yet. Neovim hides those from get_clients() by default, and a
-- client mid-handshake is still a process this plugin owns: whether a buffer
-- needs starting, and what :VisorInfo should say, both depend on seeing it.
-- The private filter key is passed inside a pcall because an older client does
-- not know it, and the plain call still answers correctly there.
local function client_list()
  local ok, clients = pcall(vim.lsp.get_clients, { name = 'visor', _uninitialized = true })
  if ok then
    return clients
  end
  return vim.lsp.get_clients({ name = 'visor' })
end

-- clients lists the visor clients in this session.
function M.clients()
  return client_list()
end

-- client returns the visor client attached to a buffer, or nil.
function M.client(bufnr)
  for _, client in ipairs(client_list()) do
    if vim.lsp.buf_is_attached(bufnr, client.id) then
      return client
    end
  end
  return nil
end

local function on_attach(client, bufnr)
  vim.b[bufnr].visor_client = client.id
  -- The token lane is the server's to announce. Asking a server that never
  -- advertised tokens would leave the client polling for an answer it cannot
  -- get, so the negotiated capability decides.
  if config.options.semantic_tokens and client.server_capabilities.semanticTokensProvider then
    vim.lsp.semantic_tokens.start(bufnr, client.id)
  end
end

-- start attaches a client to a buffer. It returns the client, or nil when the
-- buffer is not V, a client is already attached, or there is no server to run.
function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if vim.bo[bufnr].filetype ~= 'v' then
    return nil
  end
  local attached = M.client(bufnr)
  if attached then
    return attached
  end
  local command = M.find_server()
  if not command then
    if not warned_once then
      warned_once = true
      notify('no server executable. Put visor on PATH, set $VISOR_BIN, or pass cmd to setup().', vim.log.levels.ERROR)
    end
    return nil
  end
  local client_id = vim.lsp.start({
    name = 'visor',
    cmd = M.as_argv(command),
    root_dir = M.root_dir(bufnr),
    on_attach = on_attach,
  }, { bufnr = bufnr })
  if not client_id then
    notify('the server did not answer initialize; run :VisorInfo and check the log', vim.log.levels.ERROR)
    return nil
  end
  return vim.lsp.get_client_by_id(client_id)
end

-- start_loaded starts a client for every V buffer already open. The filetype
-- event covers buffers opened later; this covers the ones open before the
-- plugin loaded.
function M.start_loaded()
  local started = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'v' then
      if M.start(bufnr) then
        started = started + 1
      end
    end
  end
  return started
end

-- stop ends every visor client. The buffers stay open; the server is what goes.
function M.stop()
  local stopped = 0
  for _, client in ipairs(M.clients()) do
    client:stop()
    stopped = stopped + 1
  end
  return stopped
end

-- info is what :VisorInfo prints, one line per fact. It is the answer to "is
-- this plugged in", which is otherwise guesswork from an editor's log.
function M.info()
  local lines = {}
  local command = M.find_server()
  if command then
    lines[#lines + 1] = 'executable: ' .. table.concat(M.as_argv(command), ' ')
  else
    lines[#lines + 1] = 'executable: not found'
  end
  local clients = M.clients()
  if #clients == 0 then
    lines[#lines + 1] = 'clients: none'
    return lines
  end
  lines[#lines + 1] = 'format on save: ' .. (config.options.format_on_save and 'on' or 'off')
  for _, client in ipairs(clients) do
    local reported = client.server_info or {}
    -- A client whose initialize reply is still in flight has no server info
    -- yet, and saying so beats printing an empty name.
    local version = reported.version or (client.initialized and 'unknown version' or 'initializing')
    local attached = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.lsp.buf_is_attached(bufnr, client.id) then
        attached[#attached + 1] = vim.api.nvim_buf_get_name(bufnr)
      end
    end
    lines[#lines + 1] = string.format('client %d: %s %s, root %s, %d buffer(s)', client.id, reported.name or 'visor', version, client.config.root_dir or 'none', #attached)
  end
  return lines
end

-- setup stores the caller's settings and wires the filetype hook. Loading the
-- plugin file is what defines the commands; this is what turns the automatic
-- start on or off.
function M.setup(opts)
  local options = config.setup(opts)
  if options.autostart then
    M.start_loaded()
  end
  return options
end

return M
