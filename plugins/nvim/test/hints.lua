-- Inlay hints, in a real editor against a real server.
--
-- The script opens a V buffer whose values are written without their names: a
-- positional literal, a call whose arguments have none either, and a `:=` with
-- no type on it. Then it asks the editor what it drew beside them, because a
-- label the server sent and a label on the screen are two different claims and
-- only an editor can settle the second.
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

-- The buffer the checks read from. Every line is there for a hint that has to
-- be checked, and the positions are looked up in this text rather than written
-- down, so an edit here does not silently move an expectation.
--
-- It is also short on purpose. Neovim asks for hints over the lines it has
-- drawn, and a headless editor draws a screen's worth, so a file that runs past
-- that gets no hints on the lines below it and this script would fail on a
-- fixture that is merely long.
local source = {
  'module main',
  '',
  'import os',
  'struct Point {',
  '\tx int',
  '\ty int',
  '}',
  '',
  '@[inline]',
  'fn scale(p Point, factor int) Point {',
  '\treturn Point{ p.x * factor, p.y * factor }',
  '}',
  '',
  'fn label(n int) string {',
  "\treturn 'n'",
  '}',
  '',
  'fn main() {',
  '\tbase := Point{ 2, 3 }',
  '\tscaled := scale(base, 4)',
  '\tdefer println(scaled)',
  '\tprintln(label(7))',
  '\tcontent := os.read_file("v.mod") or { "" }',
  '}',
}

local function write_project()
  local dir = realpath(vim.fn.tempname())
  vim.fn.mkdir(dir, 'p')
  vim.fn.writefile({ "Module {\n\tname: 'app'\n}\n" }, dir .. '/v.mod')
  vim.fn.writefile(source, dir .. '/app.v')
  return dir
end

