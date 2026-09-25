module lsp

import json2

// The capability paths as the spec spells them. They are constants because a
// typo in one of these strings is silent: the negotiation would just decide the
// client does not have the capability.
const cap_synchronization = 'textDocument.synchronization'
const cap_pull_diagnostics = 'textDocument.diagnostic'
const cap_workspace_folders = 'workspace.workspaceFolders'
const cap_work_done_progress = 'window.workDoneProgress'
const cap_position_encodings = 'general.positionEncodings'
const cap_configuration = 'workspace.configuration'
const cap_did_change_configuration = 'workspace.didChangeConfiguration'

// @since 3.18.0
// workspace/textDocumentContent is 3.18 and the capability path is provisional.
const cap_text_document_content = 'workspace.textDocumentContent'

pub const server_name = 'visor'

// ClientCapabilities is a read-only view over what the client announced in
// initialize. Every decision the server makes about offering a provider comes
// from here, because a provider the client cannot use is worse than none.
pub struct ClientCapabilities {
pub:
	raw map[string]json2.Any
}

pub fn new_client_capabilities(value json2.Any) ClientCapabilities {
	obj := as_object(value) or { map[string]json2.Any{} }
	return ClientCapabilities{
		raw: obj
	}
}

// at walks a dotted capability path and returns what is there, if anything.
pub fn (c &ClientCapabilities) at(path string) ?json2.Any {
	mut node := json2.Any(c.raw)
	for segment in path.split('.') {
		obj := as_object(node) or { return none }
		node = obj[segment] or { return none }
	}
	return node
}

// advertises reports that the client sent something for this path. An explicit
// false, null or empty list does not count: the client said it has nothing
// there. An object counts even when it is empty, because that is how the
// capability is spelled when it carries only sub-flags.
pub fn (c &ClientCapabilities) advertises(path string) bool {
	value := c.at(path) or { return false }
	if value is bool {
		return value as bool
	}
	if value is json2.Null {
		return false
	}
	if value is []json2.Any {
		return (value as []json2.Any).len > 0
	}
	if value is string {
		return (value as string) != ''
	}
	return true
}

// flag reports that the client sent exactly true, which is how a plain switch
// capability is written.
pub fn (c &ClientCapabilities) flag(path string) bool {
	value := c.at(path) or { return false }
	return value is bool && (value as bool)
}

// strings reads a list of strings out of the capabilities, for the paths that
// carry a list of allowed values.
pub fn (c &ClientCapabilities) strings(path string) []string {
	value := c.at(path) or { return [] }
	items := as_array(value) or { return [] }
	mut out := []string{cap: items.len}
	for item in items {
		if item is string {
			out << (item as string)
		}
	}
	return out
}

// Negotiation is the server capability set plus a line per decision. The notes
// are there for support: "why is completion missing" should be answerable from a
// log line instead of from the spec.
pub struct Negotiation {
pub:
	capabilities map[string]json2.Any
	notes        []string
}

// negotiate builds the server capabilities from the client's list.
//
// Two things are deliberately not advertised. The feature providers (hover,
// completion, definition and the rest) have no handlers yet, so claiming them
// would turn a visible MethodNotFound into an empty answer. And the 3.18 virtual
// document provider is advertised only where content exists to serve.
pub fn negotiate(client ClientCapabilities) Negotiation {
	mut caps := map[string]json2.Any{}
	mut notes := []string{}

	if client.advertises(cap_synchronization) {
		// the client said it can send ranged edits, so ask for them.
		caps['textDocumentSync'] = sync_incremental()
		notes << 'textDocumentSync: incremental, the client advertised ${cap_synchronization}'
	} else {
		// without that, the server has to ask for whole documents.
		caps['textDocumentSync'] = sync_full()
		notes << 'textDocumentSync: full, the client did not advertise ${cap_synchronization}'
	}

	if client.flag(cap_workspace_folders) {
		caps['workspace'] = workspace_capabilities()
		notes << 'workspace.workspaceFolders: supported, the client advertised it'
	} else {
		notes << 'workspace.workspaceFolders: not advertised, the client did not offer it'
	}

	if client.advertises(cap_pull_diagnostics) {
		// the diag lane fills this in. Until it does, the method answers with a
		// request-failed error naming the lane, which is a visible stub.
		caps['diagnosticProvider'] = diagnostic_provider()
		notes << 'diagnosticProvider: registered, the client advertised ${cap_pull_diagnostics}'
	} else {
		notes << 'diagnosticProvider: not advertised, the client did not offer ${cap_pull_diagnostics}'
	}

	if client.flag(cap_work_done_progress) {
		caps['workDoneProgress'] = json2.Any(true)
		notes << 'workDoneProgress: supported, the client advertised it'
	} else {
		notes << 'workDoneProgress: not advertised, the client did not offer it'
	}

	encodings := client.strings(cap_position_encodings)
	if encodings.len > 0 {
		if 'utf-16' in encodings {
			// the document store counts UTF-16 code units, and utf-16 is the
			// default, so saying so only matters to a client that asked.
			caps['positionEncoding'] = json2.Any('utf-16')
			notes << 'positionEncoding: utf-16, the client offered it'
		} else {
			notes << 'positionEncoding: left at the default, the client offered ${encodings} and the store counts UTF-16'
		}
	}

	// @since 3.18.0
	if client.advertises(cap_text_document_content) {
		// the client can ask for content; there is none to give. Advertising the
		// provider would turn a missing feature into a request that fails on
		// every keystroke.
		notes << 'textDocumentContentProvider: not advertised, the client offered ${cap_text_document_content} (3.18) and this build serves no content'
	}

	return Negotiation{
		capabilities: caps
		notes:        notes
	}
}

// client_pulls_configuration reports whether the server may ask the client for
// settings. Applies to workspace/configuration, which is the pull that replaces
// the didChangeConfiguration push when the client offers it.
pub fn (c &ClientCapabilities) client_pulls_configuration() bool {
	return c.advertises(cap_configuration)
}

// client_pushes_configuration reports whether the client will send
// workspace/didChangeConfiguration. Both sides can be true.
pub fn (c &ClientCapabilities) client_pushes_configuration() bool {
	return c.advertises(cap_did_change_configuration)
}

fn sync_incremental() json2.Any {
	mut save := map[string]json2.Any{}
	save['includeText'] = json2.Any(false)
	mut sync := map[string]json2.Any{}
	sync['openClose'] = json2.Any(true)
	// 2 is the Incremental change kind.
	sync['change'] = json2.Any(2)
	sync['save'] = json2.Any(save)
	return json2.Any(sync)
}

fn sync_full() json2.Any {
	mut sync := map[string]json2.Any{}
	sync['openClose'] = json2.Any(true)
	// 1 is the Full change kind.
	sync['change'] = json2.Any(1)
	return json2.Any(sync)
}

fn workspace_capabilities() json2.Any {
	mut folders := map[string]json2.Any{}
	folders['supported'] = json2.Any(true)
	folders['changeNotifications'] = json2.Any(true)
	mut workspace := map[string]json2.Any{}
	workspace['workspaceFolders'] = json2.Any(folders)
	return json2.Any(workspace)
}

fn diagnostic_provider() json2.Any {
	mut provider := map[string]json2.Any{}
	provider['identifier'] = json2.Any(server_name)
	// Single file diagnostics only until the diag lane can schedule a whole
	// module root, and no workspace diagnostics for the same reason.
	provider['interFileDependencies'] = json2.Any(false)
	provider['workspaceDiagnostics'] = json2.Any(false)
	return json2.Any(provider)
}
