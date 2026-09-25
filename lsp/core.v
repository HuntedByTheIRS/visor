module lsp

// register_core wires the methods the protocol core answers by itself. Feature
// lanes add theirs with on(), and a lane that implements a method currently
// stubbed here takes the stub out of the table.
fn (mut s Server) register_core() {
	s.on('initialize', handle_initialize)
	s.on('initialized', handle_initialized)
	s.on('shutdown', handle_shutdown)
	s.on('exit', handle_exit)
	// The diag lane implements this. Until it lands the method answers with a
	// request-failed error naming the lane, because an empty diagnostic list
	// would read as a file with no problems.
	s.stub('textDocument/diagnostic', 'the diag lane')
}
