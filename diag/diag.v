// diag schedules the compiler runs that produce diagnostics.
//
// A check starts a whole compiler, so starting one per keystroke is a process
// storm. This module is the policy between the editor's edits and the compiler:
// an edit is absorbed while the buffer is still moving, a check runs once the
// buffer settles, and a result for a version the buffer has left behind is
// dropped rather than published to a client that has already moved on.
//
// The compiler is reached through vtool, and nothing here knows about the
// protocol. What comes out is a Report; where that report goes belongs to lsp/.
module diag

import vtool

// Policy is what a session allows the scheduler to spend.
pub struct Policy {
pub:
	// debounce_ms is how long a buffer has to sit still before it is checked.
	// An edit inside the window moves the check later instead of adding one,
	// which is what keeps a burst of typing down to a single compiler run.
	debounce_ms int
	// max_per_pass caps how many checks one pass starts. Checks run on the
	// serving thread, so this is what stops a burst across several modules
	// from holding that thread for as long as the burst lasts.
	max_per_pass int
	// max_per_root caps how many checks a single module root may have running
	// at once. One is the useful setting: two buffers in the same module are
	// checked against the same tree, and the second run would read the same
	// sources as the first.
	max_per_root int
}

// default_policy is what the server runs with. The numbers are a judgement
// rather than a measurement: 250 ms is longer than a typing pause and shorter
// than a person noticing, and a V check of a single module takes longer than
// the debounce either way.
pub fn default_policy() Policy {
	return Policy{
		debounce_ms:  250
		max_per_pass: 2
		max_per_root: 1
	}
}

// Job is one check waiting to run: the text, and the names the diagnostics come
// back with.
pub struct Job {
pub:
	uri string
	// path is what the diagnostics name. It is the caller's path, never the
	// temporary name the compiler invents for a buffer it read on stdin.
	path string
	// root is the compiler's working folder, so imports resolve against the
	// module the buffer belongs to. Empty leaves the compiler where it is.
	root string
	// version is the buffer version the text belongs to.
	version int
	text    string
}

// Report is one finished check, tied to the version it checked.
pub struct Report {
pub:
	uri     string
	version int
	// result_id is what a client sends back to ask whether anything changed.
	// It doubles as the version, because that is exactly what makes a report
	// stale: any edit moves the version and earns a new one.
	result_id   string
	diagnostics []vtool.Diagnostic
	// has_error comes from the compiler's exit code rather than from the
	// diagnostics, so a failure reported without a line this server can place
	// is still visible to whoever reads the report.
	has_error bool
}

// Standing is what the caller knows about the document a check ran for: the
// version it holds now, and whether it exists at all.
//
// Both halves come from outside the scheduler, and both of them decide whether
// a finished check is worth anything. A buffer that moved makes the report
// stale, and one that closed makes it unreachable, including for a document
// that is opened again later at the same version.
pub struct Standing {
pub:
	// open is false when the document was closed while the compiler ran.
	open    bool
	version int
}

// Pull is what a textDocument/diagnostic request can be answered with.
pub enum Pull {
	// unchanged means the client echoed this report's id and the buffer still
	// holds the version it was computed from.
	unchanged
	// cached means there is a report for the buffer's current version, so the
	// answer is known without starting a compiler.
	cached
	// fresh means the buffer has to be checked before it can be answered.
	fresh
}
