module lsp

import json2
import os
import time
import vtool

// A buffer that parses everything except its third line, so the one finding it
// earns has a known line and column.
const broken_buffer = 'fn main() {\n\tx := \n}\n'

// Nothing wrong with it at all.
const clean_buffer = 'fn main() {\n\tprintln(1)\n}\n'

// One warning and one error in one file. The warning is an import that is never
// used, which the compiler only prints when it has something else to report,
// and the missing `module main` is that something.
const warning_buffer = 'module foo\n\nimport os\n\npub fn f() int {\n\treturn 1\n}\n'

// The finding sits after a character that is four bytes wide and two UTF-16
// code units wide. A server that passed the compiler's byte column straight
// through would place it two characters too far along.
const astral_buffer = "fn main() {\n\tx := '\U0001F600' q\n}\n"

// The buffer these tests open is never written to disk. The text comes from the
// client, which is what an editor holds for a file nobody has saved, and a
// finding about it can only have come from that text.
const probe_uri = 'file:///tmp/visor-diagnostics-probe/a.v'

// A client that pulls findings and never shows a pushed one.
const pulling_client = '{"textDocument":{"synchronization":{},"diagnostic":{}}}'

// A client that shows what the server pushes, which Neovim and VS Code both
// declare. It offers the pull too, because the two paths answer from one report.
const pushing_client = '{"textDocument":{"synchronization":{},"diagnostic":{},' +
	'"publishDiagnostics":{"versionSupport":true}}}'

// diagnostics_session takes a server through the handshake with a real compiler
// probed. The sink is emptied at the end, so a test reads only what its own
// request produced.
fn diagnostics_session(client_capabilities string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.probe_compiler()
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${client_capabilities}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	sink.messages = []
	return sink, s
}

// open_buffer sends the didOpen a client sends before it asks about a buffer.
fn open_buffer(mut s Server, uri string, text string) {
	s.serve_message(parse_message(open_body_for(uri, 1, text)))
}

// open_body_for builds a didOpen for a buffer, with the text encoded rather
// than escaped by hand.
fn open_body_for(uri string, version int, text string) string {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['languageId'] = json2.Any('v')
	document['version'] = json2.Any(version)
	document['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	return encode_notification('textDocument/didOpen', json2.Any(params))
}

// edit_buffer replaces the whole buffer, which incremental sync allows and a
// client that lost track sends. No save goes with it: the text is the client's
// and nothing in these tests writes it anywhere.
fn edit_buffer(mut s Server, uri string, version int, text string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['version'] = json2.Any(version)
	mut change := map[string]json2.Any{}
	change['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	params['contentChanges'] = json2.Any([json2.Any(change)])
	s.serve_message(parse_message(encode_notification('textDocument/didChange', json2.Any(params))))
}

// pull_report asks for the findings of a buffer. echo is the resultId the
// client already holds, empty when it holds none.
fn pull_report(mut s Server, uri string, echo string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	if echo != '' {
		params['previousResultId'] = json2.Any(echo)
	}
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":7,"method":"textDocument/diagnostic",' +
		'"params":${json2.encode(json2.Any(params))}}'))
}

// due_now runs the checks an edit scheduled. The debounce is measured against
// the clock the server reads, so a moment far enough ahead is what makes a
// scheduled check due without any test sleeping for it.
fn due_now(mut s Server) int {
	return s.pump_diagnostics(time.ticks() + 10_000)
}

// report_obj reads a pull answer as an object.
fn report_obj(reply Message) map[string]json2.Any {
	return as_object(reply.result) or { panic('the result is not an object') }
}

fn report_kind_of(reply Message) string {
	obj := report_obj(reply)
	return (obj['kind'] or { panic('the report has no kind') }).str()
}

fn result_id_of(reply Message) string {
	obj := report_obj(reply)
	return (obj['resultId'] or { panic('the report has no resultId') }).str()
}

fn items_of(reply Message) []json2.Any {
	obj := report_obj(reply)
	return as_array(obj['items'] or { panic('a full report has no items') }) or {
		panic('items is not an array')
	}
}

