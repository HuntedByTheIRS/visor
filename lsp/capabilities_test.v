module lsp

import json2
import vtool

// A 3.17 client that advertises synchronization but none of the optional server
// features. It is the shape a minimal editor sends.
const thin_client = '{"textDocument":{"synchronization":{"dynamicRegistration":true}},' +
	'"general":{"positionEncodings":[]}}'

// A client that advertises everything this build can act on.
const rich_client = '{"workspace":{"workspaceFolders":true,"configuration":true,' +
	'"didChangeConfiguration":{"dynamicRegistration":false},' +
	'"symbol":{"dynamicRegistration":false}},' +
	'"textDocument":{"synchronization":{"dynamicRegistration":true},' +
	'"diagnostic":{"dynamicRegistration":true,"relatedDocumentSupport":false},' +
	'"inlayHint":{"dynamicRegistration":false},' +
	'"documentSymbol":{"hierarchicalDocumentSymbolSupport":true},' +
	'"rename":{"dynamicRegistration":false,"prepareSupport":true}},' +
	'"window":{"workDoneProgress":true},' +
	'"general":{"positionEncodings":["utf-16","utf-8"]}}'

// A client that advertises nothing at all.
const bare_client = '{}'

// A client that offers synchronization and formatting, which is the shape an
// editor with save hooks sends.
const formatting_client = '{"textDocument":{"synchronization":{"dynamicRegistration":true},' +
	'"formatting":{"dynamicRegistration":false}}}'

// A client that offers rename but never the prepare request, which is the shape
// an editor sends when it only ever asks for the rewrite.
const rename_without_prepare_client = '{"textDocument":{"rename":{"dynamicRegistration":false}}}'

fn client_for(client_capabilities string) ClientCapabilities {
	body := '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":${client_capabilities}}}'
	params := parse_message(body).params
	obj := as_object(params) or { panic('params is not an object') }
	values := obj['capabilities'] or { panic('no capabilities in the request') }
	return new_client_capabilities(values)
}

fn caps_from(client_capabilities string) map[string]json2.Any {
	// most of these tests are about negotiation that the compiler has no say in
	return negotiate(client_for(client_capabilities), none).capabilities
}

// caps_with says what the compiler can do, so a test can check the decisions
// that depend on it without one being installed.
fn caps_with(client_capabilities string, compiler ?vtool.CapabilityReport) map[string]json2.Any {
	return negotiate(client_for(client_capabilities), compiler).capabilities
}

// A probe report from a compiler that formats.
fn compiler_that_formats() vtool.CapabilityReport {
	return vtool.CapabilityReport{
		v_version: 'V 0.5.2 test'
		items:     {
			'format': vtool.Capability{
				kind:   .format
				status: .supported
				detail: 'rewrote the probe buffer'
			}
		}
	}
}

// A probe report from a compiler that ran and did not format.
fn compiler_that_cannot_format() vtool.CapabilityReport {
	return vtool.CapabilityReport{
		v_version: 'V 0.5.2 test'
		items:     {
			'format': vtool.Capability{
				kind:   .format
				status: .unsupported
				detail: 'accepted the invocation and wrote nothing back'
			}
		}
	}
}

// A probe report from a compiler that reports findings for a buffer it cannot
// compile, which is what the diagnostics lane needs.
fn compiler_that_checks() vtool.CapabilityReport {
	return vtool.CapabilityReport{
		v_version: 'V 0.5.2 test'
		items:     {
			'check': vtool.Capability{
				kind:   .check
				status: .supported
				detail: 'reported the error written into the probe buffer'
			}
		}
	}
}

// A probe report from a compiler that ran and reported nothing.
fn compiler_that_cannot_check() vtool.CapabilityReport {
	return vtool.CapabilityReport{
		v_version: 'V 0.5.2 test'
		items:     {
			'check': vtool.Capability{
				kind:   .check
				status: .unsupported
				detail: 'the invocation produced no diagnostic for a buffer that cannot compile'
			}
		}
	}
}

