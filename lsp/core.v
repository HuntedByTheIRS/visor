module lsp

// register_core wires the methods the protocol core answers by itself. Feature
// lanes add theirs with on(), and a lane that implements a method currently
// stubbed here takes the stub out of the table.
fn (mut s Server) register_core() {
	s.on('initialize', handle_initialize)
	s.on('initialized', handle_initialized)
	s.on('shutdown', handle_shutdown)
	s.on('exit', handle_exit)
	s.on('textDocument/didOpen', handle_did_open)
	s.on('textDocument/didChange', handle_did_change)
	s.on('textDocument/didClose', handle_did_close)
	s.on('textDocument/didSave', handle_did_save)
	s.on('workspace/didChangeConfiguration', handle_did_change_configuration)
	s.on('workspace/didChangeWorkspaceFolders', handle_did_change_workspace_folders)
	// Formatting is the first feature lane to land. It answers only when the
	// startup probe found a compiler that formats, and the capability set says
	// the same thing, so a client is never told to ask for something that would
	// come back as an error.
	s.on('textDocument/formatting', handle_formatting)
	// Semantic tokens are the other lane that answers today. They come from the
	// buffer's parse tree, so a file that does not compile is highlighted like
	// any other, and the capability set only advertises them when the client
	// named token types this server can emit.
	s.on('textDocument/semanticTokens/full', handle_semantic_tokens_full)
	// Diagnostics answer both ways round. A pull is served from the buffer the
	// client holds, and a push goes out after an edit settles, so neither of
	// them needs the file to have been saved. The capability set advertises the
	// provider only when the client offers the request and the compiler can
	// report a finding at all.
	s.on('textDocument/diagnostic', handle_diagnostic)
	// Inlay hints are the lane that reads the workspace index rather than the
	// buffer alone. A request is answered from the parse the session holds for
	// that buffer, so the answer describes the text in front of the person and
	// not the last save.
	s.on('textDocument/inlayHint', handle_inlay_hint)
}
