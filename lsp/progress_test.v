module lsp

import json2

// progress_server is a session whose client advertised work-done progress and
// the configuration pull, with the handshake taken out of the sink.
fn progress_server(client_capabilities string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":100,"method":"initialize","params":' +
		'{"capabilities":${client_capabilities}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	sink.messages = []
	return sink, s
}

const progress_client = '{"window":{"workDoneProgress":true},"workspace":{"configuration":true}}'
const quiet_client = '{"textDocument":{"synchronization":{}}}'

fn progress_value(m Message) map[string]json2.Any {
	body := as_object(m.params) or { panic('progress params is not an object') }
	return as_object(body['value'] or { panic('no value') }) or { panic('value is not an object') }
}

fn test_begin_asks_the_client_to_create_the_token_first() {
	sink, mut s := progress_server(progress_client)
	assert s.progress_begin('indexing', 'Indexing the module')
	assert sink.messages.len == 1
	request := sink.last_message()
	assert request.kind == .request
	assert request.method == 'window/workDoneProgress/create'
	params := as_object(request.params) or { panic('params is not an object') }
	assert (params['token'] or { panic('no token') }).str() == 'indexing'
	// nothing has been reported yet: the token does not exist until the client
	// says it does.
	assert s.progress.begun == 0
	assert !s.progress_open('indexing')
	assert s.outstanding_requests() == 1
}

fn test_the_begin_report_follows_the_clients_answer() {
	sink, mut s := progress_server(progress_client)
	s.progress_begin('indexing', 'Indexing the module')
	id := sink.last_message().id
	s.serve_message(parse_message(encode_result(id, null_value())))
	assert s.progress.begun == 1
	assert s.progress_open('indexing')
	assert s.outstanding_requests() == 0
	report := sink.last_message()
	assert report.kind == .notification
	assert report.method == '$/progress'
	body := as_object(report.params) or { panic('params is not an object') }
	assert (body['token'] or { panic('no token') }).str() == 'indexing'
	value := progress_value(report)
	assert (value['kind'] or { panic('no kind') }).str() == 'begin'
	assert (value['title'] or { panic('no title') }).str() == 'Indexing the module'
	assert (value['cancellable'] or { panic('no cancellable') }) is bool
}

fn test_reports_and_the_end_go_out_for_an_open_token() {
	sink, mut s := progress_server(progress_client)
	s.progress_begin('indexing', 'Indexing')
	s.serve_message(parse_message(encode_result(sink.last_message().id, null_value())))
	assert s.progress_report('indexing', 'half way', 50)
	value := progress_value(sink.last_message())
	assert (value['kind'] or { panic('no kind') }).str() == 'report'
	assert (value['message'] or { panic('no message') }).str() == 'half way'
	assert (value['percentage'] or { panic('no percentage') }).int() == 50
	assert s.progress_end('indexing', 'done')
	last := progress_value(sink.last_message())
	assert (last['kind'] or { panic('no kind') }).str() == 'end'
	assert !s.progress_open('indexing')
	assert s.progress.ended == 1
	// a report after the end is a no-op, not a second begin.
	assert !s.progress_report('indexing', 'more', 60)
}

fn test_a_report_without_a_percentage_leaves_the_field_out() {
	sink, mut s := progress_server(progress_client)
	s.progress_begin('t', 'title')
	s.serve_message(parse_message(encode_result(sink.last_message().id, null_value())))
	s.progress_report('t', 'working', -1)
	value := progress_value(sink.last_message())
	assert 'percentage' !in value
}

fn test_a_client_that_did_not_advertise_progress_gets_no_traffic() {
	sink, mut s := progress_server(quiet_client)
	assert !s.progress_begin('indexing', 'Indexing')
	assert sink.messages.len == 0
	assert !s.progress_open('indexing')
}

fn test_a_token_the_client_declines_is_never_reported_on() {
	sink, mut s := progress_server(progress_client)
	s.progress_begin('indexing', 'Indexing')
	id := sink.last_message().id
	s.serve_message(parse_message(encode_error(id, code_request_failed, 'no progress here')))
	assert s.progress.declined == 1
	assert !s.progress_open('indexing')
	assert !s.progress_report('indexing', 'anything', 10)
	// the only message in the sink is the create request: no report went out for
	// a token the client refused.
	assert sink.messages.len == 1
}

fn test_a_response_the_server_never_asked_for_is_counted() {
	sink, mut s := progress_server(quiet_client)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":77,"result":null}'))
	assert s.unsolicited_responses == 1
	assert sink.messages.len == 0
}

fn test_the_configuration_pull_replaces_the_pushed_settings() {
	sink, mut s := progress_server(progress_client)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration",' +
		'"params":{"settings":{"visor":{"trace":"off"}}}}'))
	pull := sink.last_message()
	assert pull.kind == .request
	assert pull.method == 'workspace/configuration'
	params := as_object(pull.params) or { panic('params is not an object') }
	items := as_array(params['items'] or { panic('no items') }) or { panic('items is not an array') }
	assert items.len == 1
	mut section := map[string]json2.Any{}
	section['trace'] = json2.Any('messages')
	section['extra'] = json2.Any(true)
	answer := json2.Any([json2.Any(section)])
	s.serve_message(parse_message(encode_result(pull.id, answer)))
	settings := as_object(s.configuration()) or { panic('settings is not an object') }
	assert (settings['trace'] or { panic('no trace') }).str() == 'messages'
}

fn test_a_client_that_cannot_pull_keeps_the_pushed_settings() {
	sink, mut s := progress_server(quiet_client)
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"workspace/didChangeConfiguration",' +
		'"params":{"settings":{"visor":{"trace":"off"}}}}'))
	assert sink.messages.len == 0
	settings := as_object(s.configuration()) or { panic('settings is not an object') }
	assert 'visor' in settings
}
