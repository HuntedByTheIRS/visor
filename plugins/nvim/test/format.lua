-- Formatting, on demand and on save.
--
-- The editor is real and so is the server behind it, so what this checks is the
-- whole chain: the buffer goes over the wire, `v fmt` rewrites it, and the edit
-- comes back into the buffer and onto disk.
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

local function wait_for(label, predicate, timeout)
  local limit = timeout or 5000
  local ok = vim.wait(limit, predicate, 10)
  check(label, ok, string.format('gave up after %d ms', limit))
  return ok
end

local function realpath(path)
  return vim.uv.fs_realpath(path) or path
end

-- The spelling `v fmt` writes for this buffer: tabs, single quotes, a space
-- before the brace.
local unformatted = { 'fn   main(){', 'println("x")', '}' }
local formatted = { 'fn main() {', "\tprintln('x')", '}' }

local function write_project()
  local dir = realpath(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ "Module {\n\tname: 'app'\n}" }, dir .. '/v.mod')
  vim.fn.writefile(unformatted, dir .. '/main.v')
  return dir
end

vim.cmd('runtime! plugin/visor.lua')

local visor = require('visor')
local format = require('visor.format')

-- The server answers the client's pull-diagnostics request with an error naming
-- the diagnostics lane, which is deliberate, and Neovim turns that into a
-- message. A message that arrives while a Lua chunk is running :commands comes
-- back out of vim.cmd as an error, so commands go through pcall here and the
-- state after each one is what the test asserts.
local function run(command)
  return pcall(vim.cmd, command)
end

local project = write_project()
local file = project .. '/main.v'
vim.cmd.edit(file)
local bufnr = vim.api.nvim_get_current_buf()
vim.bo[bufnr].filetype = 'v'

wait_for('the server answers initialize for the buffer', function()
  local client = visor.client(bufnr)
  return client ~= nil and client.initialized == true
end)
vim.wait(300)

local client = visor.client(bufnr)
check('the server advertises formatting to this client',
  client ~= nil and client.server_capabilities.documentFormattingProvider ~= nil)

check('the buffer starts out unformatted',
  table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(unformatted, '\n'))

check(':VisorFormat exists', vim.fn.exists(':VisorFormat') == 2)

-- On demand, through the command the user would run.
local ran = run('VisorFormat')
check('the :VisorFormat command runs', ran, 'vim.cmd refused it')
wait_for('the buffer holds what v fmt wrote', function()
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(formatted, '\n')
end)

check('the file on disk is untouched until the buffer is saved',
  table.concat(vim.fn.readfile(file), '\n') == table.concat(unformatted, '\n'))

-- Saving with the setting off leaves the file alone.
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, unformatted)
run('silent write')
check('a save with format on save off leaves the buffer as it was',
  table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(unformatted, '\n'))

-- Saving with the setting on formats the buffer and the file together.
visor.setup({ format_on_save = true })
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, unformatted)
run('silent write')
check('a save with format on save on rewrites the buffer',
  table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(formatted, '\n'))
-- A failure here has to say what landed on disk and which file was read: the
-- buffer being formatted and the file not is the shape this check exists to
-- catch, and a bare FAIL leaves the reader guessing which half went wrong.
local on_disk = table.concat(vim.fn.readfile(file), '\n')
check('the saved file holds the formatted text',
  on_disk == table.concat(formatted, '\n'),
  string.format('%s holds %q, and the buffer is %s', file, on_disk,
    vim.api.nvim_buf_get_name(bufnr)))

-- The buffer variable wins over the setting for one buffer.
vim.b[bufnr].visor_format_on_save = false
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, unformatted)
run('silent write')
check('a buffer can turn formatting off for itself',
  table.concat(vim.fn.readfile(file), '\n') == table.concat(unformatted, '\n'))

-- A buffer with no client is skipped rather than reported.
local loose = realpath(vim.fn.tempname())
vim.fn.mkdir(loose, 'p')
vim.fn.writefile(unformatted, loose .. '/notes.txt')
vim.cmd.edit(loose .. '/notes.txt')
run('silent write')
check('a buffer with no server is left alone',
  table.concat(vim.fn.readfile(loose .. '/notes.txt'), '\n') == table.concat(unformatted, '\n'))

check(':VisorInfo reports the format setting',
  vim.api.nvim_exec2('VisorInfo', { output = true }).output:find('format on save: on', 1, true) ~= nil)

io.write(string.format('\n%d checks, %d failed\n', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
end
vim.cmd('qall!')
