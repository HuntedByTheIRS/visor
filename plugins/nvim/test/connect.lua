-- An editor, the plugin's own files, and a real server.
--
-- The script loads plugin/visor.lua the way an editor does, opens a V buffer in
-- a small project, and checks what came up. Everything it asserts is a fact
-- about a session that happened, not about what the plugin intends.
--
-- run.sh sets $VISOR_BIN and puts plugins/nvim on the runtimepath.

local checks = 0
local failures = 0

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    io.write(string.format('ok   %s\n', label))
    return
  end
  failures = failures + 1
  io.write(string.format('FAIL %s%s\n', label, detail and (': ' .. detail) or ''))
end

-- wait_for pumps the event loop until the predicate holds. initialize is a
-- round trip, so a working session is briefly a session with an unfinished
-- client, and a script that does not wait would call that a failure.
local function wait_for(label, predicate, timeout)
  local limit = timeout or 5000
  local ok = vim.wait(limit, predicate, 10)
  check(label, ok, string.format('gave up after %d ms', limit))
  return ok
end

local function realpath(path)
  return vim.uv.fs_realpath(path) or path
end

-- write_project builds a directory with a v.mod in it, which is what the root
-- search looks for.
local function write_project()
  local dir = realpath(vim.fn.tempname())
  vim.fn.mkdir(dir .. '/greeter', 'p')
  vim.fn.writefile({ "Module {\n\tname: 'app'\n}" }, dir .. '/v.mod')
  vim.fn.writefile({
    'module main',
    '',
    'import greeter',
    '',
    'fn main() {',
    '\tprintln(greeter.greeting())',
    '}',
  }, dir .. '/app.v')
  vim.fn.writefile({
    'module greeter',
    '',
    'pub fn greeting() string {',
    "\treturn 'hello'",
    '}',
  }, dir .. '/greeter/greeter.v')
  return dir
end

check('nvim detects .v as the V filetype on its own', vim.filetype.match({ filename = 'app.v' }) == 'v')

-- load the plugin the way an editor does
vim.cmd('runtime! plugin/visor.lua')

check('the plugin installs :VisorInfo', vim.fn.exists(':VisorInfo') == 2,
  string.format('exists() answered %d', vim.fn.exists(':VisorInfo')))

local visor = require('visor')

check('loading the plugin file starts no client', #visor.clients() == 0,
  string.format('%d client(s) came up', #visor.clients()))

local bin = vim.env.VISOR_BIN
check('the plugin finds the server', visor.find_server() ~= nil, 'find_server() answered nil')
check('the found server is the one run.sh named', visor.find_server() == bin,
  string.format('%s, wanted %s', tostring(visor.find_server()), tostring(bin)))

local project = write_project()
vim.cmd.edit(project .. '/app.v')
local bufnr = vim.api.nvim_get_current_buf()
vim.bo[bufnr].filetype = 'v' -- the FileType event is what starts the server

wait_for('the filetype event brought a client all the way through initialize', function()
  local client = visor.client(bufnr)
  return client ~= nil and client.initialized == true
end)

local clients = visor.clients()
check('one client serves the buffer', #clients == 1, string.format('%d client(s)', #clients))

local client = visor.client(bufnr)
if not client then
  io.write(string.format('\n%d checks, %d failed\n', checks, failures))
  vim.cmd('cquit 1')
end

check('the client is named visor', client.name == 'visor', client.name)
check('the client attached to the buffer', vim.lsp.buf_is_attached(bufnr, client.id))
check('on_attach ran for the buffer', vim.b[bufnr].visor_client == client.id,
  tostring(vim.b[bufnr].visor_client))

local reported = client.server_info or {}
check('initialize answered with the server name', reported.name == 'visor',
  tostring(reported.name))
check('initialize answered with a version',
  type(reported.version) == 'string' and reported.version:match('^%d+%.%d+%.%d+') ~= nil,
  tostring(reported.version))
check('the server capabilities arrived', client.server_capabilities.textDocumentSync ~= nil)

check('the root search landed on the project', realpath(client.config.root_dir) == project,
  string.format('%s, wanted %s', tostring(client.config.root_dir), project))

-- A V file with no marker above it belongs to its own directory.
local loose = realpath(vim.fn.tempname())
vim.fn.mkdir(loose, 'p')
vim.fn.writefile({ 'module main' }, loose .. '/loose.v')
vim.cmd.edit(loose .. '/loose.v')
local loose_buf = vim.api.nvim_get_current_buf()
vim.bo[loose_buf].filetype = 'v'
wait_for('a second project gets its own client', function()
  local second = visor.client(loose_buf)
  return second ~= nil and second.initialized == true
end)
local loose_client = visor.client(loose_buf)
check('a buffer with no marker gets its own directory as the root',
  loose_client ~= nil and realpath(loose_client.config.root_dir) == loose,
  loose_client and tostring(loose_client.config.root_dir) or 'no client')
check('the first client still serves the first project', visor.client(bufnr) ~= nil)
check('two projects are two clients', #visor.clients() == 2,
  string.format('%d client(s)', #visor.clients()))

local info = table.concat(visor.info(), '\n')
check(':VisorInfo names the executable', info:find('executable: ' .. bin, 1, true) ~= nil, info)
check(':VisorInfo reports the first client root', info:find('root ' .. project, 1, true) ~= nil, info)

local printed = vim.api.nvim_exec2('VisorInfo', { output = true }).output
check('the :VisorInfo command prints the same lines',
  printed:find('executable: ', 1, true) ~= nil, printed)

-- Stopping runs the shutdown handshake, so the client list is briefly non-empty
-- afterwards. The count is what was asked to stop; the wait is what shows it
-- went.
local stopped = visor.stop()
wait_for('stop ends every client', function()
  return #visor.clients() == 0
end)
check('the client count fell to zero', #visor.clients() == 0,
  string.format('stopped %d, %d still running', stopped, #visor.clients()))

io.write(string.format('\n%d checks, %d failed\n', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
end
vim.cmd('qall!')