// range_of reads a finding's range as four numbers.
fn range_of(item json2.Any) (int, int, int, int) {
	obj := as_object(item) or { panic('the finding is not an object') }
	range_ := as_object(obj['range'] or { panic('the finding has no range') }) or {
		panic('range is not an object')
	}
	start := as_object(range_['start'] or { panic('the range has no start') }) or {
		panic('start is not an object')
	}
	end := as_object(range_['end'] or { panic('the range has no end') }) or {
		panic('end is not an object')
	}
	return (start['line'] or { panic('no line') }).int(), (start['character'] or { panic('no character') }).int(), (end['line'] or { panic('no end line') }).int(), (end['character'] or { panic('no end character') }).int()
}

fn severity_of(item json2.Any) int {
	obj := as_object(item) or { panic('the finding is not an object') }
	return (obj['severity'] or { panic('the finding has no severity') }).int()
}

fn message_of(item json2.Any) string {
	obj := as_object(item) or { panic('the finding is not an object') }
	return (obj['message'] or { panic('the finding has no message') }).str()
}

// last_pushed reads the last payload the server pushed, or none when it pushed
// nothing at all. The name is not `published`: a local in diagnostics.v carries
// that one, and a test helper that shadows it earns a compile notice.
fn last_pushed(sink &BufferSink) ?map[string]json2.Any {
	for i := sink.messages.len - 1; i >= 0; i-- {
		parsed := parse_message(sink.messages[i])
		if parsed.method == publish_method {
			return as_object(parsed.params) or { map[string]json2.Any{} }
		}
	}
	return none
}

// push_count is how many pushes the server sent. It exists so a test can assert
// on silence, which an empty payload would otherwise look like.
fn push_count(sink &BufferSink) int {
	mut total := 0
	for message in sink.messages {
		if parse_message(message).method == publish_method {
			total++
		}
	}
	return total
}

fn pushed_items(note map[string]json2.Any) []json2.Any {
	return as_array(note['diagnostics'] or { panic('the push has no diagnostics') }) or {
		panic('diagnostics is not an array')
	}
}

fn test_a_pull_reports_the_finding_in_an_unsaved_buffer() {
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	// the file is not on disk. The finding below can only have come from the
	// text the client sent.
	assert !os.exists(path_from_uri(probe_uri))
	pull_report(mut s, probe_uri, '')
	reply := sink.last_message()
	assert reply.kind == .response
	assert reply.id_key() == 'n:7'
	assert report_kind_of(reply) == 'full'
	items := items_of(reply)
	assert items.len == 1
	line, character, end_line, end_character := range_of(items[0])
	assert line == 2
	assert character == 0
	// the compiler says nothing about where the token ends, so the range covers
	// the rest of the line rather than a point.
	assert end_line == 2
	assert end_character > character
	assert severity_of(items[0]) == 1
	assert message_of(items[0]).contains('unexpected token')
}

fn test_the_report_describes_the_buffer_and_not_the_file_on_disk() {
	// The file on disk compiles, and the buffer in front of the person does not.
	// The buffer is what is being edited, so it is the one that gets reported on.
	dir := os.join_path(os.temp_dir(), 'visor-diagnostics-on-disk')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err.msg()) }
	path := os.join_path(dir, 'a.v')
	os.write_file(path, clean_buffer) or { panic(err.msg()) }
	defer {
		os.rmdir_all(dir) or {}
	}
	uri := 'file://${path}'
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, uri, broken_buffer)
	pull_report(mut s, uri, '')
	items := items_of(sink.last_message())
	assert items.len == 1
	_, character, _, _ := range_of(items[0])
	assert character == 0
	// and the clean file on disk is reported as clean once the buffer matches it.
	edit_buffer(mut s, uri, 2, clean_buffer)
	due_now(mut s)
	pull_report(mut s, uri, '')
	assert items_of(sink.last_message()).len == 0
}

fn test_an_edit_in_the_buffer_is_what_the_next_report_describes() {
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	pull_report(mut s, probe_uri, '')
	before := sink.last_message()
	assert items_of(before).len == 1
	// The fix happens in the buffer and nowhere else: no didSave is sent, so
	// nothing here has written a file, and the report still follows the text.
	edit_buffer(mut s, probe_uri, 2, clean_buffer)
	pull_report(mut s, probe_uri, result_id_of(before))
	after := sink.last_message()
	assert report_kind_of(after) == 'full'
	assert items_of(after).len == 0
	assert result_id_of(after) != result_id_of(before)
}

