module lsp

import json2
import vtool

// The spelling `v fmt` produces from the buffer the tests send. Asserted against
// a literal rather than against a second run of the compiler.
const formatted_text = "fn main() {\n\tprintln('x')\n}\n"

const unformatted_text = 'fn   main(){\nprintln("x")\n}\n'

// A buffer no formatter can parse.
const unparsable_text = 'fn main() {\n\tx := \n}\n'

// initialize_session takes a server through the handshake. A request that
// arrives before initialize is refused, which is the protocol working rather
// than the feature under test.
fn initialize_session(mut s Server) {
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":{"textDocument":{"synchronization":{},"formatting":{}}}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
}

// A session with a real compiler and an open document, which is what a client
// has when it asks for formatting.
fn formatting_session(text string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.probe_compiler()
	initialize_session(mut s)
	open_document(mut s, 'file:///tmp/fmt.v', text)
	return sink, s
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

fn ask_for_formatting(mut s Server, uri string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,"method":"textDocument/formatting",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

fn test_formatting_replaces_the_whole_buffer() {
	mut sink, mut s := formatting_session(unformatted_text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	assert reply.kind == .response
	assert reply.id_key() == 'n:9'
	edits := as_array(reply.result) or { panic('the result is not an edit list') }
	assert edits.len == 1
	edit := as_object(edits[0]) or { panic('the edit is not an object') }
	assert (edit['newText'] or { panic('no newText') }).str() == formatted_text
	range_ := as_object(edit['range'] or { panic('no range') }) or { panic('range is not an object') }
	start := as_object(range_['start'] or { panic('no start') }) or { panic('start is not an object') }
	end := as_object(range_['end'] or { panic('no end') }) or { panic('end is not an object') }
	assert (start['line'] or { panic('no line') }).int() == 0
	assert (start['character'] or { panic('no character') }).int() == 0
	// the buffer has three lines and ends with a newline, so the end of it is
	// the line after the last one.
	assert (end['line'] or { panic('no line') }).int() == 3
	assert (end['character'] or { panic('no character') }).int() == 0
}

fn test_an_already_formatted_buffer_needs_no_edits() {
	mut sink, mut s := formatting_session(formatted_text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	assert reply.kind == .response
	edits := as_array(reply.result) or { panic('the result is not an edit list') }
	assert edits.len == 0
}

fn test_the_end_position_counts_code_units_not_bytes() {
	// The last line carries an astral character, which is one rune, four bytes
	// and two UTF-16 units. A byte count would answer 9 here.
	text := 'fn   main(){\nprintln("x")\n} // \U0001F600'
	mut sink, mut s := formatting_session(text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	edits := as_array(reply.result) or { panic('the result is not an edit list') }
	edit := as_object(edits[0]) or { panic('the edit is not an object') }
	range_ := as_object(edit['range'] or { panic('no range') }) or { panic('range is not an object') }
	end := as_object(range_['end'] or { panic('no end') }) or { panic('end is not an object') }
	assert (end['line'] or { panic('no line') }).int() == 2
	assert (end['character'] or { panic('no character') }).int() == 7
}

fn test_a_buffer_that_is_not_open_is_an_error() {
	mut sink, mut s := formatting_session(formatted_text)
	ask_for_formatting(mut s, 'file:///tmp/somewhere_else.v')
	reply := sink.last_message()
	assert reply.error_code == code_invalid_params
	assert reply.error_text.contains('no open document')
}

fn test_a_buffer_the_formatter_refuses_is_an_error() {
	mut sink, mut s := formatting_session(unparsable_text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('`v fmt` refused the buffer')
}

fn test_a_session_with_no_compiler_says_so() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	initialize_session(mut s)
	s.report_no_compiler('no V compiler on PATH')
	open_document(mut s, 'file:///tmp/fmt.v', unformatted_text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('no V compiler to format with')
	assert reply.error_text.contains('no V compiler on PATH')
}

fn test_a_compiler_that_cannot_format_says_so() {
	missing := vtool.Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.take_compiler(missing)
	initialize_session(mut s)
	open_document(mut s, 'file:///tmp/fmt.v', unformatted_text)
	ask_for_formatting(mut s, 'file:///tmp/fmt.v')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('this compiler cannot format')
	assert reply.error_text.contains('not a file')
}
