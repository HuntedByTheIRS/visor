module lsp

import json2
import os

// The rename lane plans edits over buffers the session holds, so these tests
// open a folder of real files, open one of them as a document, and ask through
// the same message path a client uses.

const rename_client = '{"textDocument":{"rename":{"dynamicSelection":false,"prepareSupport":true}}}'

const rename_app = "module main

import greeter

struct Point {
	x int
	y int
}

fn helper(base int) int {
	local_count := base + 1
	return local_count
}

fn main() {
	point := Point{ 1, 2 }
	println(helper(2))
	println(greeter.Greeting{ text_body: 'hi' }.body_of())
}
"

// rename_greeter is the file another module reaches: its method is renamed where
// it is declared and where it is called.
const rename_greeter = 'module greeter

pub struct Greeting {
pub:
	text_body string
}

pub fn (g Greeting) body_of() string {
	return g.text_body
}
'

// rename_session opens a folder holding both files and opens the first as a
// document, which is what a client has while a person is looking at it.
fn rename_session(name string) (&BufferSink, &Server, string) {
	dir := os.join_path(os.temp_dir(), 'visor-lsp-rename-test-${name}')
	os.mkdir_all(os.join_path(dir, 'greeter')) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'app.v'), rename_app) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'greeter', 'greeter.v'), rename_greeter) or {
		panic(err.msg())
	}
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	mut folder := map[string]json2.Any{}
	folder['uri'] = json2.Any('file://${dir}')
	folder['name'] = json2.Any('scratch')
	s.serve_message(parse_message(rename_initialize([json2.Any(folder)])))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_rename_document(mut s, 'file://${dir}/app.v', rename_app)
	return sink, s, dir
}

// rename_initialize builds the request that opens a session around the folders
// the index is built from.
fn rename_initialize(folders []json2.Any) string {
	return '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
		rename_client + ',"workspaceFolders":' + json2.encode(json2.Any(folders)) + '}}'
}

// open_rename_document sends the didOpen a client sends before it asks.
fn open_rename_document(mut s Server, uri string, text string) {
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

// position_in is where a piece of the fixture sits, as the protocol counts:
// computed from the text so editing the fixture cannot move an expectation.
fn position_in(text string, needle string, skip int) Position {
	mut seen := 0
	mut from := 0
	mut offset := -1
	for from < text.len {
		at := text[from..].index(needle) or { break }
		if seen == skip {
			offset = from + at
			break
		}
		seen++
		from += at + 1
	}
	if offset < 0 {
		panic('${needle} is not in the fixture')
	}
	return position_for_offset(text, offset)
}

// ask_prepare_rename sends the request a client sends before it shows a rename
// box.
fn ask_prepare_rename(mut s Server, uri string, position Position) {
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":7,"method":"textDocument/prepareRename",' +
		'"params":{"textDocument":{"uri":"${uri}"},"position":' +
		json2.encode(json2.Any(encode_position(position))) + '}}'))
}

