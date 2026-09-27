module diag

import vtool

// check runs one job through the compiler.
//
// This is the only place visor starts a compiler for diagnostics, and it goes
// through vtool like every other compiler call: the buffer travels on stdin, so
// a file that has never been saved is checked like any other and nothing is
// written into the workspace beside it.
pub fn check(job Job, compiler vtool.Compiler) !vtool.CheckResult {
	return compiler.check(job.text, job.root, job.path)
}
