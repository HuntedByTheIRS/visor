module lsp

import features
import json2
import os

// The search reads the index, so these tests index a folder of real files and
// ask through the same message path a client uses. The buffer is where the
// difference between the index and the editor shows: what is only typed is not
// found.

const search_client = '{"workspace":{"symbol":{"dynamicRegistration":false}}}'

const search_helper = 'module main

pub fn helper() int {
	return 1
}

pub struct Config {
	pub:
	name string
}
'

const search_typed = 'module main

fn typed_helper() int {
	return 2
}
'

// search_session indexes a folder holding a real file and opens a buffer for a
// file that was never written, which is the pair the lane has to tell apart.
fn search_session(name string) (&BufferSink, &Server, string) {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-workspace-symbols-test-${name}')
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'helper.v'), search_helper) or { panic(err.msg()) }
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	mut folder := map[string]json2.Any{}
	folder['uri'] = json2.Any('file://${dir}')
	folder['name'] = json2.Any('scratch')
	s.serve_message(parse_message(search_initialize([json2.Any(folder)])))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_search_buffer(mut s, 'file://${dir}/main.v', search_typed)
	return sink, s, dir
}

// search_initialize builds the request that opens a session around the folders
// the index is built from.
fn search_initialize(folders []json2.Any) string {
	return '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
		search_client + ',"workspaceFolders":' + json2.encode(json2.Any(folders)) + '}}'
}

// open_search_buffer sends the didOpen a client sends before it asks.
fn open_search_buffer(mut s Server, uri string, text string) {
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

// ask_for_search sends the request the lane answers.
fn ask_for_search(mut s Server, query string) {
	mut params := map[string]json2.Any{}
	params['query'] = json2.Any(query)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,"method":"workspace/symbol",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// search_entries reads a reply into one entry per name.
fn search_entries(reply Message) []map[string]json2.Any {
	items := as_array(reply.result) or { panic('the symbol result is not an array') }
	mut entries := []map[string]json2.Any{cap: items.len}
	for item in items {
		entries << as_object(item) or { panic('a symbol is not an object') }
	}
	return entries
}

// search_names is a reply as plain names, in the order the lane sent them.
fn search_names(reply Message) []string {
	mut names := []string{}
	for entry in search_entries(reply) {
		names << (entry['name'] or { json2.Any('') }).str()
	}
	return names
}

// search_entry finds one answer by name.
fn search_entry(reply Message, name string) ?map[string]json2.Any {
	for entry in search_entries(reply) {
		if (entry['name'] or { json2.Any('') }).str() == name {
			return entry
		}
	}
	return none
}

// location_of reads the file and the position an answer points at.
fn location_of(entry map[string]json2.Any) (string, Position) {
	location := as_object(entry['location'] or { panic('a symbol has no location') }) or {
		panic('a location is not an object')
	}
	uri := (location['uri'] or { panic('a location has no uri') }).str()
	range_ := as_object(location['range'] or { panic('a location has no range') }) or {
		panic('a range is not an object')
	}
	start := parse_position(range_['start'] or { panic('a range has no start') }) or {
		panic('a range has no start')
	}
	return uri, start
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
	panic('the fixture has no line holding ${needle}')
}

fn test_a_search_answers_with_the_declarations_the_index_holds() {
	mut sink, mut s, dir := search_session('answer')
	ask_for_search(mut s, 'helper')
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	// the exact name first, then the name that only contains the query
	assert search_names(reply) == ['helper', 'typed_helper']
	entry := search_entry(reply, 'helper') or { panic('the answer has no helper') }
	assert (entry['kind'] or { json2.Any(0) }).int() == int(features.SymbolKind.function)
	assert (entry['containerName'] or { json2.Any('') }).str() == 'main'
	uri, start := location_of(entry)
	assert uri == 'file://${dir}/helper.v'
	assert start == position_in(search_helper, 'helper')
}

// The index describes the files on disk, so a declaration that has only been
// typed is not in it. The outline answers for that buffer, and this test is
// where the two lines are known to sit.
// ask_for_outline sends the outline request for a buffer. It lives here because
// each test file is its own binary: a helper in the neighbouring file is an
// unknown function in this one.
fn ask_for_outline(mut s Server, uri string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":8,"method":"textDocument/documentSymbol",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// outline_names is an outline reply as plain names, one level deep.
fn outline_names(reply Message) []string {
	items := as_array(reply.result) or { panic('the outline result is not an array') }
	mut names := []string{}
	for item in items {
		entry := as_object(item) or { panic('a symbol is not an object') }
		names << (entry['name'] or { json2.Any('') }).str()
	}
	return names
}

// The index is refreshed from the buffer an edit arrived in, so a declaration
// nobody has saved is searched as the person typed it.
fn test_a_declaration_that_is_only_typed_is_still_found() {
	mut sink, mut s, dir := search_session('typed')
	ask_for_search(mut s, 'typed_helper')
	reply := sink.last_message()
	assert search_names(reply) == ['typed_helper']
	// the answer points at the file the buffer would be saved to, at the place
	// the name sits in the buffer as it stands
	entry := search_entry(reply, 'typed_helper') or { panic('the answer has no typed_helper') }
	uri, start := location_of(entry)
	assert uri == 'file://${dir}/main.v'
	assert start == position_in(search_typed, 'typed_helper')
	// the same buffer is a file this session holds, and the outline lists it
	ask_for_outline(mut s, 'file://${dir}/main.v')
	assert outline_names(sink.last_message()) == ['main', 'typed_helper']
	// and the file the index read is found by the search
	ask_for_search(mut s, 'Config')
	assert search_names(sink.last_message()) == ['Config']
}

// A query nothing matches is an empty answer rather than an error: the search
// ran, and the workspace has no such name in it.
fn test_a_query_that_matches_nothing_is_an_empty_answer() {
	mut sink, mut s, _dir := search_session('empty')
	ask_for_search(mut s, 'nothingisnamedthis')
	reply := sink.last_message()
	assert reply.kind == .response
	assert reply.error_text == ''
	assert search_entries(reply).len == 0
}

// An empty query is a client asking what is here. The answer is the workspace
// with the shorter names first, and both files are in it: the one on disk and
// the one open in a buffer.
fn test_an_empty_query_lists_the_workspace() {
	mut sink, mut s, _dir := search_session('everything')
	ask_for_search(mut s, '')
	names := search_names(sink.last_message())
	// the module clause of each file is a declaration in its own right, so
	// `main` is in the answer twice
	assert names == ['main', 'main', 'name', 'Config', 'helper', 'typed_helper']
}

// Nothing has been indexed, so there is nothing to search. An empty list would
// read as a workspace with no declarations in it.
fn test_a_session_with_no_indexed_folder_is_refused() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.serve_message(parse_message(search_initialize([])))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	ask_for_search(mut s, 'helper')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('nothing to search')
}
