module lsp

import engine
import json2
import os

// WorkspaceFolder is one root the client has open. Only the uri and name are
// kept: anything else a lane needs can be read from the folder later.
pub struct WorkspaceFolder {
pub:
	uri  string
	name string
}

// handle_initialize answers the request that opens a session. The capabilities
// it returns are computed from what the client announced, so the reply is built
// here rather than read out of a constant.
fn handle_initialize(mut s Server, req Message) Reply {
	if s.state != .uninitialized {
		// a second initialize is a client bug, and answering it would leave the
		// session holding two capability sets.
		return fail(code_invalid_request, 'initialize arrived twice')
	}
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'initialize params is not an object')
	}
	s.client_caps = new_client_capabilities(params['capabilities'] or { null_value() })
	s.client_name = string_field(params, 'clientInfo.name')
	s.workspace_folders = read_workspace_folders(params)
	// The session is built here, empty, so every lane that reads it has one
	// object to ask rather than a second place to check whether it exists.
	s.session = engine.new_session()
	if options := params['initializationOptions'] {
		s.initialization_options = options
	}
	negotiated := negotiate(s.client_caps, s.compiler_caps)
	s.negotiation_notes = negotiated.notes
	// The handlers encode with the same legend the reply advertised, so an index
	// means the same type on both sides.
	s.semantic_legend = negotiated.legend
	mut result := map[string]json2.Any{}
	result['capabilities'] = json2.Any(negotiated.capabilities)
	mut info := map[string]json2.Any{}
	info['name'] = json2.Any(server_name)
	if s.server_version != '' {
		info['version'] = json2.Any(s.server_version)
	}
	result['serverInfo'] = json2.Any(info)
	s.state = .initialized
	return ok(json2.Any(result))
}

// handle_initialized takes the notification that says the client is ready. Only
// after it may the server ask the client for anything.
//
// The workspace index is built here rather than in initialize. The folders are
// read at initialize, and the reply to it is what the client waits for before it
// draws anything, so the indexing belongs on the far side of the handshake where
// nothing is blocked on the answer but this server's own next request.
fn handle_initialized(mut s Server, _ Message) Reply {
	if s.state != .initialized {
		return ok(null_value())
	}
	s.client_ready = true
	s.index_workspace()
	return ok(null_value())
}

// index_workspace indexes the folders the client named, which is the whole of
// what every engine-backed lane can see.
//
// A folder that is not a readable directory is named in the notes and skipped:
// there is nothing the client could do with an error about it, and the lane that
// asks afterwards reports what it did not get to. Indexing a folder that is
// already indexed does nothing, which is what makes this safe to call again when
// the client adds a folder to the session.
fn (mut s Server) index_workspace() {
	mut session := s.session or { return }
	mut indexed := 0
	for folder in s.workspace_folders {
		path := path_from_uri(folder.uri)
		if path == '' || !os.is_dir(path) {
			s.negotiation_notes << 'index: skipped ${folder.uri}, which is not a directory this process can read'
			continue
		}
		session.index_root(path, index_cache_dir())
		indexed++
	}
	if indexed > 0 {
		s.negotiation_notes << 'index: ${indexed} folder(s) in ${session.index_ms} ms'
	}
	// A buffer that was open before its folder arrived has no stubs in the
	// index: the session refused it when the text came in. Handing every open
	// buffer over again is what makes the folder's arrival visible in it.
	for uri in s.documents.uris() {
		s.feed_session(uri)
	}
}

// handle_shutdown stops accepting work. The process stays alive until exit, so
// a client can still read the replies it already asked for.
fn handle_shutdown(mut s Server, _ Message) Reply {
	if s.state == .uninitialized {
		return fail(code_invalid_request, 'shutdown arrived before initialize')
	}
	s.state = .shutting_down
	return ok(null_value())
}

// handle_exit ends the session. The exit code is the point: exit after a
// shutdown is the clean path, and exit without one means the client is gone.
fn handle_exit(mut s Server, _ Message) Reply {
	s.exit_code = if s.state == .shutting_down { 0 } else { 1 }
	s.exit_now = true
	return ok(null_value())
}

// refuse_before_dispatch answers a message that arrived in the wrong phase. A
// request sent before initialize, or after shutdown, gets an error naming the
// phase instead of the MethodNotFound it would otherwise collect.
fn (s &Server) refuse_before_dispatch(m Message) ?Reply {
	if s.state == .shutting_down && m.method != 'exit' {
		return fail(code_invalid_request, 'the server has shut down')
	}
	if s.state == .uninitialized && m.method != 'initialize' && m.method != 'exit' {
		return fail(code_server_not_initialized, '${m.method} arrived before initialize')
	}
	return none
}

// read_workspace_folders takes the folder list, falling back to the deprecated
// rootUri that older clients send on its own.
fn read_workspace_folders(params map[string]json2.Any) []WorkspaceFolder {
	mut folders := []WorkspaceFolder{}
	if listed := params['workspaceFolders'] {
		items := as_array(listed) or { []json2.Any{} }
		for item in items {
			if folder := parse_workspace_folder(item) {
				folders << folder
			}
		}
		return folders
	}
	if root := params['rootUri'] {
		if root is string {
			root_uri := root as string
			if root_uri != '' {
				folders << WorkspaceFolder{
					uri: root_uri
				}
			}
		}
	}
	return folders
}

fn parse_workspace_folder(value json2.Any) ?WorkspaceFolder {
	obj := as_object(value) or { return none }
	uri := obj['uri'] or { return none }
	if uri !is string {
		return none
	}
	mut name := ''
	if label := obj['name'] {
		name = label.str()
	}
	return WorkspaceFolder{
		uri:  uri as string
		name: name
	}
}

// string_field reads a nested string field and tolerates the path being absent
// at any depth.
fn string_field(obj map[string]json2.Any, path string) string {
	mut node := json2.Any(obj)
	for segment in path.split('.') {
		container := as_object(node) or { return '' }
		node = container[segment] or { return '' }
	}
	if node is string {
		return node as string
	}
	return ''
}
