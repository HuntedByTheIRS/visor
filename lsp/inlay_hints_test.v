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
const lane_labels = ['x:', 'y:', ': Point', 'p:', 'factor:', '; defer: println(scaled)']

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
	// the defer label is drawn at the end of the last line of the body, which is
	// line 6, above the closing brace on line 7
	assert positions.last() == Position{
		line:      6
		character: 14
	}
}

// entry_flag reads a boolean out of a hint, which is how a client is told where
// the spaces around a label go.
fn entry_flag(entry map[string]json2.Any, name string) bool {
	value := entry[name] or { return false }
	if value is bool {
		return value as bool
	}
	return false
}

// A label is drawn against the text around it, so the padding it asks for is the
// difference between `factor: 4` and `factor4`. The defer label, the one that
// follows code on its line, opens with its own separator instead:
// `os.execute('x'); defer: y`.
fn test_the_labels_ask_for_the_spacing_they_need() {
	dir := hint_project('spacing')
	mut sink, mut s := hint_session(dir, 'main.v', lane_buffer)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	items := as_array(sink.last_message().result) or { panic('the hint result is not an array') }
	mut padded_left := 0
	mut padded_right := 0
	for item in items {
		entry := as_object(item) or { panic('a hint is not an object') }
		if entry_flag(entry, 'paddingLeft') {
			padded_left++
		}
		if entry_flag(entry, 'paddingRight') {
			padded_right++
		}
	}
	// the labels that sit in front of something, and the one that follows the
	// last statement of the block, which separates itself with a semicolon rather
	// than asking for a space.
	assert padded_right == 4
	assert padded_left == 0
}

// The function this buffer calls is declared in the buffer itself and is on no
// disk, so the parameter names below are a question only the buffer's own stubs
// can answer. The struct it returns comes from the file next to it, so the field
// hints need the folder's index too.
const added_buffer = 'module main

fn offset(base int, extra int) Point {
	return Point{ base + extra, extra }
}

fn main() {
	result := offset(3, 4)
	println(result)
}
'

// Every label this buffer earns, in the order the lane sends them: the two
// fields of the return literal, then the type the call infers, then the two
// parameter names.
const added_labels = ['x:', 'y:', ': Point', 'base:', 'extra:']

// add_workspace_folder sends the notification a client sends when the person
// opens another folder in the same window.
fn add_workspace_folder(mut s Server, dir string) {
	mut folder := map[string]json2.Any{}
	folder['uri'] = json2.Any('file://${dir}')
	folder['name'] = json2.Any('scratch')
	mut event := map[string]json2.Any{}
	event['added'] = json2.Any([json2.Any(folder)])
	mut params := map[string]json2.Any{}
	params['event'] = json2.Any(event)
	mut message := map[string]json2.Any{}
	message['jsonrpc'] = json2.Any(jsonrpc_version)
	message['method'] = json2.Any('workspace/didChangeWorkspaceFolders')
	message['params'] = json2.Any(params)
	s.serve_message(parse_message(json2.encode(json2.Any(message))))
}

// A folder can turn up after the handshake, and a client that adds one expects
// the answers it would have got by opening the project first. Both halves of
// that have to happen for any label here to come back: the folder handler walks
// the folders again, and the buffer that was open with no root behind it is
// handed over a second time.
fn test_a_folder_added_later_answers_for_the_buffers_already_open() {
	dir := hint_project('added')
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.serve_message(parse_message(initialize_request(hint_client, []json2.Any{})))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_hint_buffer(mut s, 'file://${dir}/main.v', added_buffer)
	// With no folder indexed the buffer is refused in words, not answered with
	// an empty list.
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	assert sink.last_message().error_code == code_request_failed
	add_workspace_folder(mut s, dir)
	ask_for_hints(mut s, 'file://${dir}/main.v', none)
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	assert hint_labels_of(reply) == added_labels
}
