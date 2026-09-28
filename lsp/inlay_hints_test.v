module lsp

import json2
import os

// The lane tests drive real notifications through the server, because the part
// that can go wrong is which text the index ends up describing: the buffer, the
// file behind it, or neither.

const hint_client = '{"textDocument":{"inlayHint":{"dynamicRegistration":false}}}'

const lane_util = 'module main

struct Point {
	x int
	y int
}

fn scale(p Point, factor int) Point {
	return Point{ p.x * factor, p.y * factor }
}
'

// The buffer writes a positional struct literal, a call into the other file and
// a defer, which is every family the lane has.
const lane_buffer = 'module main

fn main() {
	base := Point{ 2, 3 }
	scaled := scale(base, 4)
	defer println(scaled)
	println(base)
}
'

// Every label this buffer earns, in the order the lane sends them.
const lane_labels = ['x:', 'y:', ': Point', 'p:', 'factor:', 'defer: println(scaled)']

// hint_project writes the file the buffer calls into and returns the directory.
// No main.v is written: that is what makes the disk read a test of its own. The
// name keeps the tests apart, since one of them writes main.v on purpose.
fn hint_project(name string) string {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-inlay-hints-test-${name}')
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), lane_util) or { panic(err.msg()) }
	return dir
}

// hint_session is a session with the folder indexed and one buffer open, which
// is what a client has when it asks for hints.
fn hint_session(dir string, file_name string, text string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	mut folder := map[string]json2.Any{}
	folder['uri'] = json2.Any('file://${dir}')
	folder['name'] = json2.Any('scratch')
	s.serve_message(parse_message(initialize_request(hint_client, [json2.Any(folder)])))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_hint_buffer(mut s, 'file://${dir}/${file_name}', text)
	return sink, s
}

// initialize_request builds the request that opens a session around the folders
// the index is built from. The capabilities arrive as JSON because that is what
// the client sends.
fn initialize_request(client_capabilities string, folders []json2.Any) string {
	return '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
		client_capabilities + ',"workspaceFolders":' + json2.encode(json2.Any(folders)) + '}}'
}

// open_hint_buffer sends the didOpen a client sends before it asks about a buffer.
fn open_hint_buffer(mut s Server, uri string, text string) {
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

// ask_for_hints sends the request the lane answers, optionally limited to a part
// of the buffer.
fn ask_for_hints(mut s Server, uri string, requested ?Range) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	if asked := requested {
		params['range'] = encode_range(asked)
	}
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,"method":"textDocument/inlayHint",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// hint_labels_of reads the labels out of a reply, in the order they were sent.
fn hint_labels_of(reply Message) []string {
	items := as_array(reply.result) or { panic('the hint result is not an array') }
	mut labels := []string{}
	for item in items {
		entry := as_object(item) or { panic('a hint is not an object') }
		label := entry['label'] or { panic('a hint has no label') }
		labels << label.str()
	}
	return labels
}

// hint_positions_of reads where the hints were placed.
fn hint_positions_of(reply Message) []Position {
	items := as_array(reply.result) or { panic('the hint result is not an array') }
	mut positions := []Position{}
	for item in items {
		entry := as_object(item) or { panic('a hint is not an object') }
		positions << parse_position(entry['position'] or { panic('a hint has no position') }) or {
			panic('the position did not parse')
		}
	}
	return positions
}

fn test_the_buffer_is_what_the_hints_describe() {
	// main.v is not on disk. Every label comes from the text the client sent,
	// from the file next to it, or from both.
	dir := hint_project('buffer')
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	assert hint_labels_of(reply) == lane_labels
	assert !os.exists(os.join_path(dir, 'main.v'))
}

fn test_the_file_on_disk_is_not_what_answers() {
	dir := hint_project('disk')
	// The file on disk holds a println and nothing else. A lane that read it
	// instead of the buffer would have nothing to send.
	disk := 'module main

fn main() {
	println(1)
}
'
	os.write_file(os.join_path(dir, 'main.v'), disk) or { panic(err.msg()) }
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	assert hint_labels_of(reply) == lane_labels
	assert (os.read_file(os.join_path(dir, 'main.v')) or { '' }) == disk
}

fn test_a_buffer_outside_the_indexed_folder_is_refused() {
	dir := hint_project('outside')
	outside := os.join_path(os.temp_dir(), 'visor-lsp-inlay-hints-outside')
	os.mkdir_all(outside) or { panic(err.msg()) }
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	open_hint_buffer(mut s, 'file://${outside}/loose.v', 'module main\n\nfn main() {}\n')
	ask_for_hints(mut s, 'file://${outside}/loose.v', none)
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('no indexed workspace folder contains')
}

fn test_a_request_before_anything_was_indexed_is_an_error() {
	// A session with no folder has nothing to answer from, and an empty list
	// would read as a buffer with nothing worth saying in it.
	dir := hint_project('unindexed')
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${hint_client}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_hint_buffer(mut s, 'file://${dir}/main.v', lane_buffer)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('no workspace folder was indexed')
}

fn test_the_requested_range_limits_the_answer() {
	dir := hint_project('range')
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	// The opening lines only, which is the part of the file a client has drawn
	// when it asks about what is on screen.
	ask_for_hints(mut s, 'file://${dir}/main.v', Range{
		start: Position{
			line:      0
			character: 0
		}
		end:   Position{
			line:      4
			character: 30
		}
	})
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	// the struct literal and the call are inside; the defer on line 5 is not
	assert hint_labels_of(reply) == ['x:', 'y:', ': Point', 'p:', 'factor:']
}

fn test_settings_turn_a_family_off() {
	dir := hint_project('settings')
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration",' +
		'"params":{"settings":{"visor":{"inlayHints":{"types":false,"defers":false}}}}}'))
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	assert hint_labels_of(reply) == ['x:', 'y:', 'p:', 'factor:']
}

fn test_a_hint_carries_a_position_a_client_can_place() {
	dir := hint_project('position')
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	positions := hint_positions_of(reply)
	// `base := Point{ 2, 3 }` is line 3, and the value the x hint describes
	// starts at column 16 of it.
	assert positions.first() == Position{
		line:      3
		character: 16
	}
	// the defer label is drawn at the closing brace of main, which is line 7
	assert positions.last().line == 7
}
