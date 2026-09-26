module lsp

import vtool

// probe_compiler resolves the V binary and probes what it can do. It runs once,
// before the loop reads a frame, and what was learned about it is kept on the
// server.
//
// Resolving it lazily would be worse than a slower startup. A feature that
// discovers a missing compiler halfway through a request has already answered
// initialize, and that answer either promised the client formatting or told the
// client nothing was there. Either way the promise came before the check.
pub fn (mut s Server) probe_compiler() {
	compiler := vtool.find() or {
		s.report_no_compiler(err.msg())
		return
	}
	s.take_compiler(compiler)
}

// take_compiler installs a resolved compiler and probes it. It takes the
// resolution as an argument rather than performing it, so a test can drive a
// binary that does not exist without hiding the real compiler from the process
// it runs in.
pub fn (mut s Server) take_compiler(compiler vtool.Compiler) {
	s.compiler = compiler
	s.compiler_caps = compiler.probe()
}

// report_no_compiler records why the session has no compiler. The message is
// what a person reads, so it is the resolver's own words rather than a
// restatement of them.
pub fn (mut s Server) report_no_compiler(reason string) {
	s.compiler_error = reason
}
