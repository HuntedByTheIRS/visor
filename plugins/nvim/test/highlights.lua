-- Code highlighting, in a real editor against a real server.
--
-- The script opens a V buffer, waits for the client, and asks Neovim what it
-- thinks each position is. That is the whole point of the lane: the server's
-- answer arriving in a buffer as highlight is a different claim from the server
-- producing tokens, and only an editor can settle it.
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

-- The buffer the checks read from. Every line is there for a token that has to
-- be checked, and the positions are spelled out in the assertions below.
local source = {
  'module main',
  '',
  '// A comment about the thing.',
  '',
  'struct Thing {',
  '\tname string',
  '}',
  '',
  'const answer = 42',
  '',
  'fn greet() string {',
  "\treturn 'hi'",
  '}',
}

local function write_project()
  local dir = realpath(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ "Module {\n\tname: 'app'\n}" }, dir .. '/v.mod')
  vim.fn.writefile(source, dir .. '/app.v')
  return dir
end

-- token_at asks the editor what it has at a position, or nil when it has
-- nothing there.
local function token_at(bufnr, row, col)
  local tokens = vim.lsp.semantic_tokens.get_at_pos(bufnr, row, col)
  if not tokens or #tokens == 0 then
    return nil
  end
  return tokens[1]
end

local function type_at(bufnr, row, col)
  local token = token_at(bufnr, row, col)
  return token and token.type or 'nothing'
end

-- check_type compares the editor's answer at a position with the type the walk
-- should have produced for it.
local function check_type(label, bufnr, row, col, want)
  local got = type_at(bufnr, row, col)
  check(label, got == want, string.format('%s, wanted %s', got, want))
end

vim.cmd('runtime! plugin/visor.lua')
local visor = require('visor')

local project = write_project()
vim.cmd.edit(project .. '/app.v')
local bufnr = vim.api.nvim_get_current_buf()
vim.bo[bufnr].filetype = 'v'

wait_for('the buffer gets a client', function()
  local client = visor.client(bufnr)
  return client ~= nil and client.initialized == true
end)

local client = visor.client(bufnr)
if not client then
  io.write(string.format('\n%d checks, %d failed\n', checks, failures))
  vim.cmd('cquit 1')
end

check('the server advertised a token provider',
  client.server_capabilities.semanticTokensProvider ~= nil,
  vim.inspect(client.server_capabilities.semanticTokensProvider))

-- The lane is opt-out, not opt-in: a client that can show tokens gets them
-- without asking, so this is what a plain :edit gets.
check('the client is highlighting the buffer',
  vim.lsp.semantic_tokens.get_at_pos(bufnr, 0, 0) ~= nil
  or vim.lsp.semantic_tokens.is_enabled({ bufnr = bufnr }),
  'tokens were not enabled for the buffer')

vim.lsp.semantic_tokens.force_refresh(bufnr)
wait_for('tokens arrive from the server', function()
  return token_at(bufnr, 0, 0) ~= nil
end)

check_type('the module keyword is a keyword', bufnr, 0, 0, 'keyword')
check_type('the module name is a namespace', bufnr, 0, 7, 'namespace')
check_type('a comment is a comment', bufnr, 2, 4, 'comment')
check_type('the struct keyword is a keyword', bufnr, 4, 0, 'keyword')
check_type('the struct name is a struct', bufnr, 4, 7, 'struct')
check_type('a field is a property', bufnr, 5, 1, 'property')
check_type('the field type is a type', bufnr, 5, 6, 'type')
check_type('a const name is a variable', bufnr, 8, 6, 'variable')
check_type('a number literal is a number', bufnr, 8, 15, 'number')
check_type('a function name is a function', bufnr, 10, 3, 'function')
check_type('a string literal is a string', bufnr, 11, 8, 'string')

local constant = token_at(bufnr, 8, 6)
check('a const carries the read only modifier',
  constant ~= nil and constant.modifiers.readonly == true,
  constant and vim.inspect(constant.modifiers) or 'no token')

local declaration = token_at(bufnr, 10, 3)
check('a declared name carries the declaration modifier',
  declaration ~= nil and declaration.modifiers.declaration == true,
  declaration and vim.inspect(declaration.modifiers) or 'no token')

-- The tokens arriving is the server's half. An extmark in the buffer is the
-- editor's: it is what a screen ends up showing.
local namespace = vim.api.nvim_create_namespace('nvim.lsp.semantic_tokens:' .. client.id)
local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, {})
check('the editor turned the tokens into highlights', #marks > 0,
  string.format('%d extmark(s)', #marks))

-- A position inside a token reads as that token; a blank line has nothing.
local literal = token_at(bufnr, 11, 10)
check('a whole literal is one token, quotes included',
  literal ~= nil and literal.type == 'string' and literal.start_col == 8 and literal.end_col == 12,
  literal and vim.inspect(literal) or 'no token')
check_type('an empty line has nothing to colour', bufnr, 1, 0, 'nothing')

visor.stop()

io.write(string.format('\n%d checks, %d failed\n', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
end
vim.cmd('qall!')
