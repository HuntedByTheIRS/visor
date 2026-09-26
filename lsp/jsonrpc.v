module lsp

import json2

// Errors LSP 3.17 names. The transport needs its own four for frames that never
// became a usable message; the rest are the ones a language server actually
// sends.
pub const code_parse_error = -32700
pub const code_invalid_request = -32600
pub const code_method_not_found = -32601
pub const code_invalid_params = -32602
pub const code_internal_error = -32603
pub const code_server_not_initialized = -32002
pub const code_request_cancelled = -32800
pub const code_content_modified = -32801
pub const code_request_failed = -32803

pub const jsonrpc_version = '2.0'

pub enum MessageKind {
	request
	notification
	response
	// invalid is a message the server could not use. It carries a reason and no
	// id, because a body that did not parse has nowhere to send an answer.
	invalid
}

pub struct Message {
pub:
	kind   MessageKind
	id     json2.Any
	method string
	params json2.Any
	// result belongs to a response the server received for a request it sent.
	result json2.Any
	// error_code is 0 on a message without an error. LSP never uses 0 as an
	// error code, so it doubles as the "no error" marker.
	error_code int
	error_text string
	// reason says why a message is invalid.
	reason string
	// invalid_code is the JSON-RPC error an invalid message is answered with. A
	// body that did not parse is a parse error; a body that parsed but had
	// nothing to route is an invalid request.
	invalid_code int
}

// failed reports whether this message carries an error.
pub fn (m &Message) failed() bool {
	return m.error_code != 0
}

// id_key is the map key for this message's id.
pub fn (m &Message) id_key() string {
	return id_key(m.id)
}

// null_value returns a JSON null as a json2.Any.
pub fn null_value() json2.Any {
	return json2.Any(json2.Null{})
}

// id_key normalises a request id into a map key. An integer 3 and a string "3"
// are different ids to the client, so they get different keys: a cancellation
// aimed at one of them must not land on the other.
pub fn id_key(id json2.Any) string {
	if id is json2.Null {
		return ''
	}
	if id is []json2.Any {
		// an unset json2.Any holds the first member of the sum type, an empty
		// array. Nothing about a request id looks like that, so it means unset.
		if (id as []json2.Any).len == 0 {
			return ''
		}
		return 'x:${id}'
	}
	if id is string {
		return 's:${id as string}'
	}
	if id is f64 {
		f := id as f64
		i := i64(f)
		if f64(i) == f {
			return 'n:${i}'
		}
		return 'n:${f}'
	}
	if id is int {
		return 'n:${id as int}'
	}
	if id is i64 {
		return 'n:${id as i64}'
	}
	return 'x:${id}'
}

// parse_message turns a frame body into a Message. It never fails: a body that
// cannot be used comes back as MessageKind.invalid with the reason set.
pub fn parse_message(body string) Message {
	if body == '' {
		return Message{
			kind:         .invalid
			reason:       'empty frame body'
			invalid_code: code_parse_error
		}
	}
	decoded := json2.decode[map[string]json2.Any](body) or {
		return Message{
			kind:         .invalid
			reason:       'frame body is not a JSON object'
			invalid_code: code_parse_error
		}
	}
	version := decoded['jsonrpc'] or { null_value() }
	if version !is string || (version as string) != jsonrpc_version {
		return Message{
			kind:         .invalid
			reason:       'frame body does not declare jsonrpc ${jsonrpc_version}'
			invalid_code: code_invalid_request
		}
	}
	id := decoded['id'] or { null_value() }
	if method := decoded['method'] {
		if method !is string {
			return Message{
				kind:         .invalid
				reason:       'method is not a string'
				invalid_code: code_invalid_request
			}
		}
		name := method as string
		if name == '' {
			return Message{
				kind:         .invalid
				reason:       'method is empty'
				invalid_code: code_invalid_request
			}
		}
		params := decoded['params'] or { null_value() }
		if id is json2.Null {
			// A null id cannot be answered: nothing in the response would match
			// it. Treating it as a notification is what every editor expects,
			// because that is how they spell "no reply wanted".
			return Message{
				kind:   .notification
				id:     id
				method: name
				params: params
			}
		}
		return Message{
			kind:   .request
			id:     id
			method: name
			params: params
		}
	}
	if error_body := decoded['error'] {
		mut code := 0
		mut text := ''
		if error_body is map[string]json2.Any {
			err_obj := error_body as map[string]json2.Any
			if c := err_obj['code'] {
				code = c.int()
			}
			if t := err_obj['message'] {
				text = t.str()
			}
		}
		return Message{
			kind:       .response
			id:         id
			error_code: code
			error_text: text
		}
	}
	if result := decoded['result'] {
		return Message{
			kind:   .response
			id:     id
			result: result
		}
	}
	return Message{
		kind:         .invalid
		reason:       'frame body is neither a request, a notification nor a response'
		invalid_code: code_invalid_request
	}
}

// as_object reads a JSON object out of a value, for the many places the
// protocol nests one.
pub fn as_object(value json2.Any) ?map[string]json2.Any {
	if value is map[string]json2.Any {
		return value as map[string]json2.Any
	}
	return none
}

// as_array reads a JSON array out of a value.
pub fn as_array(value json2.Any) ?[]json2.Any {
	if value is []json2.Any {
		return value as []json2.Any
	}
	return none
}

// encode_result builds a successful JSON-RPC response for the given id.
pub fn encode_result(id json2.Any, result json2.Any) string {
	mut out := map[string]json2.Any{}
	out['jsonrpc'] = json2.Any(jsonrpc_version)
	out['id'] = id
	out['result'] = result
	return json2.encode(out)
}

// encode_error builds a JSON-RPC error response for the given id.
pub fn encode_error(id json2.Any, code int, message string) string {
	mut body := map[string]json2.Any{}
	body['code'] = json2.Any(code)
	body['message'] = json2.Any(message)
	mut out := map[string]json2.Any{}
	out['jsonrpc'] = json2.Any(jsonrpc_version)
	out['id'] = id
	out['error'] = json2.Any(body)
	return json2.encode(out)
}

// encode_request builds a JSON-RPC request frame.
pub fn encode_request(id int, method string, params json2.Any) string {
	mut out := map[string]json2.Any{}
	out['jsonrpc'] = json2.Any(jsonrpc_version)
	out['id'] = json2.Any(id)
	out['method'] = json2.Any(method)
	out['params'] = params
	return json2.encode(out)
}

// encode_notification builds a JSON-RPC notification, leaving out null params.
pub fn encode_notification(method string, params json2.Any) string {
	mut out := map[string]json2.Any{}
	out['jsonrpc'] = json2.Any(jsonrpc_version)
	out['method'] = json2.Any(method)
	if params !is json2.Null {
		out['params'] = params
	}
	return json2.encode(out)
}