fn object_at(obj map[string]json2.Any, key string) map[string]json2.Any {
	value := obj[key] or { panic('${key} is missing') }
	return as_object(value) or { panic('${key} is not an object') }
}

fn int_at(obj map[string]json2.Any, key string) int {
	value := obj[key] or { panic('${key} is missing') }
	return value.int()
}

fn string_at(obj map[string]json2.Any, key string) string {
	value := obj[key] or { panic('${key} is missing') }
	return value.str()
}

fn is_true(obj map[string]json2.Any, key string) bool {
	value := obj[key] or { return false }
	return value is bool && (value as bool)
}

fn test_a_client_that_advertises_synchronization_gets_incremental_sync() {
	caps := caps_from(thin_client)
	sync := object_at(caps, 'textDocumentSync')
	assert int_at(sync, 'change') == 2
	assert is_true(sync, 'openClose')
	assert 'save' in sync
	// a client that never advertised a workspace gets no workspace block.
	assert 'workspace' !in caps
	// and no provider it cannot drive.
	assert 'diagnosticProvider' !in caps
	assert 'workDoneProgress' !in caps
}

fn test_a_client_that_advertises_nothing_gets_full_sync_and_little_else() {
	caps := caps_from(bare_client)
	sync := object_at(caps, 'textDocumentSync')
	// without a promise of ranged edits, the server has to ask for whole files.
	assert int_at(sync, 'change') == 1
	assert 'save' !in sync
	assert 'workspace' !in caps
	assert 'diagnosticProvider' !in caps
	assert 'positionEncoding' !in caps
}

fn test_the_full_client_gets_the_providers_it_advertised() {
	caps := caps_with(rich_client, compiler_that_checks())
	assert 'workspace' in caps
	folders := object_at(object_at(caps, 'workspace'), 'workspaceFolders')
	assert is_true(folders, 'supported')
	assert is_true(folders, 'changeNotifications')
	provider := object_at(caps, 'diagnosticProvider')
	assert string_at(provider, 'identifier') == server_name
	// One buffer per request: a whole workspace pass and the cross-file
	// dependencies that come with it are another lane's work, and both are
	// left out of the claim rather than answered with something smaller.
	assert !is_true(provider, 'interFileDependencies')
	assert !is_true(provider, 'workspaceDiagnostics')
	assert is_true(caps, 'workDoneProgress')
	assert string_at(caps, 'positionEncoding') == 'utf-16'
}

fn test_inlay_hints_are_registered_without_a_resolve() {
	caps := caps_with(rich_client, none)
	provider := object_at(caps, 'inlayHintProvider')
	// Every label is final: the answer is in hand when the request arrives, so
	// a resolve round trip would only be a way to send it later.
	assert !is_true(provider, 'resolveProvider')
	// A client that never offered the capability gets no provider, so it is
	// never told to ask for hints this session cannot place.
	assert 'inlayHintProvider' !in caps_from(bare_client)
	assert 'inlayHintProvider' !in caps_from(thin_client)
}

fn test_a_client_that_offers_symbols_gets_the_symbol_providers() {
	caps := caps_from(rich_client)
	// An outline and a workspace symbol search are both answered from what is
	// in hand, so neither asks the client for a second round trip.
	assert is_true(caps, 'documentSymbolProvider')
	assert is_true(caps, 'workspaceSymbolProvider')
	// A client that offered neither is never told to ask for one.
	assert 'documentSymbolProvider' !in caps_from(bare_client)
	assert 'workspaceSymbolProvider' !in caps_from(bare_client)
	assert 'documentSymbolProvider' !in caps_from(thin_client)
	assert 'workspaceSymbolProvider' !in caps_from(thin_client)
}

