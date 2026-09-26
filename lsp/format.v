module lsp

import features
import json2

// handle_formatting answers textDocument/formatting by running the buffer
// through `v fmt` and replacing the buffer with what came back.
//
// Every way this can fail is an error rather than an empty edit list. To a
// client an empty list means the buffer was already formatted, which is a claim
// about the file, and a session with no compiler or a buffer that does not parse
// has not earned it.
fn handle_formatting(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'formatting params is not an object')
	}
	item := parse_text_document(params['textDocument'] or {
		return fail(code_invalid_params, 'formatting has no textDocument')
	}) or { return fail(code_invalid_params, 'formatting textDocument has no uri') }
	document := s.document(item.uri) or {
		// Formatting the file on disk would format something other than the
		// buffer the user is looking at, and the two differ exactly when it
		// matters.
		return fail(code_invalid_params, 'no open document for ${item.uri}')
	}
	compiler := s.compiler or {
		return fail(code_request_failed, 'no V compiler to format with: ${s.compiler_error}')
	}
	report := s.compiler_caps or {
		return fail(code_request_failed, 'the compiler was never probed, so formatting is unproven')
	}
	if !report.supports(.format) {
		return fail(code_request_failed, 'this compiler cannot format: ${report.detail_of(.format)}')
	}
	result := features.format_buffer(compiler, document.text) or {
		return fail(code_request_failed, '`v fmt` refused the buffer: ${err.msg()}')
	}
	return ok(encode_text_edits(document.text, result.edits))
}

// encode_text_edits turns the feature layer's byte ranges into the positions a
// client counts.
fn encode_text_edits(text string, edits []features.DocumentEdit) json2.Any {
	mut items := []json2.Any{cap: edits.len}
	for edit in edits {
		mut item := map[string]json2.Any{}
		item['range'] = encode_range(Range{
			start: position_for_offset(text, edit.start_byte)
			end:   position_for_offset(text, edit.end_byte)
		})
		item['newText'] = json2.Any(edit.new_text)
		items << json2.Any(item)
	}
	return json2.Any(items)
}