fn test_a_pull_that_echoes_the_id_it_holds_is_unchanged() {
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	pull_report(mut s, probe_uri, '')
	id := result_id_of(sink.last_message())
	// the client already has this answer, and the buffer has not moved since.
	pull_report(mut s, probe_uri, id)
	again := sink.last_message()
	assert report_kind_of(again) == 'unchanged'
	assert result_id_of(again) == id
}

fn test_a_pull_with_no_echoed_id_answers_from_what_is_known() {
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	due_now(mut s)
	// the check the open scheduled has already run, so a first pull is answered
	// from its report rather than from a second compiler.
	pull_report(mut s, probe_uri, '')
	assert report_kind_of(sink.last_message()) == 'full'
}

fn test_a_warning_keeps_its_own_severity() {
	sink, mut s := diagnostics_session(pulling_client)
	uri := 'file:///tmp/visor-diagnostics-probe/warn.v'
	open_buffer(mut s, uri, warning_buffer)
	pull_report(mut s, uri, '')
	items := items_of(sink.last_message())
	assert items.len == 2
	mut severities := map[int]int{}
	for item in items {
		level := severity_of(item)
		severities[level] = (severities[level] or { 0 }) + 1
	}
	// 1 is the error and 2 is the warning. The compiler's third level is a
	// notice, which is what an editor calls information.
	assert severities[1] == 1
	assert severities[2] == 1
}

// error_item picks the one error out of a report. The compiler sometimes says
// more than one thing about a damaged line, and a test about where a finding
// lands wants the error rather than the warning beside it.
fn error_item(items []json2.Any) json2.Any {
	mut errors := []json2.Any{}
	for item in items {
		if severity_of(item) == 1 {
			errors << item
		}
	}
	assert errors.len == 1
	return errors[0]
}

fn test_a_finding_after_an_astral_character_is_placed_in_code_units() {
	sink, mut s := diagnostics_session(pulling_client)
	uri := 'file:///tmp/visor-diagnostics-probe/astral.v'
	open_buffer(mut s, uri, astral_buffer)
	pull_report(mut s, uri, '')
	items := items_of(sink.last_message())
	// two findings: the emoji leaves `x` unused, and `q` is an unexpected name.
	// The positions are what this test is about, so it takes the error.
	assert items.len == 2
	line, character, end_line, end_character := range_of(error_item(items))
	assert line == 1
	// `q` sits 13 bytes into that line and 11 UTF-16 code units into it, which
	// is what the client counts in. A byte column would answer 13.
	assert character == 11
	assert end_line == 1
	assert end_character > character
}

fn test_the_workspace_folder_is_what_imports_resolve_against() {
	// One project with a buffer in a subdirectory and a `greeter` module on both
	// levels, with different signatures. Which one the check finds is decided by
	// the root it runs under: the workspace folder for a file inside it, the
	// file's own directory when there is no folder. The signatures differ so the
	// report says which level answered.
	root := os.join_path(os.temp_dir(), 'visor-diagnostics-root')
	os.rmdir_all(root) or {}
	os.mkdir_all(os.join_path(root, 'greeter')) or { panic(err.msg()) }
	os.mkdir_all(os.join_path(root, 'src', 'greeter')) or { panic(err.msg()) }
	os.write_file(os.join_path(root, 'greeter', 'greeter.v'),
		'module greeter\n\npub fn greeting() int {\n	return 1\n}\n') or {
		panic(err.msg())
	}
	os.write_file(os.join_path(root, 'src', 'greeter', 'greeter.v'),
		"module greeter\n\npub fn greeting() string {\n	return 'hi'\n}\n") or {
		panic(err.msg())
	}
	defer {
		os.rmdir_all(root) or {}
	}
	uri := 'file://${os.join_path(root, 'src', 'app.v')}'
	// the project's greeter returns a number, so adding one to it type checks,
	// and the greeter beside the buffer returns text, so it does not.
	text := 'module main\n\nimport greeter\n\nfn main() {\n	println(greeter.greeting() + 1)\n}\n'

	mut rooted_sink := &BufferSink{}
	mut rooted := new_server(rooted_sink)
	rooted.probe_compiler()
	rooted.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${pulling_client},"workspaceFolders":[{"uri":"file://${root}","name":"root"}]}}'))
	rooted.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_buffer(mut rooted, uri, text)
	pull_report(mut rooted, uri, '')
	assert items_of(rooted_sink.last_message()).len == 0

	// no folder: the buffer's own directory becomes the root, the greeter beside
	// it returns text, and adding a number to that is the finding.
	sink, mut loose := diagnostics_session(pulling_client)
	open_buffer(mut loose, uri, text)
	pull_report(mut loose, uri, '')
	items := items_of(sink.last_message())
	assert items.len == 1
	assert message_of(items[0]).contains('cannot use')
	line, character, _, _ := range_of(items[0])
	assert line == 5
	assert character > 0
}

