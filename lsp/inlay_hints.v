module lsp

import features
import json2
import os

// handle_inlay_hint answers textDocument/inlayHint.
//
// Every label comes from the buffer's own parse and the workspace index: which
// parameter an argument lands on, which field a positional value initializes,
// what a `:=` infers to, and what a defer will run. The text the client sent is
// the text that is parsed, so a buffer nobody has saved is described as it
// stands rather than as the file it came from.
//
// A request the index cannot answer is refused in words. An empty list reads to
// a client as a clean buffer, and "no workspace folder was indexed" is a
// different statement from "there is nothing here to say".
fn handle_inlay_hint(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'inlay hint params is not an object')
	}
	item := parse_text_document(params['textDocument'] or {
		return fail(code_invalid_params, 'inlay hint has no textDocument')
	}) or { return fail(code_invalid_params, 'inlay hint textDocument has no uri') }
	document := s.document(item.uri) or {
		return fail(code_invalid_params, 'no open document for ${item.uri}')
	}
	session := s.session or {
		return fail(code_request_failed, 'no workspace index exists: initialize never arrived')
	}
	if !session.is_indexed() {
		return fail(code_request_failed, 'no workspace folder was indexed, so a hint here would be a guess')
	}
	path := path_from_uri(item.uri)
	if !session.owns(path) {
		return fail(code_request_failed, 'no indexed workspace folder contains ${path}')
	}
	file := session.file(path) or {
		return fail(code_request_failed, 'the buffer for ${path} is not open in this session')
	}

	mut requested := Range{}
	mut limited := false
	if range_value := params['range'] {
		if parsed := parse_range(range_value) {
			requested = parsed
			limited = true
		}
	}

	hints := features.hints_for(file, s.inlay_hint_options())
	mut result := []json2.Any{cap: hints.len}
	for hint in hints {
		position := position_for_offset(document.text, hint.offset)
		if limited && !range_covers(requested, position) {
			continue
		}
		mut entry := map[string]json2.Any{}
		entry['position'] = encode_position(position)
		entry['label'] = json2.Any(hint.label)
		entry['kind'] = json2.Any(int(hint.kind))
		if hint.padding_right {
			entry['paddingRight'] = json2.Any(true)
		}
		if hint.tooltip != '' {
			entry['tooltip'] = json2.Any(hint.tooltip)
		}
		result << json2.Any(entry)
	}
	return ok(json2.Any(result))
}

// range_covers reports whether a hint's position falls in the part of the file
// the client asked about. The end is inclusive here because a hint sits before
// the text it describes: one that lands exactly at the end of the drawn part is
// describing what comes next on the same line.
fn range_covers(asked Range, position Position) bool {
	if position.line < asked.start.line || position.line > asked.end.line {
		return false
	}
	if position.line == asked.start.line && position.character < asked.start.character {
		return false
	}
	if position.line == asked.end.line && position.character > asked.end.character {
		return false
	}
	return true
}

// inlay_hint_options reads the family toggles out of the settings the client
// sent.
//
// Both shapes are read: a push carries the whole tree with this server's section
// at the top, and the answer to a pull is the section itself. A family that is
// absent, or that arrives as something other than a flag, stays on. A server
// that turned itself off on a malformed setting would be silent for a reason
// nobody could find in the settings file.
fn (s &Server) inlay_hint_options() features.HintOptions {
	settings := s.inlay_hint_settings()
	return features.HintOptions{
		parameters:    setting_flag(settings, 'parameters', true)
		struct_fields: setting_flag(settings, 'structFields', true)
		types:         setting_flag(settings, 'types', true)
		defers:        setting_flag(settings, 'defers', true)
	}
}

// inlay_hint_settings finds the inlayHints object in whatever the client sent.
fn (s &Server) inlay_hint_settings() map[string]json2.Any {
	root := as_object(s.settings) or { return map[string]json2.Any{} }
	if nested := root[server_name] {
		if section := as_object(nested) {
			return hints_of_section(section)
		}
	}
	return hints_of_section(root)
}

// hints_of_section reads the inlayHints object out of one settings section.
fn hints_of_section(section map[string]json2.Any) map[string]json2.Any {
	entry := section['inlayHints'] or { return map[string]json2.Any{} }
	return as_object(entry) or { map[string]json2.Any{} }
}

// setting_flag reads one boolean, falling back to the documented default.
fn setting_flag(settings map[string]json2.Any, name string, default_on bool) bool {
	value := settings[name] or { return default_on }
	if value is bool {
		return value as bool
	}
	return default_on
}

// index_cache_dir is where an index would be cached if this build saved one. It
// does not: the serializer behind the cache dies, so every session pays for its
// own index. The path is handed to the indexer anyway, because a caller that
// forgot it would write into whatever directory the process was started from the
// day the cache works.
fn index_cache_dir() string {
	cache := os.cache_dir()
	return os.join_path(cache, server_name)
}
