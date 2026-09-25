module lsp

import json2

fn test_parses_a_request() {
	m := parse_message('{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"processId":null}}')
	assert m.kind == .request
	assert m.method == 'initialize'
	assert m.id_key() == 'n:3'
	assert m.params is map[string]json2.Any
	assert !m.failed()
}

fn test_parses_a_notification() {
	m := parse_message('{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"a":1}}')
	assert m.kind == .notification
	assert m.method == 'textDocument/didOpen'
	assert m.id is json2.Null
}

fn test_treats_a_null_id_as_a_notification() {
	// nothing in a reply would match a null id, so the message cannot be one
	// that wants an answer.
	m := parse_message('{"jsonrpc":"2.0","id":null,"method":"exit"}')
	assert m.kind == .notification
	assert m.method == 'exit'
}

fn test_parses_a_string_id() {
	m := parse_message('{"jsonrpc":"2.0","id":"abc-1","method":"shutdown"}')
	assert m.kind == .request
	assert m.id_key() == 's:abc-1'
	// an integer 1 and the string "1" are different ids.
	other := parse_message('{"jsonrpc":"2.0","id":1,"method":"shutdown"}')
	assert other.id_key() != m.id_key()
}

fn test_parses_a_response_with_an_error() {
	m := parse_message('{"jsonrpc":"2.0","id":9,"error":{"code":-32601,"message":"no such method"}}')
	assert m.kind == .response
	assert m.id_key() == 'n:9'
	assert m.failed()
	assert m.error_code == -32601
	assert m.error_text == 'no such method'
}

fn test_parses_a_response_with_a_result() {
	m := parse_message('{"jsonrpc":"2.0","id":9,"result":[1,2]}')
	assert m.kind == .response
	assert !m.failed()
	assert m.result is []json2.Any
	assert (m.result as []json2.Any).len == 2
}

fn test_refuses_a_body_that_is_not_json() {
	m := parse_message('{oops')
	assert m.kind == .invalid
	assert m.reason != ''
}

fn test_refuses_an_empty_body() {
	m := parse_message('')
	assert m.kind == .invalid
	assert m.reason.contains('empty')
}

fn test_refuses_a_wrong_jsonrpc_version() {
	m := parse_message('{"jsonrpc":"1.0","id":1,"method":"initialize"}')
	assert m.kind == .invalid
	assert m.reason.contains('jsonrpc')
}

fn test_refuses_a_non_string_method() {
	m := parse_message('{"jsonrpc":"2.0","id":1,"method":17}')
	assert m.kind == .invalid
	assert m.reason.contains('method')
}

fn test_refuses_a_body_with_nothing_to_route() {
	m := parse_message('{"jsonrpc":"2.0"}')
	assert m.kind == .invalid
	assert m.reason.contains('neither')
}

fn test_encode_result_round_trips() {
	out := encode_result(json2.Any(7), json2.Any('done'))
	m := parse_message(out)
	assert m.kind == .response
	assert m.id_key() == 'n:7'
	assert m.result.str() == 'done'
}

fn test_encode_error_round_trips() {
	out := encode_error(json2.Any(7), code_method_not_found, 'no such method')
	m := parse_message(out)
	assert m.failed()
	assert m.error_code == code_method_not_found
	assert m.error_text == 'no such method'
}

fn test_encode_notification_round_trips() {
	out := encode_notification('$/progress', json2.Any('x'))
	m := parse_message(out)
	assert m.kind == .notification
	assert m.method == '$/progress'
	assert m.params.str() == 'x'
	// a notification without params carries no params key at all.
	stripped := parse_message(encode_notification('exit', null_value()))
	assert stripped.params is json2.Null
}

fn test_encoded_text_escapes_a_document_body() {
	// a didChange carries real file text, newlines and quotes included. The
	// frame has to stay one line of JSON.
	text := 'fn main() {\n\tprintln("hi")\n}'
	mut change := map[string]json2.Any{}
	change['text'] = json2.Any(text)
	out := encode_notification('textDocument/didChange', json2.Any(change))
	assert !out.contains('\n')
	m := parse_message(out)
	body := as_object(m.params) or { map[string]json2.Any{} }
	got_text := body['text'] or { null_value() }
	assert got_text.str() == text
}

fn test_as_object_and_as_array_reject_the_other_shape() {
	not_an_object := as_object(json2.Any([]json2.Any{})) or { map[string]json2.Any{} }
	assert not_an_object.len == 0
	not_an_array := as_array(json2.Any('nope')) or { []json2.Any{} }
	assert not_an_array.len == 0
	mut obj := map[string]json2.Any{}
	obj['a'] = json2.Any(1)
	got := as_object(json2.Any(obj)) or { map[string]json2.Any{} }
	assert got.len == 1
}
