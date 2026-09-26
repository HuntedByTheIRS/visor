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
	// The diag lane implements this. Until it lands the method answers with a
	// request-failed error naming the lane, because an empty diagnostic list
	// would read as a file with no problems.
	s.stub('textDocument/diagnostic', 'the diag lane')
}