fn test_rename_is_registered_with_prepare_only_when_the_client_offers_it() {
	provider := object_at(caps_from(rich_client), 'renameProvider')
	assert is_true(provider, 'prepareProvider')
	// The same feature without the prepare request: rename is still there, and
	// the client is not told about a request it will never send.
	plain := object_at(caps_from(rename_without_prepare_client), 'renameProvider')
	assert !is_true(plain, 'prepareProvider')
	assert 'renameProvider' !in caps_from(bare_client)
}

fn test_the_two_client_sets_do_not_produce_the_same_capabilities() {
	thin := caps_from(thin_client)
	rich := caps_with(rich_client, compiler_that_checks())
	assert thin.len != rich.len
	assert 'workspace' !in thin
	assert 'workspace' in rich
	assert 'diagnosticProvider' in rich
	assert 'diagnosticProvider' !in thin
}

fn test_diagnostics_are_pulled_only_when_the_client_and_the_compiler_allow_it() {
	// The client asked, and the compiler reports nothing, so there is no
	// provider to advertise: the request would fail on every keystroke.
	caps := caps_with(rich_client, compiler_that_cannot_check())
	assert 'diagnosticProvider' !in caps
	notes := negotiate(client_for(rich_client), compiler_that_cannot_check()).notes
	assert notes.any(it.contains('the compiler cannot check a buffer'))

	// No compiler at all is the same answer with a different reason.
	bare := negotiate(client_for(rich_client), none)
	assert 'diagnosticProvider' !in bare.capabilities
	assert bare.notes.any(it.contains('no compiler was resolved at startup'))
}

fn test_pushed_diagnostics_are_a_note_of_their_own() {
	// A client that will draw a pushed finding says so once, and one that does
	// not is served by the pull path. Which of the two this session chose is
	// worth a line in the negotiation record either way.
	pushing := '{"textDocument":{"publishDiagnostics":{"relatedInformation":true}}}'
	notes := negotiate(client_for(pushing), compiler_that_checks()).notes
	assert notes.any(it.contains('publishDiagnostics: pushed'))
	quiet := negotiate(client_for(rich_client), compiler_that_checks()).notes
	assert quiet.any(it.contains('publishDiagnostics: not pushed, the client did not offer'))
}

fn test_position_encoding_is_left_alone_when_the_client_did_not_offer_it() {
	assert 'positionEncoding' !in caps_from(bare_client)
	// the thin client sent an empty list, which is not an offer.
	assert 'positionEncoding' !in caps_from(thin_client)
}

fn test_a_three_eighteen_client_gets_no_virtual_document_provider() {
	// @since 3.18.0. The client offers the content capability and this build has
	// nothing to serve, so the provider stays out of the response.
	eighteen := '{"workspace":{"textDocumentContent":{"schemes":["visor"]}}}'
	assert 'textDocumentContentProvider' !in caps_from(eighteen)
	notes := negotiate(client_for(eighteen), none).notes
	mut mentioned := false
	for note in notes {
		if note.contains('textDocumentContentProvider') {
			mentioned = true
			assert note.contains('3.18')
		}
	}
	assert mentioned
}

fn test_advertises_is_false_for_an_explicit_false_and_for_an_empty_list() {
	off := client_for('{"workspace":{"workspaceFolders":false},"general":{"positionEncodings":[]}}')
	assert !off.advertises('workspace.workspaceFolders')
	assert !off.flag('workspace.workspaceFolders')
	assert off.strings('general.positionEncodings').len == 0
	on := client_for('{"window":{"workDoneProgress":true}}')
	assert on.advertises('window.workDoneProgress')
	assert on.flag('window.workDoneProgress')
}

fn test_at_walks_a_path_and_stops_at_a_non_object() {
	c := client_for('{"window":{"workDoneProgress":true}}')
	assert c.advertises('window.workDoneProgress')
	if _ := c.at('window.nope') {
		assert false
	} else {
		assert true
	}
	if _ := c.at('window.workDoneProgress.deeper') {
		assert false
	} else {
		assert true
	}
}