-- drawn_hints reads the labels the editor put in the buffer, with the position
-- each one lands on, taken from the virtual text a screen would show.
--
-- Neovim keeps the marks for this lane in namespaces of its own naming, so they
-- are found by the highlight group on the text instead: anything the editor
-- drew as an inlay hint carries `LspInlayHint`.
local function drawn_hints(bufnr)
  local hints = {}
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    local label = {}
    local is_hint = false
    for _, chunk in ipairs(details.virt_text or {}) do
      if chunk[2] == 'LspInlayHint' then
        is_hint = true
      end
      label[#label + 1] = chunk[1]
    end
    if is_hint then
      -- The padding a hint asks for arrives as its own chunk, in front of the
      -- label or behind it, so both ends are trimmed before the label is
      -- compared with what the server said.
      local text = table.concat(label):gsub('^%s+', ''):gsub('%s+$', '')
      hints[#hints + 1] = { row = mark[2], col = mark[3], label = text }
    end
  end
  return hints
end

-- line_of finds the first line holding a needle, and column_of the first column
-- of one on a line.
local function line_of(target, needle)
  local lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return i - 1, line
    end
  end
  return -1, nil
end

local function column_of(line, needle)
  return (line:find(needle, 1, true) or 0) - 1
end

-- hint_at finds one hint by its label, optionally on one line: the same label
-- turns up wherever the same field or parameter is named twice.
local function hint_at(hints, label, row)
  for _, hint in ipairs(hints) do
    if hint.label == label and (row == nil or hint.row == row) then
      return hint
    end
  end
  return nil
end

local function labels_of(hints)
  local labels = {}
  for _, hint in ipairs(hints) do
    labels[#labels + 1] = hint.label
  end
  return table.concat(labels, ' ')
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

check('the server advertised a hint provider',
  client.server_capabilities.inlayHintProvider ~= nil,
  vim.inspect(client.server_capabilities.inlayHintProvider))
check('the provider does not ask for a resolve round trip',
  client.server_capabilities.inlayHintProvider
    and client.server_capabilities.inlayHintProvider.resolveProvider ~= true)

-- Neovim keeps hints off until something turns them on, so a plugin that does
-- not ask shows an empty screen with a working server behind it. This reads back
-- what the plugin did on attach; the script never asks for hints itself.
if vim.lsp.inlay_hint.is_enabled then
  check('the plugin turned hints on for the buffer',
    vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }))
end

wait_for('the server answers with hints', function()
  return #vim.lsp.inlay_hint.get({ bufnr = bufnr }) > 0
end)

-- Neovim 0.11 turns that answer into marks when the buffer is drawn, and a
-- headless editor draws when it is asked to. 0.12 draws as the answer lands, so
-- the redraw is a no-op there.
vim.cmd('redraw')

wait_for('the editor draws hints in the buffer', function()
  return #drawn_hints(bufnr) > 0
end)

local hints = drawn_hints(bufnr)
local labels = labels_of(hints)
check('every family reached the screen',
  labels:find('x:', 1, true) ~= nil
    and labels:find(': Point', 1, true) ~= nil
    and labels:find('p:', 1, true) ~= nil
    and labels:find('n:', 1, true) ~= nil
    and labels:find('| inline', 1, true) ~= nil
    and labels:find('defer:', 1, true) ~= nil,
  labels)

-- The standard library is read for the modules a buffer imports, so a call into
-- one of them answers like a call into the next file. The parameter of
-- os.read_file is named `path` in the library this server found.
check('a call into the standard library gets its parameter name',
  hint_at(hints, 'path:') ~= nil, labels)

-- An attribute is written above the declaration it belongs to, so the label
-- restating it belongs at the end of that declaration: after the brace the body
-- opens with, rather than at the end of the line, which is a different place the
-- moment a line holds anything else.
local scale_row, scale_line = line_of(bufnr, 'fn scale(')
local attribute = hint_at(hints, '| inline')
local attribute_column = column_of(scale_line or '', '{') + 1
check('a declaration names the attributes it carries',
  attribute ~= nil and attribute.row == scale_row and attribute.col == attribute_column,
  attribute and string.format('row %d col %d, wanted row %d col %d',
    attribute.row, attribute.col, scale_row, attribute_column)
    or string.format('no attribute hint, %s', labels))

-- A field name belongs on the value it names, which is the `2` of
-- `base := Point{ 2, 3 }`.
local literal_row, literal_line = line_of(bufnr, 'base := Point{')
local field = hint_at(hints, 'x:', literal_row)
local want_column = column_of(literal_line or '', '2')
check('a field name sits on the value it names',
  field ~= nil and field.row == literal_row and field.col == want_column,
  field and string.format('row %d col %d, wanted row %d col %d',
    field.row, field.col, literal_row, want_column) or 'no x: hint')

-- The parameter names come from the declaration in the same buffer, and the
-- call is the line under the literal.
local call_row = line_of(bufnr, 'scaled := scale(')
local parameter = hint_at(hints, 'p:')
check('a parameter name sits on the argument it names',
  parameter ~= nil and parameter.row == call_row,
  parameter and string.format('row %d, wanted row %d', parameter.row, call_row) or 'no p: hint')

-- A call inside another call is the same question one level in.
local nested_row = line_of(bufnr, 'println(label(7))')
local nested = hint_at(hints, 'n:')
check('a nested call gets its own parameter name',
  nested ~= nil and nested.row == nested_row,
  nested and string.format('row %d, wanted row %d', nested.row, nested_row) or 'no n: hint')

-- `defer println(scaled)` runs at the end of the block it is written in, which
-- is the last line above the closing brace. A label on the brace itself lands
-- after the brace, at the far left of the block.
local closing_row = -1
for row = line_of(bufnr, 'defer println(scaled)') + 1, 30 do
  if vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] == '}' then
    closing_row = row
    break
  end
end
local deferred = hint_at(hints, '; defer: println(scaled)')
check('the deferred code is spelled out above the brace it runs at',
  deferred ~= nil and deferred.row == closing_row - 1 and deferred.row > -1,
  deferred and string.format('row %d, wanted row %d', deferred.row, closing_row - 1)
    or string.format('no ; defer: hint, %s', labels))

visor.stop()

io.write(string.format('\n%d checks, %d failed\n', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
end
vim.cmd('qall!')
