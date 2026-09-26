module lsp

import features
import json2

// The token types Neovim lists, in the order it lists them. The legend is built
// from this list, so what these tests pin is the order the server declares its
// own types in and the indices that come out of it.
const nvim_types = '["namespace","type","class","enum","interface","struct","typeParameter",' +
	'"parameter","variable","property","enumMember","event","function","method","macro",' +
	'"keyword","modifier","comment","string","number","regexp","operator","decorator"]'

const nvim_modifiers = '["declaration","definition","readonly","static","deprecated","abstract",' +
	'"async","modification","documentation","defaultLibrary"]'

// A client that offers semantic tokens, which is the shape Neovim sends.
const tokens_client = '{"textDocument":{"synchronization":{"dynamicRegistration":true},' +
	'"semanticTokens":{"dynamicRegistration":false,"requests":{"range":true,"full":{"delta":true}},' +
	'"tokenTypes":${nvim_types},"tokenModifiers":${nvim_modifiers},"formats":["relative"]}}}'

// Two tokens on one line and one on the next, with a declaration in it.
const sample_text = '// hi\nfn main() {}\n'

// A block comment, which the grammar reports as one token spanning two lines.
const multiline_text = '/* a\nb */\nfn main() {}\n'

// The indices the legend puts these kinds at, spelled out so a reordering of
// features.token_kinds fails here instead of silently recolouring a client.
const index_comment = 17
const index_keyword = 13
const index_function = 10

fn tokens_client_for(client_capabilities string) ClientCapabilities {
	body := '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":${client_capabilities}}}'
	params := parse_message(body).params
	object := as_object(params) or { panic('params is not an object') }
	values := object['capabilities'] or { panic('no capabilities in the request') }
	return new_client_capabilities(values)
}

// token_session is a session with the token provider negotiated and one buffer
// open, which is what a client has when it asks for tokens.
fn token_session(text string, client_capabilities string) (&BufferSink, &Server) {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.set_version('0.0.1')
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${client_capabilities}}}'))
	s.serve_message(parse_message('{"jsonrpc":"2.0","method":"initialized","params":{}}'))
	open_buffer(mut s, 'file:///tmp/tokens.v', text)
	return sink, s
}

// open_buffer sends the didOpen a client sends before it asks about a buffer.
fn open_buffer(mut s Server, uri string, text string) {
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

fn ask_for_tokens(mut s Server, uri string) {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":9,' +
		'"method":"textDocument/semanticTokens/full","params":${json2.encode(json2.Any(params))}}'))
}

// data_of reads the token data out of a reply, failing on the part that was
// wrong rather than on an index.
fn data_of(reply Message) []json2.Any {
	result := as_object(reply.result) or { panic('the result is not an object') }
	return as_array(result['data'] or { panic('no data in the result') }) or {
		panic('data is not an array')
	}
}

fn int_at(data []json2.Any, index int) int {
	if index >= data.len {
		panic('the encoding stopped after ${data.len} integers')
	}
	return data[index].int()
}

fn test_the_legend_is_the_types_the_client_offered() {
	legend := new_semantic_legend(tokens_client_for(tokens_client))
	assert legend.token_types == features.token_kinds
	assert legend.token_modifiers == features.modifier_names
}

fn test_a_type_the_client_cannot_draw_falls_back() {
	// no struct, enum, interface or typeParameter, which some clients leave out
	thin := '{"textDocument":{"semanticTokens":{"tokenTypes":["type","keyword","comment"],' +
		'"tokenModifiers":["declaration"]}}}'
	legend := new_semantic_legend(tokens_client_for(thin))
	assert legend.index_of('struct') == legend.index_of('type')
	assert legend.index_of('enumMember') == -1
	assert legend.index_of('comment') == 2
}

fn test_a_type_with_no_rendering_is_dropped() {
	legend := new_semantic_legend(tokens_client_for('{"textDocument":{"semanticTokens":' +
		'{"tokenTypes":["comment"],"tokenModifiers":[]}}}'))
	assert legend.index_of('comment') == 0
	// nothing close enough to keyword exists in that legend, and an index that
	// is not in it would be drawn as whatever sits at that number
	assert legend.index_of('keyword') == -1
}

fn test_modifiers_become_bits_in_the_order_the_client_listed_them() {
	legend := new_semantic_legend(tokens_client_for(tokens_client))
	assert legend.modifier_mask([features.modifier_declaration, features.modifier_readonly]) == 3
	// a modifier the client did not list is dropped rather than shifted in
	one := new_semantic_legend(tokens_client_for('{"textDocument":{"semanticTokens":' +
		'{"tokenTypes":["keyword"],"tokenModifiers":["readonly"]}}}'))
	assert one.modifier_mask([features.modifier_declaration, features.modifier_readonly]) == 1
}