fn test_configuration_offers_are_read_from_the_client_side() {
	rich := client_for(rich_client)
	assert rich.client_pulls_configuration()
	assert rich.client_pushes_configuration()
	bare := client_for(bare_client)
	assert !bare.client_pulls_configuration()
	assert !bare.client_pushes_configuration()
}

fn test_every_decision_is_written_down() {
	notes := negotiate(client_for(bare_client), none).notes
	// one line per capability considered, so a support question has an answer
	// without re-reading the negotiation. Eleven is what a client that offered
	// nothing gets: sync, formatting, semantic tokens, inlay hints, the
	// document symbols, the workspace symbols, rename, workspace folders, the
	// pull diagnostics provider, the pushed diagnostics and progress.
	assert notes.len == 11
	mut sync_note := ''
	for note in notes {
		if note.starts_with('textDocumentSync:') {
			sync_note = note
		}
	}
	assert sync_note.contains('full')
	assert sync_note.contains('did not advertise')
}

fn test_formatting_is_registered_when_the_client_and_the_compiler_allow_it() {
	caps := caps_with(formatting_client, compiler_that_formats())
	assert is_true(caps, 'documentFormattingProvider')
}

fn test_formatting_is_not_registered_when_the_client_did_not_offer_it() {
	caps := caps_from(thin_client)
	assert 'documentFormattingProvider' !in caps
}

fn test_formatting_is_not_registered_when_the_compiler_cannot_do_it() {
	caps := caps_with(formatting_client, compiler_that_cannot_format())
	assert 'documentFormattingProvider' !in caps
	notes := negotiate(client_for(formatting_client), compiler_that_cannot_format()).notes
	assert notes.any(it.contains('the compiler cannot format'))
}

// A client that offers semantic tokens and asks for whole-document ones, which
// is the shape Neovim sends.
const client_with_tokens = '{"textDocument":{"semanticTokens":' +
	'{"requests":{"range":true,"full":{"delta":true}},"tokenTypes":["type","keyword","comment"],' +
	'"tokenModifiers":["declaration"]}}}'

// The same client, but it only wants ranges.
const client_with_range_tokens = '{"textDocument":{"semanticTokens":' +
	'{"requests":{"range":true,"full":false},"tokenTypes":["type","keyword","comment"],' +
	'"tokenModifiers":["declaration"]}}}'

fn test_semantic_tokens_are_registered_when_the_client_offers_types_the_server_emits() {
	caps := caps_from(client_with_tokens)
	assert 'semanticTokensProvider' in caps
	provider := as_object(caps['semanticTokensProvider'] or {
		panic('the provider is not there')
	}) or { panic('the provider is not an object') }
	legend := as_object(provider['legend'] or { panic('no legend') }) or {
		panic('the legend is not an object')
	}
	// only the three types the client named, in the server's own order
	types := as_array(legend['tokenTypes'] or { panic('no tokenTypes') }) or {
		panic('tokenTypes is not an array')
	}
	assert types.len == 3
	assert types[0].str() == 'type'
	assert types[1].str() == 'keyword'
	assert types[2].str() == 'comment'
}

fn test_semantic_tokens_are_not_registered_without_a_type_the_server_emits() {
	caps := caps_from('{"textDocument":{"semanticTokens":{"tokenTypes":[],"tokenModifiers":[]}}}')
	assert 'semanticTokensProvider' !in caps
	notes := negotiate(client_for('{"textDocument":{"semanticTokens":{"tokenTypes":[]}}}'),
		none).notes
	assert notes.any(it.contains('no token type this server emits'))
}

fn test_semantic_tokens_are_not_registered_for_a_client_that_only_wants_ranges() {
	caps := caps_from(client_with_range_tokens)
	assert 'semanticTokensProvider' !in caps
	notes := negotiate(client_for(client_with_range_tokens), none).notes
	assert notes.any(it.contains('did not ask for whole-document tokens'))
}

fn test_a_session_with_no_compiler_says_so_in_the_notes() {
	notes := negotiate(client_for(formatting_client), none).notes
	assert notes.any(it.contains('no compiler was resolved at startup'))
}
