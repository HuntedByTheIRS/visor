module lsp

import engine
import json2

// handle_did_open records a buffer the client has open. From here until
// didClose, this store is the only copy of the file that exists.
//
// A check is scheduled with it: the buffer has not been read by the compiler
// before, so whatever is wrong with it is wrong right now.
fn handle_did_open(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	item_value := params['textDocument'] or { return ok(null_value()) }
	item := parse_text_document(item_value) or { return ok(null_value()) }
	s.documents.open_document(item)
	s.feed_session(item.uri)
	s.schedule_check(item.uri)
	return ok(null_value())
}

// handle_did_change applies the ranged edits. Each change is measured against
// the result of the previous one, and a change with no range replaces the
// buffer, which is how a client that lost track resynchronises.
//
// The edit is what earns a check, and the check waits for the typing to stop.
// Nothing here runs the compiler: a didChange arrives per keystroke, and this
// is the notification that would turn each of them into a process.
fn handle_did_change(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	item_value := params['textDocument'] or { return ok(null_value()) }
	item := parse_text_document(item_value) or { return ok(null_value()) }
	changes_value := params['contentChanges'] or { return ok(null_value()) }
	changes := parse_changes(changes_value) or { return ok(null_value()) }
	s.documents.apply_changes(item.uri, item.version, changes) or {
		// A change for a buffer that is not open means the open notification was
		// lost or the two sides disagree about what is open. There is nothing to
		// answer, so it is counted.
		s.sync_refusals++
		return ok(null_value())
	}
	s.feed_session(item.uri)
	s.schedule_check(item.uri)
	return ok(null_value())
}

// handle_did_close drops the buffer. Anything a lane cached for it has to be
// dropped with it, which the lanes do on the notification.
//
// The findings go with it: a saved or closed file keeps no marks, so the client
// is told to clear what it is showing for this uri rather than left with
// errors from a buffer nobody has open.
fn handle_did_close(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	item_value := params['textDocument'] or { return ok(null_value()) }
	item := parse_text_document(item_value) or { return ok(null_value()) }
	s.documents.close_document(item.uri)
	s.close_session_buffer(item.uri)
	s.clear_diagnostics(item.uri)
	return ok(null_value())
}

// handle_did_save records a save. Most clients send no text with it, and the
// buffer already holds the file.
//
// A save is worth a check even though it does not change the text: the files
// the buffer imports may have moved on disk since the last run, and a save is
// where the compiler's view of the project can differ from the buffer's.
fn handle_did_save(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	item_value := params['textDocument'] or { return ok(null_value()) }
	item := parse_text_document(item_value) or { return ok(null_value()) }
	mut text := ''
	if sent := params['text'] {
		if sent is string {
			text = sent as string
		}
	}
	// a save for a buffer that is not open is a client bug, and one that did not
	// arrive as a notification we can answer.
	if s.documents.save_document(item.uri, text) {
		s.feed_session(item.uri)
		s.schedule_check(item.uri)
	}
	return ok(null_value())
}

// feed_session hands the buffer's text to the workspace index, which is what
// makes a question about the buffer answerable from the buffer.
//
// It runs on every edit, and it is the price of the index describing the text in
// front of the person rather than the last save: the buffer is reparsed and the
// workspace index is rebuilt from it. A client that never advertised a lane that
// reads a buffer is not fed at all, because paying for a parse per keystroke
// would be paying for nothing.
//
// A buffer no indexed folder contains is refused by the session, and the refusal
// is not repeated here: the lanes ask the same question when they are asked, and
// they can say why in the answer.
fn (mut s Server) feed_session(uri string) {
	if !s.lanes_read_buffers() {
		return
	}
	mut session := s.session or { return }
	document := s.documents.get(uri) or { return }
	path := path_from_uri(uri)
	if path == '' {
		return
	}
	buffer := session.put_buffer(path, document.text) or { return }
	// A buffer that names a standard library module gets that module indexed, so
	// `os.read_file` answers with its parameter names the way a call into the
	// next file does. Only the modules the buffer names are read, and only once
	// per session.
	if compiler := s.compiler {
		if vlib := compiler.vlib_dir() {
			session.index_imported_modules(vlib, engine.imported_modules(buffer.file))
		}
	}
}

// close_session_buffer drops the parse of a buffer nobody has open, and hands the
// file back to the index as it is on disk.
fn (mut s Server) close_session_buffer(uri string) {
	mut session := s.session or { return }
	path := path_from_uri(uri)
	if path == '' {
		return
	}
	session.close_buffer(path)
}

// handle_did_change_configuration stores the settings the client pushed. Whether
// the server also polls for them depends on what the client advertised, which is
// decided where the pull is sent.
fn handle_did_change_configuration(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	if settings := params['settings'] {
		s.settings = settings
	}
	// A client that can answer workspace/configuration may send an empty push
	// and expect the server to ask for what it needs, so ask.
	if s.client_announced().client_pulls_configuration() {
		s.pull_configuration()
	}
	return ok(null_value())
}

// handle_did_change_workspace_folders keeps the root list current. A folder that
// was removed stops being a root for every lane at once.
fn handle_did_change_workspace_folders(mut s Server, req Message) Reply {
	params := as_object(req.params) or { return ok(null_value()) }
	event_value := params['event'] or { return ok(null_value()) }
	event := as_object(event_value) or { return ok(null_value()) }
	if added := event['added'] {
		for item in as_array(added) or { []json2.Any{} } {
			folder := parse_workspace_folder(item) or { continue }
			mut known := false
			for existing in s.workspace_folders {
				if existing.uri == folder.uri {
					known = true
				}
			}
			if !known {
				s.workspace_folders << folder
			}
		}
	}
	if removed := event['removed'] {
		mut removed_uris := []string{}
		for item in as_array(removed) or { []json2.Any{} } {
			folder := parse_workspace_folder(item) or { continue }
			removed_uris << folder.uri
		}
		if removed_uris.len > 0 {
			mut kept := []WorkspaceFolder{cap: s.workspace_folders.len}
			for folder in s.workspace_folders {
				if folder.uri !in removed_uris {
					kept << folder
				}
			}
			s.workspace_folders = kept
		}
	}
	// A folder added mid-session has no index behind it, and every answer about
	// a file in it would be refused for a reason the person cannot see. Walk the
	// list again; the folders already indexed cost nothing here.
	//
	// A folder taken away keeps its stubs, because the engine has no way to drop
	// one root. What that costs is an answer about a file that is no longer open,
	// which is smaller than the alternative: dropping the whole index and paying
	// for it again on the next keystroke.
	s.index_workspace()
	return ok(null_value())
}

// configuration is the last settings the client sent, either pushed or pulled.
pub fn (s &Server) configuration() json2.Any {
	return s.settings
}

// pull_configuration asks the client for the settings this server reads. The
// answer replaces whatever a push carried, because it is the newer one.
fn (mut s Server) pull_configuration() {
	mut item := map[string]json2.Any{}
	item['section'] = json2.Any(server_name)
	mut params := map[string]json2.Any{}
	params['items'] = json2.Any([json2.Any(item)])
	s.ask('workspace/configuration', json2.Any(params), .configuration, '')
}

// first_configuration unwraps the array workspace/configuration answers with.
// The request carries one section, so the reply has one entry.
fn first_configuration(value json2.Any) json2.Any {
	items := as_array(value) or { return value }
	if items.len == 0 {
		return value
	}
	return items[0]
}
