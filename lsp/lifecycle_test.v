module lsp

// The capability set a client sends in initialize. The two shapes are the ones
// the negotiation tests use: a client that offers everything this build acts on,
// and one that offers synchronization only.
const asks_for_everything = '{"workspace":{"workspaceFolders":true,"configuration":true},' +
	'"textDocument":{"synchronization":{},"diagnostic":{},"formatting":{}},' +
	'"window":{"workDoneProgress":true}}'
const asks_for_sync_only = '{"textDocument":{"synchronization":{}}}'

fn initialized_server(client_capabilities string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"processId":null,"clientInfo":{"name":"test-editor","version":"1.0"},' +
		'"workspaceFolders":[{"uri":"file:///tmp/proj","name":"proj"}],' +
		'"capabilities":${client_capabilities}}}'))
	return sink, s
}

fn test_initialize_answers_with_capabilities_built_from_the_client() {
	sink, s := initialized_server(asks_for_everything)
	assert s.session_state() == .initialized
	reply := sink.last_message()
	assert reply.kind == .response
	assert reply.id_key() == 'n:1'
	result := as_object(reply.result) or { panic('result is not an object') }
	caps := as_object(result['capabilities'] or { panic('no capabilities') }) or {
		panic('capabilities is not an object')
	}
	assert 'workspace' in caps
	// Both providers this build serves are probe-gated, and this session never
	// probed a compiler, so neither is offered. The pair below is the other
	// half of that: the same client, with the probe.
	assert 'diagnosticProvider' !in caps
	assert 'documentFormattingProvider' !in caps
	assert 'textDocumentSync' in caps
	info := as_object(result['serverInfo'] or { panic('no serverInfo') }) or {
		panic('serverInfo is not an object')
	}
	assert (info['name'] or { panic('no name') }).str() == server_name
	assert (info['version'] or { panic('no version') }).str() == '0.0.1'
	// the client's own name is kept, since a support question starts with which
	// editor is on the other end.
	assert s.client_name == 'test-editor'
}

fn test_a_client_that_offers_less_gets_a_smaller_capability_set() {
	_, thin := initialized_server(asks_for_sync_only)
	rich_sink, rich := initialized_server(asks_for_everything)
	_ = rich_sink
	full := negotiate(rich.client_announced(), none).capabilities
	small := negotiate(thin.client_announced(), none).capabilities
	assert full.len > small.len
	assert 'workspace' !in small
	assert 'workspace' in full
}

fn test_initialize_advertises_a_provider_only_once_a_compiler_is_probed() {
	// The negotiation reads the probe rather than the compiler's path, so a
	// server that never probed has no formatting and no diagnostics to offer.
	// This is the pair: the same client and the same fixture, without the probe
	// and with it.
	unprobed_sink, unprobed := initialized_server(asks_for_everything)
	_ = unprobed_sink
	unprobed_caps := negotiate(unprobed.client_announced(), none).capabilities
	assert 'documentFormattingProvider' !in unprobed_caps
	// the fixture's client offers the pull request, so the provider would be
	// advertised if there were a compiler behind it.
	assert 'diagnosticProvider' !in unprobed_caps

	mut probed_sink := &BufferSink{}
	mut probed := new_server(probed_sink)
	probed.probe_compiler()
	probed.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${asks_for_everything}}}'))
	result := as_object(probed_sink.last_message().result) or { panic('no result') }
	caps := as_object(result['capabilities'] or { panic('no capabilities') }) or {
		panic('capabilities is not an object')
	}
	assert 'documentFormattingProvider' in caps
	assert 'diagnosticProvider' in caps
}

fn test_the_negotiation_notes_are_kept_for_the_log() {
	_, s := initialized_server(asks_for_sync_only)
	notes := s.notes()
	assert notes.len > 0
	mut saw_sync := false
	for note in notes {
		if note.starts_with('textDocumentSync:') {
			saw_sync = true
		}
	}
	assert saw_sync
}

fn test_a_request_before_initialize_is_refused() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":5,"method":"textDocument/hover"}'))
	reply := sink.last_message()
	assert reply.error_code == code_server_not_initialized
	assert reply.id_key() == 'n:5'
}

fn test_a_notification_before_initialize_is_dropped() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{}}'))
	assert sink.messages.len == 0
}

fn test_initialize_twice_is_an_invalid_request() {
	sink, mut s := initialized_server(asks_for_sync_only)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"capabilities":{}}}'))
	reply := sink.last_message()
	assert reply.error_code == code_invalid_request
	assert s.session_state() == .initialized
}

fn test_initialized_marks_the_client_ready() {
	_, mut s := initialized_server(asks_for_sync_only)
	assert !s.is_ready()
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	assert s.is_ready()
}

fn test_workspace_folders_are_taken_from_the_initialize_params() {
	_, s := initialized_server(asks_for_sync_only)
	assert s.workspace_folders.len == 1
	assert s.workspace_folders[0].uri == 'file:///tmp/proj'
	assert s.workspace_folders[0].name == 'proj'
}

fn test_a_client_that_sends_only_root_uri_still_gets_a_root() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"rootUri":"file:///tmp/old","capabilities":{}}}'))
	assert s.workspace_folders.len == 1
	assert s.workspace_folders[0].uri == 'file:///tmp/old'
}

fn test_shutdown_then_exit_leaves_the_clean_code() {
	sink, mut s := initialized_server(asks_for_sync_only)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":2,"method":"shutdown"}'))
	assert s.session_state() == .shutting_down
	reply := sink.last_message()
	assert reply.kind == .response
	assert !reply.failed()
	assert s.code_on_exit() == 1
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"exit"}'))
	assert s.wants_exit()
	assert s.code_on_exit() == 0
}

fn test_exit_without_shutdown_leaves_the_failure_code() {
	_, mut s := initialized_server(asks_for_sync_only)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"exit"}'))
	assert s.wants_exit()
	assert s.code_on_exit() == 1
}

fn test_exit_before_initialize_is_also_a_failure() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"exit"}'))
	assert s.wants_exit()
	assert s.code_on_exit() == 1
}

fn test_a_request_after_shutdown_is_refused() {
	sink, mut s := initialized_server(asks_for_sync_only)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":2,"method":"shutdown"}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":3,"method":"textDocument/hover"}'))
	reply := sink.last_message()
	assert reply.error_code == code_invalid_request
	assert reply.id_key() == 'n:3'
}

fn test_shutdown_before_initialize_is_refused() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":2,"method":"shutdown"}'))
	reply := sink.last_message()
	// the phase guard answers first, and naming the missing initialize is more
	// use than naming the request that arrived too early.
	assert reply.error_code == code_server_not_initialized
	assert s.session_state() == .uninitialized
}

fn test_a_pull_for_a_buffer_that_is_not_open_is_invalid_params() {
	// The stub that used to answer here is gone: the method is served now, and
	// what a request for an unopened buffer gets is a reason rather than an
	// empty list. The lane's own tests carry the rest of this.
	sink, mut s := initialized_server(asks_for_everything)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,"method":"textDocument/diagnostic",' +
		'"params":{"textDocument":{"uri":"file:///tmp/proj/a.v"}}}'))
	reply := sink.last_message()
	assert reply.error_code == code_invalid_params
	assert reply.error_text.contains('no open document')
}

fn test_initialize_without_params_is_an_invalid_params_error() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize"}'))
	reply := sink.last_message()
	assert reply.error_code == code_invalid_params
	assert s.session_state() == .uninitialized
}
