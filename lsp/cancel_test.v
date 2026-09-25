module lsp

import json2

fn cancel_server() (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":100,"method":"initialize","params":' +
		'{"capabilities":{"textDocument":{"synchronization":{}}}}}'))
	s.on('visor/echo', echo_handler)
	sink.messages = []
	s.requests_answered = 0
	return sink, s
}

fn echo_handler(mut _ Server, _ Message) Reply {
	return ok(json2.Any('echoed'))
}

fn frame(body string) Frame {
	return Frame{
		kind: .message
		body: body
	}
}

fn test_a_cancel_that_travels_with_its_request_stops_the_response() {
	sink, mut s := cancel_server()
	// one batch, the way a single write to the pipe arrives.
	s.serve_batch([
		frame('{"jsonrpc":"2.0","id":1,"method":"visor/echo"}'),
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}'),
	])
	assert sink.messages.len == 0
	assert s.cancelled_count() == 1
	assert s.cancel.marks == 1
	assert s.cancel.applied == 1
}

fn test_a_cancel_without_its_request_leaves_the_id_clean_for_a_later_one() {
	sink, mut s := cancel_server()
	s.serve_batch([
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":7}}'),
	])
	assert sink.messages.len == 0
	// the mark is still waiting: nothing has used id 7 yet.
	assert s.cancel.pending() == 1
	s.serve_batch([
		frame('{"jsonrpc":"2.0","id":7,"method":"visor/echo"}'),
	])
	assert sink.messages.len == 0
	assert s.cancel.pending() == 0
}

fn test_a_cancelled_id_does_not_take_the_next_request_with_it() {
	sink, mut s := cancel_server()
	s.serve_batch([
		frame('{"jsonrpc":"2.0","id":1,"method":"visor/echo"}'),
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}'),
		frame('{"jsonrpc":"2.0","id":2,"method":"visor/echo"}'),
	])
	// only the cancelled one is missing.
	assert sink.messages.len == 1
	reply := sink.last_message()
	assert reply.id_key() == 'n:2'
	assert !reply.failed()
}

fn test_a_string_id_and_an_integer_id_are_cancelled_separately() {
	sink, mut s := cancel_server()
	s.serve_batch([
		frame('{"jsonrpc":"2.0","id":"1","method":"visor/echo"}'),
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}'),
	])
	// the cancellation was for the integer 1; the string id "1" still answers.
	assert sink.messages.len == 1
	assert sink.last_message().id_key() == 's:1'
	assert s.cancel.pending() == 1
}

fn test_a_cancel_for_an_id_already_answered_is_kept_as_a_mark_and_nothing_else() {
	sink, mut s := cancel_server()
	s.serve_batch([
		frame('{"jsonrpc":"2.0","id":4,"method":"visor/echo"}'),
	])
	assert sink.messages.len == 1
	s.serve_batch([
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":4}}'),
	])
	// the answer is out and the late cancellation cannot recall it.
	assert sink.messages.len == 1
	assert s.cancel.marks == 1
	assert s.cancel.applied == 0
}

fn test_a_cancel_without_an_id_is_dropped() {
	_, mut s := cancel_server()
	s.serve_batch([
		frame('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{}}'),
	])
	assert s.cancel.dropped == 1
	assert s.cancel.pending() == 0
}

fn test_the_registry_does_not_grow_without_bound() {
	mut registry := CancelRegistry{}
	for i in 0 .. max_pending_cancels + 40 {
		registry.mark(json2.Any(i))
	}
	assert registry.pending() == max_pending_cancels
	assert registry.dropped == 40
	// a re-mark of an id already in the table is still accepted.
	assert registry.mark(json2.Any(0))
}
