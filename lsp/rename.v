module lsp

import features
import json2

// rename.v answers the two requests a rename is made of: what a position names,
// and the edits that rewrite it.
//
// The server never writes a file. A rename comes back as a set of edits for the
// client to apply, which is what makes it one undo in the editor rather than a
// change to the disk this process made behind the person's back.

// RenameRequest is the part both requests share: which buffer, and where in it.
struct RenameRequest {
	// uri is what the client called the buffer, path is what the compiler calls
	// it, and text is what the two agree on.
	uri    string
	path   string
	text   string
	offset int
}

// handle_prepare_rename answers textDocument/prepareRename: which name a
// position holds, and the range a client should select and prefill.
//
// A position that cannot be renamed is answered as an error rather than as
// nothing. A client that got an empty answer would show no rename affordance and
// no reason for it, where the reason is the useful part: a module name and an
// import are both refused here and both say why.
fn handle_prepare_rename(mut s Server, req Message) Reply {
	request := rename_request(s, req) or { return fail(code_invalid_params, err.msg()) }
	session := s.session or {
		return fail(code_request_failed, 'no session exists: initialize never arrived')
	}
	file := session.file(request.path) or {
		return fail(code_request_failed, 'the buffer for ${request.path} is not open in this session')
	}
	target := features.rename_target(file, request.offset) or {
		return fail(code_request_failed, err.msg())
	}
	mut answer := map[string]json2.Any{}
	answer['range'] = encode_range(Range{
		start: position_for_offset(request.text, target.span.start)
		end:   position_for_offset(request.text, target.span.end)
	})
	answer['placeholder'] = json2.Any(target.name)
	return ok(json2.Any(answer))
}

// handle_rename answers textDocument/rename with the edits that would rewrite
// every place the name appears.
//
// The proposed name is checked before anything is planned, so a client that
// would rewrite a file into something that no longer parses is refused in words
// with nothing changed. A file the search reached and could not read is refused
// the same way, because a rename that reached some of the places is worse than
// one that reached none.
fn handle_rename(mut s Server, req Message) Reply {
	request := rename_request(s, req) or { return fail(code_invalid_params, err.msg()) }
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'rename params is not an object')
	}
	new_name := (params['newName'] or {
		return fail(code_invalid_params, 'rename has no newName')
	}).str()
	problem := features.name_problem(new_name)
	if problem != '' {
		return fail(code_invalid_params, problem)
	}
	session := s.session or {
		return fail(code_request_failed, 'no session exists: initialize never arrived')
	}
	file := session.file(request.path) or {
		return fail(code_request_failed, 'the buffer for ${request.path} is not open in this session')
	}
	target := features.rename_target(file, request.offset) or {
		return fail(code_request_failed, err.msg())
	}
	plan := features.rename_spans(session, target) or {
		return fail(code_request_failed, err.msg())
	}
	if plan.unreadable.len > 0 {
		return fail(code_request_failed, 'the rename would not reach ${plan.unreadable.join(', ')}: those files could not be read, so the edit would be half of one')
	}
	mut changes := map[string]json2.Any{}
	for file_spans in plan.files {
		mut edits := []json2.Any{cap: file_spans.spans.len}
		for span in file_spans.spans {
			mut edit := map[string]json2.Any{}
			edit['range'] = encode_range(Range{
				start: position_for_offset(file_spans.text, span.start)
				end:   position_for_offset(file_spans.text, span.end)
			})
			edit['newText'] = json2.Any(new_name)
			edits << json2.Any(edit)
		}
		changes[uri_from_path(file_spans.path)] = json2.Any(edits)
	}
	mut answer := map[string]json2.Any{}
	answer['changes'] = json2.Any(changes)
	return ok(json2.Any(answer))
}

// rename_request reads the part of a rename request both handlers need: the
// buffer, the position in it, and the byte the position names.
//
// A buffer this session does not hold is refused rather than planned against the
// file on disk: the client is showing text the server has not seen, and a range
// computed over another text is a range that selects the wrong name.
fn rename_request(s &Server, req Message) !RenameRequest {
	params := as_object(req.params) or { return error('rename params is not an object') }
	item := parse_text_document(params['textDocument'] or {
		return error('rename has no textDocument')
	}) or { return error('rename textDocument has no uri') }
	position := parse_position(params['position'] or { return error('rename has no position') }) or {
		return error('the rename position is not a position')
	}
	path := path_from_uri(item.uri)
	if path == '' {
		return error('${item.uri} is not a file this server can read')
	}
	session := s.session or { return error('no session exists: initialize never arrived') }
	file := session.file(path) or {
		return error('the buffer for ${path} is not open in this session')
	}
	text := file.source_text
	// A position past the end of the buffer clamps to the end of it, and the
	// lane refuses it there with the words it uses for a position on no name.
	offset := offset_for(text, position)
	return RenameRequest{
		uri:    item.uri
		path:   path
		text:   text
		offset: offset
	}
}