// ask_rename sends the request a client sends when a name has been typed.
fn ask_rename(mut s Server, uri string, position Position, new_name string) {
	mut params := map[string]json2.Any{}
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	params['textDocument'] = json2.Any(document)
	params['position'] = json2.Any(encode_position(position))
	params['newName'] = json2.Any(new_name)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":8,"method":"textDocument/rename",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// prepare_answer reads a prepare reply into its range and its placeholder.
fn prepare_answer(reply Message) (Range, string) {
	assert reply.kind == .response, reply.error_text
	answer := as_object(reply.result) or { panic('the prepare result is not an object') }
	placeholder := (answer['placeholder'] or { panic('no placeholder') }).str()
	range_ := answer['range'] or { panic('no range') }
	return parse_range(range_) or { panic('the prepare range is not a range') }, placeholder
}

// plan_changes reads a rename reply into one entry per file it edits.
fn plan_changes(reply Message) map[string][]map[string]json2.Any {
	assert reply.kind == .response, reply.error_text
	answer := as_object(reply.result) or { panic('the rename result is not an object') }
	changes := as_object(answer['changes'] or { panic('no changes') }) or {
		panic('changes is not an object')
	}
	mut edits := map[string][]map[string]json2.Any{}
	for uri, edits_value in changes {
		mut per_file := []map[string]json2.Any{}
		for edit in as_array(edits_value) or { panic('edits are not an array') } {
			per_file << as_object(edit) or { panic('an edit is not an object') }
		}
		edits[uri] = per_file
	}
	return edits
}

// edited_range is the range one edit rewrites.
fn edited_range(edit map[string]json2.Any) Range {
	return parse_range(edit['range'] or { panic('an edit has no range') }) or {
		panic('an edit range is not a range')
	}
}

// edited_text is the name one edit writes.
fn edited_text(edit map[string]json2.Any) string {
	return (edit['newText'] or { panic('an edit has no newText') }).str()
}

fn test_prepare_rename_names_the_position_and_selects_it() {
	mut sink, mut s, dir := rename_session('prepare')
	ask_prepare_rename(mut s, 'file://${dir}/app.v', position_in(rename_app, 'local_count', 0))
	range_, placeholder := prepare_answer(sink.last_message())
	want := position_in(rename_app, 'local_count', 0)
	assert placeholder == 'local_count'
	assert range_.start == want
	assert range_.end.line == want.line
	assert range_.end.character == want.character + 'local_count'.len
}

// A name the position does not hold is refused with the reason, because a client
// that got an empty answer would show no rename affordance and no reason either.
fn test_prepare_rename_refuses_a_module_clause_in_words() {
	mut sink, mut s, dir := rename_session('clause')
	ask_prepare_rename(mut s, 'file://${dir}/app.v', position_in(rename_app, 'main', 0))
	assert sink.last_message().error_text.contains('named by the directory')
}

fn test_prepare_rename_of_an_unopened_buffer_is_refused() {
	mut sink, mut s, dir := rename_session('unopened')
	ask_prepare_rename(mut s, 'file://${dir}/greeter/greeter.v', position_in(rename_greeter,
		'body_of', 0))
	assert sink.last_message().error_text.contains('not open in this session')
}

fn test_prepare_rename_of_a_position_that_names_nothing_is_refused() {
	mut sink, mut s, dir := rename_session('nothing')
	ask_prepare_rename(mut s, 'file://${dir}/app.v', position_in(rename_app, "'hi'", 0))
	assert sink.last_message().error_text.contains('nothing at this position')
}

// A local lives in one buffer, so the plan is one file and the two places the
// name appears in it.
fn test_a_local_is_planned_as_edits_in_its_own_buffer() {
	mut sink, mut s, dir := rename_session('local')
	uri := 'file://${dir}/app.v'
	ask_rename(mut s, uri, position_in(rename_app, 'local_count', 0), 'count_local')
	changes := plan_changes(sink.last_message())
	assert changes.len == 1
	edits := changes[uri]
	assert edits.len == 2
	for edit in edits {
		assert edited_text(edit) == 'count_local'
	}
	// the declaration first, then the read of it
	assert edited_range(edits[0]).start == position_in(rename_app, 'local_count', 0)
	assert edited_range(edits[1]).start == position_in(rename_app, 'local_count', 1)
}

// A public name is reached from the module that imports it, so the plan covers
// both files and names each of them by the uri the client knows.
fn test_a_public_name_is_planned_across_the_files_that_use_it() {
	mut sink, mut s, dir := rename_session('public')
	ask_rename(mut s, 'file://${dir}/app.v', position_in(rename_app, 'body_of', 0), 'content_of')
	changes := plan_changes(sink.last_message())
	assert changes.len == 2
	call_edits := changes['file://${dir}/app.v']
	assert call_edits.len == 1
	assert edited_text(call_edits[0]) == 'content_of'
	assert edited_range(call_edits[0]).start == position_in(rename_app, 'body_of', 0)
	declaration_edits := changes['file://${dir}/greeter/greeter.v']
	assert declaration_edits.len == 1
	assert edited_text(declaration_edits[0]) == 'content_of'
	assert edited_range(declaration_edits[0]).start == position_in(rename_greeter, 'body_of', 0)
	// the range covers the name and nothing else, so a client that applies it
	// replaces exactly the name
	range_ := edited_range(declaration_edits[0])
	assert range_.end.character == range_.start.character + 'body_of'.len
}

// A name V cannot use is refused before anything is planned. The client is the
// one that would write the edits, and no edit is sent for it to apply.
fn test_a_name_that_cannot_be_used_is_refused_before_anything_is_planned() {
	mut sink, mut s, dir := rename_session('bad_name')
	uri := 'file://${dir}/app.v'
	position := position_in(rename_app, 'local_count', 0)
	ask_rename(mut s, uri, position, 'fn')
	assert sink.last_message().error_text.contains('keyword')
	ask_rename(mut s, uri, position, '1st')
	assert sink.last_message().error_text.contains('letter')
	ask_rename(mut s, uri, position, '')
	assert sink.last_message().error_text.contains('empty')
	// and a name that is fine is still answered with its edits
	ask_rename(mut s, uri, position, 'count_local')
	assert plan_changes(sink.last_message()).len == 1
}

// The rename is a set of edits for the client to apply, which is what makes one
// undo in the editor, so the files are never written here.
fn test_the_rename_does_not_write_the_files() {
	mut sink, mut s, dir := rename_session('no_write')
	path := os.join_path(dir, 'greeter', 'greeter.v')
	ask_rename(mut s, 'file://${dir}/app.v', position_in(rename_app, 'body_of', 0), 'content_of')
	plan_changes(sink.last_message())
	assert os.read_file(path) or { '' } == rename_greeter
}
