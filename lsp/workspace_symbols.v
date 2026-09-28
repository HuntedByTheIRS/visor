module lsp

import engine
import features
import json2
import os

// workspace_symbol_limit is how many names one search answers with.
//
// The protocol has no field for a limit, so the server owns it. A client draws
// these in a list a person scrolls, and a query that matches half a workspace
// would send half a workspace over the wire to be scrolled past: two hundred is
// more than a list shows at once and small enough that the answer is cheap to
// send. A query that matches more is answered with the best two hundred, which
// the ranking decides.
const workspace_symbol_limit = 200

// handle_workspace_symbols answers workspace/symbol.
//
// The search reads the index rather than the open buffers, because a search that
// only reached open files would not be a search of the workspace. What an
// indexed file says is what it said on disk, so a declaration that has only been
// typed into a buffer is found when the buffer is saved; the reply is about
// declarations the index can point at.
//
// A session with no indexed folder is refused in words. An empty list would read
// as a workspace with nothing in it, which is a different claim from "nothing has
// been indexed here".
fn handle_workspace_symbols(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'workspace symbol params is not an object')
	}
	mut query := ''
	if value := params['query'] {
		query = value.str()
	}
	session := s.session or {
		return fail(code_request_failed, 'no session exists: initialize never arrived')
	}
	if !session.is_indexed() {
		return fail(code_request_failed, 'no workspace folder has been indexed, so there is nothing to search')
	}
	candidates := searchable_symbols(session)
	ranked := features.rank_symbols(query, candidates, workspace_symbol_limit)
	return ok(json2.Any(encode_workspace_symbols(ranked, symbol_texts(session, ranked))))
}

// searchable_symbols collects the declarations the index holds, one entry per
// place a name is declared.
//
// The index files a declaration under more than one key, so the same one arrives
// several times and the answer would look like a workspace that declares
// everything twice. A repeat is recognised by the file and the place in it,
// which is what makes two declarations of one name in two files two entries.
fn searchable_symbols(session &engine.Session) []features.WorkspaceSymbol {
	mut candidates := []features.WorkspaceSymbol{}
	mut seen := map[string]bool{}
	for element in session.index_declarations() {
		path := features.element_path(element) or { continue }
		symbol := features.workspace_symbol_of(element, session.module_of(path)) or { continue }
		key := features.symbol_identity(symbol)
		if seen[key] {
			continue
		}
		seen[key] = true
		candidates << symbol
	}
	return candidates
}

// symbol_texts reads the text of every file an answer points into, once per
// file. A range from the index is a line and a byte column, and turning one into
// a position means walking that file's text.
//
// The buffer wins when the file is open: it is the text the client is showing,
// and the two agree about the lines before the first edit. A file that cannot be
// read at all is left out of the map, and a range in it is answered from the
// empty text, which puts the position at the start of it rather than inventing a
// line the file does not have.
fn symbol_texts(session &engine.Session, symbols []features.WorkspaceSymbol) map[string]string {
	mut texts := map[string]string{}
	for symbol in symbols {
		if symbol.path in texts {
			continue
		}
		if file := session.file(symbol.path) {
			texts[symbol.path] = file.source_text
			continue
		}
		texts[symbol.path] = os.read_file(symbol.path) or { '' }
	}
	return texts
}

// encode_workspace_symbols writes the ranked names in the shape a client jumps
// from: a name, the kind of declaration it is, the module it is in, and the file
// and range that hold it.
fn encode_workspace_symbols(symbols []features.WorkspaceSymbol, texts map[string]string) []json2.Any {
	mut out := []json2.Any{cap: symbols.len}
	for symbol in symbols {
		out << encode_workspace_symbol(symbol, texts[symbol.path] or { '' })
	}
	return out
}

// encode_workspace_symbol writes one name. The container is left out when the
// index knows no module for the file, because a client draws that line as an
// empty one rather than as an absent one.
fn encode_workspace_symbol(symbol features.WorkspaceSymbol, text string) json2.Any {
	mut entry := map[string]json2.Any{}
	entry['name'] = json2.Any(symbol.name)
	entry['kind'] = json2.Any(int(symbol.kind))
	if symbol.container != '' {
		entry['containerName'] = json2.Any(symbol.container)
	}
	mut location := map[string]json2.Any{}
	location['uri'] = json2.Any(uri_from_path(symbol.path))
	location['range'] = encode_range(range_of_text_range(text, symbol.range))
	entry['location'] = json2.Any(location)
	return json2.Any(entry)
}
