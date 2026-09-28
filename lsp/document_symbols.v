module lsp

import features
import json2

// handle_document_symbols answers textDocument/documentSymbol.
//
// The outline is the buffer's own parse, so the answer describes the text the
// client sent rather than the file it came from. Nothing else is consulted: an
// outline is a fact about one file, and the lane answers for a buffer in no
// indexed folder as readily as for one inside a project.
//
// A document this session does not hold is refused in words. An empty outline
// reads to a client as a file with nothing in it, which is a different claim
// from "that buffer is not open here".
fn handle_document_symbols(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'document symbol params is not an object')
	}
	item := parse_text_document(params['textDocument'] or {
		return fail(code_invalid_params, 'document symbol has no textDocument')
	}) or { return fail(code_invalid_params, 'document symbol textDocument has no uri') }
	session := s.session or {
		return fail(code_request_failed, 'no session exists: initialize never arrived')
	}
	path := path_from_uri(item.uri)
	file := session.file(path) or {
		return fail(code_request_failed, 'the buffer for ${path} is not open in this session')
	}
	symbols := features.document_symbols(file)
	return ok(json2.Any(encode_document_symbols(symbols, file.source_text)))
}

// encode_document_symbols writes an outline as the protocol's hierarchical
// shape: every entry carries the range of its whole declaration and the range
// of its name, which is what a client selects and folds on.
fn encode_document_symbols(symbols []features.DocSymbol, text string) []json2.Any {
	mut out := []json2.Any{cap: symbols.len}
	for symbol in symbols {
		out << encode_document_symbol(symbol, text)
	}
	return out
}

// encode_document_symbol writes one entry and everything under it. The offsets
// the outline carries are bytes into the text it was computed over, and this is
// where they become the positions a client counts in.
fn encode_document_symbol(symbol features.DocSymbol, text string) json2.Any {
	mut entry := map[string]json2.Any{}
	entry['name'] = json2.Any(symbol.name)
	entry['kind'] = json2.Any(int(symbol.kind))
	entry['range'] = encode_range(Range{
		start: position_for_offset(text, symbol.start)
		end:   position_for_offset(text, symbol.end)
	})
	entry['selectionRange'] = encode_range(Range{
		start: position_for_offset(text, symbol.name_start)
		end:   position_for_offset(text, symbol.name_end)
	})
	if symbol.detail != '' {
		entry['detail'] = json2.Any(symbol.detail)
	}
	if symbol.children.len > 0 {
		entry['children'] = json2.Any(encode_document_symbols(symbol.children, text))
	}
	return json2.Any(entry)
}
