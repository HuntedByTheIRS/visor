module lsp

import json2

fn handler_echo(mut _ Server, req Message) Reply {
	return ok(json2.Any('echoed ${req.method}'))
}

fn handler_fails(mut _ Server, _ Message) Reply {
	return fail(code_internal_error, 'the handler gave up')
}

// server_ready_for_requests returns a session past initialize, with the sink
// emptied of the handshake, because the router only runs once a session is
// open.
fn server_ready_for_requests() (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":100,"method":"initialize","params":' +
		'{"capabilities":{"textDocument":{"synchronization":{}}}}}'))
	sink.messages = []
	// the handshake is not what these tests count.
	s.requests_answered = 0
	s.notifications_handled = 0
	return sink, s
}

fn test_routes_a_request_to_its_handler() {
	sink, mut s := server_ready_for_requests()
	s.on('visor/echo', handler_echo)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"visor/echo"}'))
	assert sink.messages.len == 1
	m := sink.last_message()
	assert m.kind == .response
	assert m.id_key() == 'n:1'
	assert m.result.str() == 'echoed visor/echo'
	assert s.requests_answered == 1
}

fn test_unknown_method_is_method_not_found() {
	sink, mut s := server_ready_for_requests()
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":2,"method":"textDocument/hover"}'))
	assert sink.messages.len == 1
	m := sink.last_message()
	assert m.error_code == code_method_not_found
	assert m.error_text.contains('textDocument/hover')
}

fn test_a_stub_answers_with_a_request_failed_and_names_the_owner() {
	sink, mut s := server_ready_for_requests()
	s.stub('textDocument/diagnostic', 'the diag lane')
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":3,"method":"textDocument/diagnostic"}'))
	m := sink.last_message()
	// a stub is an error, not an empty success: the editor has to be able to
	// tell that the answer did not come from a working feature.
	assert m.error_code == code_request_failed
	assert m.error_text.contains('not implemented')
	assert m.error_text.contains('the diag lane')
}

fn test_a_handler_error_keeps_the_client_id() {
	sink, mut s := server_ready_for_requests()
	s.on('visor/fail', handler_fails)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":"abc","method":"visor/fail"}'))
	m := sink.last_message()
	assert m.error_code == code_internal_error
	assert m.id_key() == 's:abc'
	assert m.error_text == 'the handler gave up'
}

fn test_a_notification_is_handled_without_a_reply() {
	sink, mut s := server_ready_for_requests()
	s.on('visor/note', handler_echo)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"visor/note"}'))
	assert sink.messages.len == 0
	assert s.notifications_handled == 1
}

fn test_a_notification_for_an_unknown_method_is_ignored() {
	sink, mut s := server_ready_for_requests()
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"textDocument/willSave"}'))
	assert sink.messages.len == 0
}

fn test_a_body_that_is_not_json_gets_a_parse_error() {
	sink, mut s := server_ready_for_requests()
	s.serve_batch([
		Frame{
			kind: .message
			body: '{not json'
		},
	])
	m := sink.last_message()
	assert m.error_code == code_parse_error
	// JSON-RPC answers an unparsable body with a null id, since there is no
	// request to name.
	assert m.id_key() == ''
}

fn test_a_routable_body_without_a_method_gets_an_invalid_request() {
	sink, mut s := server_ready_for_requests()
	s.serve_batch([
		Frame{
			kind: .message
			body: '{"jsonrpc":"2.0"}'
		},
	])
	m := sink.last_message()
	assert m.error_code == code_invalid_request
}

fn test_a_malformed_frame_is_counted_and_skipped() {
	sink, mut s := server_ready_for_requests()
	s.on('visor/echo', handler_echo)
	s.serve_batch([
		Frame{
			kind:   .malformed
			reason: 'header block without a usable Content-Length'
		},
		Frame{
			kind: .message
			body: '{"jsonrpc":"2.0","id":4,"method":"visor/echo"}'
		},
	])
	// the bad frame is recorded, and the good frame behind it still runs.
	assert s.refused_frames == 1
	assert sink.messages.len == 1
	assert sink.last_message().id_key() == 'n:4'
}

fn test_a_lane_can_replace_a_stub() {
	_, mut s := server_ready_for_requests()
	s.stub('visor/echo', 'nobody')
	assert s.router.knows('visor/echo')
	s.on('visor/echo', handler_echo)
	assert !s.router.is_stub('visor/echo')
}
