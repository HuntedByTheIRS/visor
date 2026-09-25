module lsp

import json2

// A 3.17 client that advertises synchronization but none of the optional server
// features. It is the shape a minimal editor sends.
const thin_client = '{"textDocument":{"synchronization":{"dynamicRegistration":true}},' +
	'"general":{"positionEncodings":[]}}'

// A client that advertises everything this build can act on.
const rich_client = '{"workspace":{"workspaceFolders":true,"configuration":true,' +
	'"didChangeConfiguration":{"dynamicRegistration":false}},' +
	'"textDocument":{"synchronization":{"dynamicRegistration":true},' +
	'"diagnostic":{"dynamicRegistration":true,"relatedDocumentSupport":false}},' +
	'"window":{"workDoneProgress":true},' +
	'"general":{"positionEncodings":["utf-16","utf-8"]}}'

// A client that advertises nothing at all.
const bare_client = '{}'

fn client_for(client_capabilities string) ClientCapabilities {
	body := '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":${client_capabilities}}}'
	params := parse_message(body).params
	obj := as_object(params) or { panic('params is not an object') }
	values := obj['capabilities'] or { panic('no capabilities in the request') }
	return new_client_capabilities(values)
}

fn caps_from(client_capabilities string) map[string]json2.Any {
	return negotiate(client_for(client_capabilities)).capabilities
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
	caps := caps_from(rich_client)
	assert 'workspace' in caps
	folders := object_at(object_at(caps, 'workspace'), 'workspaceFolders')
	assert is_true(folders, 'supported')
	assert is_true(folders, 'changeNotifications')
	provider := object_at(caps, 'diagnosticProvider')
	assert string_at(provider, 'identifier') == server_name
	// the diag lane cannot schedule a module root yet, so neither of these is
	// claimed.
	assert !is_true(provider, 'interFileDependencies')
	assert !is_true(provider, 'workspaceDiagnostics')
	assert is_true(caps, 'workDoneProgress')
	assert string_at(caps, 'positionEncoding') == 'utf-16'
}

fn test_the_two_client_sets_do_not_produce_the_same_capabilities() {
	thin := caps_from(thin_client)
	rich := caps_from(rich_client)
	assert thin.len != rich.len
	assert 'workspace' !in thin
	assert 'workspace' in rich
	assert 'diagnosticProvider' in rich
	assert 'diagnosticProvider' !in thin
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
	notes := negotiate(client_for(eighteen)).notes
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
	notes := negotiate(client_for(bare_client)).notes
	// one line per capability considered, so a support question has an answer
	// without re-reading the negotiation. Four is what a client that offered
	// nothing gets: sync, workspace folders, diagnostics and progress.
	assert notes.len == 4
	mut sync_note := ''
	for note in notes {
		if note.starts_with('textDocumentSync:') {
			sync_note = note
		}
	}
	assert sync_note.contains('full')
	assert sync_note.contains('did not advertise')
}
