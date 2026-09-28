module lsp

import json2
import os

// The outline lane needs nothing but the buffer, so these tests drive it
// through the server with a folder indexed and a buffer open, and then without
// either: what the answer must never depend on is the file on disk.

const outline_client = '{"textDocument":{"documentSymbol":{"hierarchicalDocumentSymbolSupport":true}}}'

// A buffer with a type, a method on it and an entry function: an outline with
// two levels and one method that belongs to a type rather than to the file.
const outline_buffer = 'module main

struct Point {
	x int
	y int
}

fn (p Point) scaled(k int) Point {
	return Point{ p.x * k, p.y * k }
}

fn main() {
	base := Point{ 2, 3 }
	println(base)
}
'

// outline_session indexes a folder and opens a buffer in it, which is what a
// client has while a person is typing.
fn outline_session(dir string, file_name string, text string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	mut folder := map[string]json2.Any{}
	folder['uri'] = json2.Any('file://${dir}')
	folder['name'] = json2.Any('scratch')
	s.serve_message(parse_message(initialize_with(outline_client, [json2.Any(folder)])))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_document(mut s, 'file://${dir}/${file_name}', text)
	return sink, s
}

// initialize_with builds the request that opens a session around the folders the
// index is built from. The capabilities arrive as JSON because that is what the
// client sends.
fn initialize_with(client_capabilities string, folders []json2.Any) string {
	return '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
		client_capabilities + ',"workspaceFolders":' + json2.encode(json2.Any(folders)) + '}}'
}

// open_document sends the didOpen a client sends before it asks about a buffer.
fn open_document(mut s Server, uri string, text string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['languageId'] = json2.Any('v')
	document['version'] = json2.Any(1)
	document['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	mut message := map[string]json2.Any{}
	message['jsonrpc'] = json2.Any(jsonrpc_version)
	message['method'] = json2.Any('textDocument/didOpen')
	message['params'] = json2.Any(params)
	s.serve_message(parse_message(json2.encode(json2.Any(message))))
}

// ask_for_symbols sends the request the lane answers.
fn ask_for_symbols(mut s Server, uri string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,"method":"textDocument/documentSymbol",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// outline_entries is the answer flattened one level, with the members of a type
// indented under it: what an editor's outline panel draws.
fn outline_entries(reply Message) []string {
	items := as_array(reply.result) or { panic('the symbol result is not an array') }
	mut lines := []string{}
	for item in items {
		entry := as_object(item) or { panic('a symbol is not an object') }
		lines << entry_name(entry)
		children := as_array(entry['children'] or { json2.Any([]json2.Any{}) }) or {
			[]json2.Any{}
		}
		for child in children {
			mut nested := as_object(child) or { panic('a child symbol is not an object') }
			lines << '  ${nested['name'] or { json2.Any('') }.str()}'
		}
	}
	return lines
}

// entry_name reads a symbol's name.
fn entry_name(entry map[string]json2.Any) string {
	return (entry['name'] or { json2.Any('') }).str()
}

// symbol_entries_of finds the top-level entries of a reply by name.
fn symbol_entries_of(reply Message) []map[string]json2.Any {
	items := as_array(reply.result) or { panic('the symbol result is not an array') }
	mut entries := []map[string]json2.Any{cap: items.len}
	for item in items {
		entries << as_object(item) or { panic('a symbol is not an object') }
	}
	return entries
}

// entry_at finds one entry by name, at the top level or under a type.
fn entry_at(reply Message, name string) ?map[string]json2.Any {
	for entry in symbol_entries_of(reply) {
		if entry_name(entry) == name {
			return entry
		}
		children := as_array(entry['children'] or { json2.Any([]json2.Any{}) }) or {
			[]json2.Any{}
		}
		for child in children {
			nested := as_object(child) or { continue }
			if entry_name(nested) == name {
				return nested
			}
		}
	}
	return none
}

// range_start_of reads the position a range begins at.
fn range_start_of(entry map[string]json2.Any, key string) Position {
	value := entry[key] or { panic('the symbol has no ${key}') }
	range_ := as_object(value) or { panic('${key} is not an object') }
	return parse_position(range_['start'] or { panic('${key} has no start') }) or {
		panic('${key} has no start')
	}
}

// position_in is where a needle sits in a text, looked up rather than written
// down, so editing the fixture cannot move the expectation.
fn position_in(text string, needle string) Position {
	lines := text.split_into_lines()
	for i, line in lines {
		if line.contains(needle) {
			return Position{
				line:      i
				character: line.index(needle) or { 0 }
			}
		}
	}
	panic('the buffer has no line holding ${needle}')
}

fn test_the_outline_describes_the_buffer() {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-document-symbols-test-buffer')
	os.mkdir_all(dir) or { panic(err.msg()) }
	mut sink, mut s := outline_session(dir, 'main.v', outline_buffer)
	ask_for_symbols(mut s, 'file://${dir}/main.v')
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	// the module clause, then the type with its members, then the entry
	// function, which is named after the module it is in
	assert outline_entries(reply) == ['main', 'Point', '  x', '  y', '  scaled', 'main']
	// the buffer was never written, so the answer cannot have come from disk
	assert !os.exists(os.join_path(dir, 'main.v'))
}

fn test_a_type_carries_its_members_with_their_own_ranges() {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-document-symbols-test-ranges')
	os.mkdir_all(dir) or { panic(err.msg()) }
	mut sink, mut s := outline_session(dir, 'main.v', outline_buffer)
	ask_for_symbols(mut s, 'file://${dir}/main.v')
	reply := sink.last_message()
	point := entry_at(reply, 'Point') or { panic('the outline has no Point') }
	// a type's own range covers its body, and its selection range is the name
	range_start := range_start_of(point, 'range')
	selection_start := range_start_of(point, 'selectionRange')
	assert range_start == position_in(outline_buffer, 'struct Point')
	assert selection_start == Position{
		line:      range_start.line
		character: range_start.character + 'struct '.len
	}
	// a member is reached through its type, and the name it selects is shorter
	// than the declaration it covers
	scaled := entry_at(reply, 'scaled') or { panic('the outline has no scaled') }
	member_range := range_start_of(scaled, 'range')
	member_selection := range_start_of(scaled, 'selectionRange')
	assert member_range.line == member_selection.line
	assert member_selection.character == member_range.character + 'fn (p Point) '.len
}

fn test_a_document_that_is_not_open_is_refused() {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-document-symbols-test-closed')
	os.mkdir_all(dir) or { panic(err.msg()) }
	mut sink, mut s := outline_session(dir, 'main.v', outline_buffer)
	ask_for_symbols(mut s, 'file://${dir}/never_opened.v')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('is not open in this session')
}

// The outline is a fact about one buffer, so a file in no indexed folder is
// answered rather than refused. Every other engine-backed lane refuses that
// buffer, which is what makes this worth pinning down.
fn test_a_buffer_outside_every_folder_is_still_outlined() {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-document-symbols-test-outside')
	outside := os.join_path(os.temp_dir(), 'visor-lsp-document-symbols-outside-code')
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.mkdir_all(outside) or { panic(err.msg()) }
	mut sink, mut s := outline_session(dir, 'main.v', outline_buffer)
	open_document(mut s, 'file://${outside}/loose.v', outline_buffer)
	ask_for_symbols(mut s, 'file://${outside}/loose.v')
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	assert outline_entries(reply) == ['main', 'Point', '  x', '  y', '  scaled', 'main']
}
