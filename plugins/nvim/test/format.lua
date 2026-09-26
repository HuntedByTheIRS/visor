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

-- save writes the buffer and keeps what the editor said about it. The
-- diagnostics reply the server sends arrives as a message, and a message
-- delivered while a Lua chunk runs :commands comes back out of vim.cmd as an
-- error, so the noise is caught here rather than at the assert: a write that
-- really failed is the thing worth seeing.
local function save()
  vim.v.errmsg = ''
  local wrote = pcall(vim.cmd, 'silent write')
  return wrote, vim.v.errmsg
end

-- The plugin tells the person what it did through vim.notify, and :silent
-- swallows an echo, so the test collects the notices rather than reading
-- :messages. This observes the message; it does not stand in for the server.
local notices = {}
local real_notify = vim.notify
vim.notify = function(message, level, opts)
  notices[#notices + 1] = tostring(message)
  return real_notify(message, level, opts)
end

local function said(text)
  for _, notice in ipairs(notices) do
    if notice:find(text, 1, true) then
      return true
    end
  end
  return false
end

-- Deferred messages arrive on the next turn of the event loop, which is what
-- keeps them out of the save's way, so a check that reads them runs the loop
-- first.
local function settle()
  vim.wait(100, function()
    return false
  end, 10)
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
local wrote, errmsg = save()
check('a save with format on save on rewrites the buffer',
  table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(formatted, '\n'))

-- A failure here has to say what landed on disk and which file was read: the
-- buffer being formatted and the file not is the shape this check exists to
-- catch, and a bare FAIL leaves the reader guessing which half went wrong.
local expected = table.concat(formatted, '\n')
local on_disk = table.concat(vim.fn.readfile(file), '\n')
-- A file that is wrong and then right a moment later is a write that landed
-- after the command returned, which is a different finding from a file that
-- never changes, and the difference decides where the fix goes.
local settled = on_disk == expected
if not settled then
  settled = vim.wait(1000, function()
    return table.concat(vim.fn.readfile(file), '\n') == expected
  end, 10)
end
check('the saved file holds the formatted text',
  on_disk == expected,
  string.format('%s holds %q, the buffer is %s, the write reported %s with %q, correct later: %s',
    file, on_disk, vim.api.nvim_buf_get_name(bufnr), wrote, errmsg, settled))

-- A save of a buffer that is already formatted needs no edit, and that must not
-- be read as a server that went quiet.
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, formatted)
notices = {}
save()
settle()
check('a save of a formatted buffer reports nothing', not said('unformatted'),
  table.concat(notices, ' | '))

-- A server that never answers leaves the buffer as it was, and the save says so
-- rather than passing the file off as formatted. One millisecond of patience is
-- how that path is reached without a slow server behind it.
visor.setup({ format_on_save = true, format_timeout_ms = 1 })
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, unformatted)
notices = {}
save()
settle()
check('a save the server never answers for is reported', said('goes through unformatted'),
  table.concat(notices, ' | '))
check('the buffer the server never answered for is left alone',
  table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    == table.concat(unformatted, '\n'))
-- Formatting that did not happen is a message, not a cancelled save: the file
-- has to hold what the buffer holds even on the path where nothing formatted.
check('the save the server never answered for still lands',
  table.concat(vim.fn.readfile(file), '\n') == table.concat(unformatted, '\n'))
visor.setup({ format_on_save = true })

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
