module lsp

import features
import json2

// The capability paths as the spec spells them. They are constants for the same
// reason the others are: a typo in one of these strings is silent, and the
// session would just decide the client has no semantic tokens.
const cap_semantic_tokens = 'textDocument.semanticTokens'
const cap_token_types = 'textDocument.semanticTokens.tokenTypes'
const cap_token_modifiers = 'textDocument.semanticTokens.tokenModifiers'
const cap_token_requests = 'textDocument.semanticTokens.requests'

// kind_fallbacks maps a token type onto the types worth trying when the client
// did not list it. A client that cannot draw `struct` still knows `type`, and an
// approximate colour reads better than a dropped one. A kind with no fallback
// here is dropped instead, because an index the client cannot render would be
// drawn as whatever type sits at that number.
const kind_fallbacks = {
	'struct':        ['type']
	'enum':          ['type']
	'interface':     ['type']
	'typeParameter': ['type']
	'enumMember':    ['property', 'variable']
	'decorator':     ['macro']
	'namespace':     ['type']
}

// SemanticLegend is the token types and modifiers this session may use, taken
// from what the client said it can draw.
pub struct SemanticLegend {
pub:
	token_types     []string
	token_modifiers []string
}

// new_semantic_legend builds the legend for one client. The server's kinds keep
// the order it declares them in, and a kind the client did not list stays out,
// so no index points at a type the client cannot draw.
pub fn new_semantic_legend(client ClientCapabilities) SemanticLegend {
	offered_types := client.strings(cap_token_types)
	offered_modifiers := client.strings(cap_token_modifiers)
	mut token_types := []string{cap: features.token_kinds.len}
	for kind in features.token_kinds {
		if kind in offered_types {
			token_types << kind
		}
	}
	mut token_modifiers := []string{cap: features.modifier_names.len}
	for name in features.modifier_names {
		if name in offered_modifiers {
			token_modifiers << name
		}
	}
	return SemanticLegend{
		token_types:     token_types
		token_modifiers: token_modifiers
	}
}

// enabled reports that the legend can carry a token at all.
pub fn (l &SemanticLegend) enabled() bool {
	return l.token_types.len > 0
}

// index_of returns the legend index for a token kind, or -1 when this client
// cannot draw it in any spelling.
pub fn (l &SemanticLegend) index_of(kind string) int {
	mut candidates := [kind]
	if fallbacks := kind_fallbacks[kind] {
		candidates << fallbacks
	}
	for candidate in candidates {
		index := l.token_types.index(candidate)
		if index >= 0 {
			return index
		}
	}
	return -1
}

// modifier_mask turns modifier names into the bit set the encoding carries. A
// modifier the client did not list is dropped rather than shifted in: the bits
// mean whatever the client's own list says they mean.
pub fn (l &SemanticLegend) modifier_mask(names []string) int {
	mut mask := 0
	for name in names {
		index := l.token_modifiers.index(name)
		if index >= 0 {
			mask |= 1 << index
		}
	}
	return mask
}

// full_tokens_wanted reports whether the client asked for whole-document
// requests. A client that sent no requests block is taken at its word, because
// whole-document tokens are the only kind this server has.
fn full_tokens_wanted(client ClientCapabilities) bool {
	requests := client.at(cap_token_requests) or { return true }
	object := as_object(requests) or { return true }
	full := object['full'] or { return false }
	if full is bool {
		return full as bool
	}
	// `full: { delta: true }` is how a client that wants deltas announces that
	// it handles whole-document tokens. No delta is ever sent, so only the
	// request for the full set matters here.
	return true
}

// handle_semantic_tokens_full answers textDocument/semanticTokens/full.
//
// The tokens come from the buffer's parse tree, so a file that does not compile
// is still highlighted, and the answer is the same before and after a save.
fn handle_semantic_tokens_full(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'semantic tokens params is not an object')
	}
	item := parse_text_document(params['textDocument'] or {
		return fail(code_invalid_params, 'semantic tokens has no textDocument')
	}) or { return fail(code_invalid_params, 'semantic tokens textDocument has no uri') }
	document := s.document(item.uri) or {
		return fail(code_invalid_params, 'no open document for ${item.uri}')
	}
	if !s.semantic_legend.enabled() {
		return fail(code_request_failed, 'the client offered no token type this server emits')
	}
	tokens := features.tokens_for(document.text, document.uri)
	mut result := map[string]json2.Any{}
	result['data'] = encode_semantic_tokens(document.text, tokens, s.semantic_legend)
	return ok(json2.Any(result))
}

// encode_semantic_tokens turns the feature layer's byte spans into the
// delta-encoded integers the wire wants: line delta, character delta, length,
// type index, modifier bits.
//
// The character delta counts from the previous token only while the line is
// unchanged; on a new line it counts from the start of that line. A token that
// crosses a line is sent once per line, because a length in characters means
// nothing across a line break.
fn encode_semantic_tokens(text string, tokens []features.SemanticToken, legend SemanticLegend) json2.Any {
	mut data := []json2.Any{}
	mut previous_line := 0
	mut previous_character := 0
	for token in tokens {
		index := legend.index_of(token.kind)
		if index < 0 {
			continue
		}
		modifiers := legend.modifier_mask(token.modifiers)
		mut at := token.start_byte
		for at < token.end_byte {
			stop := line_stop(text, at, token.end_byte)
			start := position_for_offset(text, at)
			finish := position_for_offset(text, stop)
			length := finish.character - start.character
			if length > 0 {
				delta_line := start.line - previous_line
				delta_character := if delta_line == 0 {
					start.character - previous_character
				} else {
					start.character
				}
				data << json2.Any(delta_line)
				data << json2.Any(delta_character)
				data << json2.Any(length)
				data << json2.Any(index)
				data << json2.Any(modifiers)
				previous_line = start.line
				previous_character = start.character
			}
			if stop >= token.end_byte {
				break
			}
			at = stop + 1
		}
	}
	return json2.Any(data)
}

// line_stop returns where the run of text starting at at ends: at the next
// newline, or at the token's own end when that comes first.
fn line_stop(text string, at int, limit int) int {
	mut index := at
	for index < limit {
		if text[index] == `\n` {
			return index
		}
		index++
	}
	return limit
}