fn test_a_push_client_is_told_what_the_buffer_holds() {
	sink, mut s := diagnostics_session(pushing_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	// The check waits for the typing to stop, so a pass that runs before the
	// debounce expires publishes nothing.
	early := s.pump_diagnostics(0)
	assert early == 0
	assert push_count(sink) == 0
	// The pump is written outside the assert: a -prod build drops every assert
	// statement, and a call left inside one never runs.
	ran := due_now(mut s)
	assert ran == 1
	note := last_pushed(sink) or { panic('nothing was pushed') }
	assert (note['uri'] or { panic('the push has no uri') }).str() == probe_uri
	assert (note['version'] or { panic('the push has no version') }).int() == 1
	items := pushed_items(note)
	assert items.len == 1
	line, character, _, _ := range_of(items[0])
	assert line == 2
	assert character == 0
}

fn test_a_fix_in_the_buffer_clears_what_was_pushed() {
	sink, mut s := diagnostics_session(pushing_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	due_now(mut s)
	assert push_count(sink) == 1
	edit_buffer(mut s, probe_uri, 2, clean_buffer)
	ran := due_now(mut s)
	assert ran == 1
	note := last_pushed(sink) or { panic('nothing was pushed') }
	// an empty list is how a client is told to take the marks away.
	assert pushed_items(note).len == 0
	assert (note['version'] or { panic('the push has no version') }).int() == 2
}

fn test_a_client_that_shows_no_pushed_findings_is_not_pushed_to() {
	sink, mut s := diagnostics_session(pulling_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	// The check runs, because this client pulls. Nothing goes out on the wire,
	// because it never said it would show a pushed finding.
	ran := due_now(mut s)
	assert ran == 0
	assert push_count(sink) == 0
	pull_report(mut s, probe_uri, '')
	assert items_of(sink.last_message()).len == 1
}

fn test_closing_the_buffer_clears_what_the_client_shows() {
	sink, mut s := diagnostics_session(pushing_client)
	open_buffer(mut s, probe_uri, broken_buffer)
	due_now(mut s)
	assert push_count(sink) == 1
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didClose","params":' +
		'{"textDocument":{"uri":"${probe_uri}"}}}'))
	assert push_count(sink) == 2
	note := last_pushed(sink) or { panic('nothing was pushed') }
	assert pushed_items(note).len == 0
	// a pull for a closed buffer has nothing to answer from.
	pull_report(mut s, probe_uri, '')
	assert sink.last_message().error_code == code_invalid_params
}

fn test_a_session_with_no_compiler_says_so_rather_than_answering_nothing() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.report_no_compiler('no V compiler on PATH')
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${pulling_client}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_buffer(mut s, probe_uri, broken_buffer)
	pull_report(mut s, probe_uri, '')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('no V compiler to check with')
	assert reply.error_text.contains('no V compiler on PATH')
	// and nothing is scheduled for a compiler that cannot run.
	ran := due_now(mut s)
	assert ran == 0
}

fn test_a_compiler_that_cannot_check_says_which_one() {
	missing := vtool.Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.take_compiler(missing)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${pulling_client}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_buffer(mut s, probe_uri, broken_buffer)
	pull_report(mut s, probe_uri, '')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('this compiler cannot check a buffer')
	assert reply.error_text.contains('not a file')
}

fn test_a_pull_for_a_buffer_the_store_does_not_have_never_checks_the_disk() {
	// The file is on disk and clean. The request names a buffer that was never
	// opened, and answering it from the file would report on something the
	// person is not editing.
	dir := os.join_path(os.temp_dir(), 'visor-diagnostics-unopened')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or { panic(err.msg()) }
	path := os.join_path(dir, 'a.v')
	os.write_file(path, broken_buffer) or { panic(err.msg()) }
	defer {
		os.rmdir_all(dir) or {}
	}
	sink, mut s := diagnostics_session(pulling_client)
	pull_report(mut s, 'file://${path}', '')
	reply := sink.last_message()
	assert reply.error_code == code_invalid_params
	assert reply.error_text.contains('no open document')
}
