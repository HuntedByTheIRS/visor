module lsp

import json2
import vtool

// The capability paths as the spec spells them. They are constants because a
// typo in one of these strings is silent: the negotiation would just decide the
// client does not have the capability.
const cap_synchronization = 'textDocument.synchronization'
const cap_pull_diagnostics = 'textDocument.diagnostic'
const cap_publish_diagnostics = 'textDocument.publishDiagnostics'
const cap_formatting = 'textDocument.formatting'
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

// new_client_capabilities builds a view over the capability payload from initialize.
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
	// legend is the token legend the capabilities were built around, which the
	// handlers have to use for the same indices to mean the same thing.
	legend SemanticLegend
}

// negotiate builds the server capabilities from the client's list and from what
// the startup probe found the compiler can do.
//
// Two things are deliberately not advertised. The feature providers that have no
// handlers yet (hover, completion, definition and the rest) would turn a visible
// MethodNotFound into an empty answer. And the 3.18 virtual document provider is
// advertised only where content exists to serve.
pub fn negotiate(client ClientCapabilities, compiler ?vtool.CapabilityReport) Negotiation {
	mut caps := map[string]json2.Any{}
	mut notes := []string{}
	legend := new_semantic_legend(client)

	if client.advertises(cap_synchronization) {
		// the client said it can send ranged edits, so ask for them.
		caps['textDocumentSync'] = sync_incremental()
		notes << 'textDocumentSync: incremental, the client advertised ${cap_synchronization}'
	} else {
		// without that, the server has to ask for whole documents.
		caps['textDocumentSync'] = sync_full()
		notes << 'textDocumentSync: full, the client did not advertise ${cap_synchronization}'
	}

	if client.advertises(cap_formatting) {
		// Claimed only when a compiler was resolved and the probe saw it rewrite
		// a buffer. A client promised a provider that answers every save with an
		// error is worse off than one told nothing.
		refusal := format_refusal(compiler)
		if refusal == '' {
			caps['documentFormattingProvider'] = json2.Any(true)
			notes << 'documentFormattingProvider: registered, the client advertised ${cap_formatting} and `v fmt -` rewrote the probe buffer'
		} else {
			notes << 'documentFormattingProvider: not registered, ${refusal}'
		}
	} else {
		notes << 'documentFormattingProvider: not registered, the client did not offer ${cap_formatting}'
	}

	if client.advertises(cap_semantic_tokens) {
		// Both halves have to line up: a legend the client can draw, and a
		// request shape it will send. Anything else is a provider that answers
		// into the void.
		if !legend.enabled() {
			notes << 'semanticTokensProvider: not registered, the client offered ${cap_semantic_tokens} but no token type this server emits'
		} else if !full_tokens_wanted(client) {
			notes << 'semanticTokensProvider: not registered, the client did not ask for whole-document tokens'
		} else {
			caps['semanticTokensProvider'] = semantic_tokens_provider(legend)
			notes << 'semanticTokensProvider: registered with ${legend.token_types.len} token types and ${legend.token_modifiers.len} token modifiers, whole document only'
		}
	} else {
		notes << 'semanticTokensProvider: not registered, the client did not offer ${cap_semantic_tokens}'
	}

	if client.flag(cap_workspace_folders) {
		caps['workspace'] = workspace_capabilities()
		notes << 'workspace.workspaceFolders: supported, the client advertised it'
	} else {
		notes << 'workspace.workspaceFolders: not advertised, the client did not offer it'
	}

	if client.advertises(cap_pull_diagnostics) {
		refusal := check_refusal(compiler)
		if refusal == '' {
			caps['diagnosticProvider'] = diagnostic_provider()
			notes << 'diagnosticProvider: registered, the client advertised ${cap_pull_diagnostics} and `v -check -` reported the planted error'
		} else {
			notes << 'diagnosticProvider: not registered, ${refusal}'
		}
	} else {
		notes << 'diagnosticProvider: not registered, the client did not offer ${cap_pull_diagnostics}'
	}

	// A pushed finding needs a compiler and a client that will draw it. The
	// client says so once, in this capability, and a client that never says it
	// is served by the pull path instead.
	if client.advertises(cap_publish_diagnostics) {
		notes << 'publishDiagnostics: pushed once an edit settles, the client advertised ${cap_publish_diagnostics}'
	} else {
		notes << 'publishDiagnostics: not pushed, the client did not offer ${cap_publish_diagnostics}; a pull still answers'
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
		legend:       legend
	}
}

// format_refusal says why formatting cannot be promised to this client, or
// nothing at all when it can. The reason is what the negotiation note carries,
// so "why is formatting missing" is answerable from a log line.
fn format_refusal(compiler ?vtool.CapabilityReport) string {
	report := compiler or { return 'no compiler was resolved at startup' }
	if !report.supports(.format) {
		return 'the compiler cannot format: ${report.detail_of(.format)}'
	}
	return ''
}

// check_refusal is the same question for diagnostics: a check can be promised
// only when the probe found a compiler that reports findings for a buffer it
// cannot compile. A server that advertised the provider without that would
// answer every request with an error, or worse, with an empty list.
fn check_refusal(compiler ?vtool.CapabilityReport) string {
	report := compiler or { return 'no compiler was resolved at startup' }
	if !report.supports(.check) {
		return 'the compiler cannot check a buffer: ${report.detail_of(.check)}'
	}
	return ''
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
	// One buffer per request, and no workspace diagnostics. A whole workspace
	// pass is its own lane, and claiming it here would promise an answer to
	// `workspace/diagnostic` that this build does not have.
	provider['interFileDependencies'] = json2.Any(false)
	provider['workspaceDiagnostics'] = json2.Any(false)
	return json2.Any(provider)
}

// semantic_tokens_provider advertises the legend the session will use.
//
// Range requests are refused rather than left out of the answer: the walk types
// a whole buffer, and slicing it per request would be a different feature with
// different bugs. A client that asked only for ranges gets no provider at all,
// because there is nothing honest to serve it.
fn semantic_tokens_provider(legend SemanticLegend) json2.Any {
	mut legend_object := map[string]json2.Any{}
	legend_object['tokenTypes'] = json2.Any(legend.token_types.map(json2.Any(it)))
	legend_object['tokenModifiers'] = json2.Any(legend.token_modifiers.map(json2.Any(it)))
	mut provider := map[string]json2.Any{}
	provider['legend'] = json2.Any(legend_object)
	provider['full'] = json2.Any(true)
	provider['range'] = json2.Any(false)
	return json2.Any(provider)
}