fn test_the_provider_carries_the_legend_it_will_use() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.serve_message(parse_message('{"jsonrpc":"2.0","id":1,"method":"initialize","params":' +
		'{"capabilities":${tokens_client}}}'))
	reply := sink.last_message()
	assert reply.kind == .response
	result := as_object(reply.result) or { panic('the initialize result is not an object') }
	capabilities := as_object(result['capabilities'] or { panic('no capabilities') }) or {
		panic('capabilities is not an object')
	}
	provider := as_object(capabilities['semanticTokensProvider'] or {
		panic('semantic tokens were not advertised')
	}) or { panic('the provider is not an object') }
	legend := as_object(provider['legend'] or { panic('the provider has no legend') }) or {
		panic('the legend is not an object')
	}
	types := as_array(legend['tokenTypes'] or { panic('no tokenTypes') }) or {
		panic('tokenTypes is not an array')
	}
	assert types.len == features.token_kinds.len
	assert types[0].str() == 'namespace'
	modifiers := as_array(legend['tokenModifiers'] or { panic('no tokenModifiers') }) or {
		panic('tokenModifiers is not an array')
	}
	assert modifiers.len == features.modifier_names.len
	assert (provider['full'] or { panic('no full flag') }).bool()
	// range requests are refused rather than answered badly
	assert !(provider['range'] or { panic('no range flag') }).bool()
}

fn test_tokens_come_back_delta_encoded() {
	mut sink, mut s := token_session(sample_text, tokens_client)
	ask_for_tokens(mut s, 'file:///tmp/tokens.v')
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	data := data_of(reply)
	assert data.len == 15
	// the comment on line 0, five characters wide
	assert int_at(data, 0) == 0 // line delta
	assert int_at(data, 1) == 0 // character delta
	assert int_at(data, 2) == 5 // length
	assert int_at(data, 3) == index_comment
	assert int_at(data, 4) == 0 // no modifiers
	// fn on line 1, which makes the line delta 1 and the character absolute
	assert int_at(data, 5) == 1
	assert int_at(data, 6) == 0
	assert int_at(data, 7) == 2
	assert int_at(data, 8) == index_keyword
	// main three characters into that same line, so the delta is relative
	// against the token before it
	assert int_at(data, 10) == 0
	assert int_at(data, 11) == 3
	assert int_at(data, 12) == 4
	assert int_at(data, 13) == index_function
	assert int_at(data, 14) == 1 // declaration
}

fn test_a_token_that_crosses_a_line_is_sent_once_per_line() {
	mut sink, mut s := token_session(multiline_text, tokens_client)
	ask_for_tokens(mut s, 'file:///tmp/tokens.v')
	data := data_of(sink.last_message())
	// two lines of comment and then fn and main: four tokens, one per line
	assert data.len == 20
	// first line of the comment
	assert int_at(data, 0) == 0
	assert int_at(data, 2) == 4
	assert int_at(data, 3) == index_comment
	// second line: a new line, so the character counts from the line start
	assert int_at(data, 5) == 1
	assert int_at(data, 6) == 0
	assert int_at(data, 7) == 4
	assert int_at(data, 8) == index_comment
	// then fn and main on the third line
	assert int_at(data, 10) == 1
	assert int_at(data, 11) == 0
	assert int_at(data, 13) == index_keyword
	assert int_at(data, 18) == index_function
}

fn test_a_kind_the_client_cannot_draw_is_left_out_of_the_answer() {
	caps := '{"textDocument":{"semanticTokens":{"tokenTypes":["comment"],' +
		'"tokenModifiers":["declaration"]}}}'
	mut sink, mut s := token_session('fn main() {}\n// hi\n', caps)
	ask_for_tokens(mut s, 'file:///tmp/tokens.v')
	data := data_of(sink.last_message())
	// the keyword and the function name have no type in that legend, so only the
	// comment is sent, and it starts on line 1
	assert data.len == 5
	assert int_at(data, 0) == 1
	assert int_at(data, 1) == 0
	assert int_at(data, 2) == 5
	assert int_at(data, 3) == 0
}

fn test_a_buffer_that_is_not_open_is_an_error() {
	mut sink, mut s := token_session(sample_text, tokens_client)
	ask_for_tokens(mut s, 'file:///tmp/somewhere_else.v')
	reply := sink.last_message()
	assert reply.error_code == code_invalid_params
	assert reply.error_text.contains('no open document')
}

fn test_a_client_with_no_token_type_gets_an_error_rather_than_nothing() {
	// an empty legend means every token would have to be dropped, and an empty
	// answer would read as a file with nothing in it to colour
	caps := '{"textDocument":{"synchronization":{},"semanticTokens":{"tokenTypes":[],"tokenModifiers":[]}}}'
	mut sink, mut s := token_session(sample_text, caps)
	ask_for_tokens(mut s, 'file:///tmp/tokens.v')
	reply := sink.last_message()
	assert reply.error_code == code_request_failed
	assert reply.error_text.contains('no token type this server emits')
}

fn test_a_buffer_with_nothing_in_it_answers_with_no_tokens() {
	mut sink, mut s := token_session('', tokens_client)
	ask_for_tokens(mut s, 'file:///tmp/tokens.v')
	reply := sink.last_message()
	assert reply.kind == .response, reply.error_text
	assert data_of(reply).len == 0
}
