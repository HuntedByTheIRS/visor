module lsp

import json2

// sync_server returns a session past initialize with the sink emptied, because
// text sync only runs once a session is open.
fn sync_server() (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":100,"method":"initialize","params":' +
		'{"capabilities":{"textDocument":{"synchronization":{}}},"workspaceFolders":[' +
		'{"uri":"file:///tmp/proj","name":"proj"}]}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	sink.messages = []
	return sink, s
}

fn open_body(uri string, version int, text string) string {
	// the text goes through a JSON encode so the test does not have to escape a
	// newline by hand.
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['languageId'] = json2.Any('v')
	document['version'] = json2.Any(version)
	document['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	return encode_notification('textDocument/didOpen', json2.Any(params))
}

fn test_did_open_fills_the_document_store() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'fn main() {}\n')))
	assert s.documents.count() == 1
	doc := s.document('file:///tmp/proj/a.v') or { panic('the buffer is missing') }
	assert doc.version == 1
	assert doc.language_id == 'v'
	assert doc.text == 'fn main() {}\n'
}

fn test_did_change_applies_a_ranged_edit() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'fn main() {}\n')))
	// characters 10 and 11 of the line are "{}", so the edit replaces both.
	change := '{"textDocument":{"uri":"file:///tmp/proj/a.v","version":2},"contentChanges":[' +
		'{"range":{"start":{"line":0,"character":10},"end":{"line":0,"character":12}},"text":"return"}]}'
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didChange","params":${change}}'))
	doc := s.document('file:///tmp/proj/a.v') or { panic('the buffer is missing') }
	assert doc.version == 2
	assert doc.text == 'fn main() return\n'
}

fn test_did_change_for_an_unopened_buffer_is_counted_not_answered() {
	sink, mut s := sync_server()
	body := '{"textDocument":{"uri":"file:///tmp/proj/gone.v","version":2},"contentChanges":[{"text":"x"}]}'
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didChange","params":${body}}'))
	assert s.sync_refusals == 1
	// a notification has nowhere to put a reply.
	assert sink.messages.len == 0
}

fn test_did_close_empties_the_store() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'x')))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didClose","params":' +
		'{"textDocument":{"uri":"file:///tmp/proj/a.v"}}}'))
	assert s.documents.count() == 0
	assert s.open_documents().len == 0
}

fn test_did_save_records_the_text_when_the_client_sends_it() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'one')))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didSave","params":' +
		'{"textDocument":{"uri":"file:///tmp/proj/a.v"},"text":"two"}}'))
	doc := s.document('file:///tmp/proj/a.v') or { panic('the buffer is missing') }
	assert doc.text == 'two'
}

fn test_did_save_without_text_keeps_the_buffer() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'one')))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didSave","params":' +
		'{"textDocument":{"uri":"file:///tmp/proj/a.v"}}}'))
	doc := s.document('file:///tmp/proj/a.v') or { panic('the buffer is missing') }
	assert doc.text == 'one'
}

fn test_did_change_configuration_stores_the_settings() {
	_, mut s := sync_server()
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration",' +
		'"params":{"settings":{"visor":{"trace":"off"}}}}'))
	settings := as_object(s.configuration()) or { panic('settings is not an object') }
	assert 'visor' in settings
}

fn test_workspace_folders_can_be_added_and_removed() {
	_, mut s := sync_server()
	assert s.workspace_folders.len == 1
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeWorkspaceFolders",' +
		'"params":{"event":{"added":[{"uri":"file:///tmp/other","name":"other"}],"removed":[]}}}'))
	assert s.workspace_folders.len == 2
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeWorkspaceFolders",' +
		'"params":{"event":{"added":[],"removed":[{"uri":"file:///tmp/proj","name":"proj"}]}}}'))
	assert s.workspace_folders.len == 1
	assert s.workspace_folders[0].uri == 'file:///tmp/other'
	// adding a folder that is already a root does not duplicate it.
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeWorkspaceFolders",' +
		'"params":{"event":{"added":[{"uri":"file:///tmp/other"}],"removed":[]}}}'))
	assert s.workspace_folders.len == 1
}

fn test_a_full_text_change_still_lands() {
	_, mut s := sync_server()
	s.serve_message(parse_message(open_body('file:///tmp/proj/a.v', 1, 'one')))
	// incremental sync does not forbid a whole-document replacement, and a
	// client that lost track sends exactly that.
	body := '{"textDocument":{"uri":"file:///tmp/proj/a.v","version":2},"contentChanges":[{"text":"two"}]}'
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didChange","params":${body}}'))
	doc := s.document('file:///tmp/proj/a.v') or { panic('the buffer is missing') }
	assert doc.text == 'two'
}
