module lsp

import json2

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
	if options := params['initializationOptions'] {
		s.initialization_options = options
	}
	negotiated := negotiate(s.client_caps)
	s.negotiation_notes = negotiated.notes
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
fn handle_initialized(mut s Server, _ Message) Reply {
	if s.state != .initialized {
		return ok(null_value())
	}
	s.client_ready = true
	return ok(null_value())
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
