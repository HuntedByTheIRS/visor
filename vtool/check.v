module vtool

// stdin_marker is the give-away in the file name V invents for the temporary
// source it parses a stdin buffer into. Seeing it is the only way to tell a
// diagnostic about the caller's buffer from one about a file on disk.
const stdin_marker = '.v3_stdin_'

// Severity is the level the compiler tagged a diagnostic with.
pub enum Severity {
	error
	warning
	notice
}

// Diagnostic is one compiler finding, with a position a feature can use.
pub struct Diagnostic {
pub:
	// file is the path the caller asked about, never the compiler's own name
	// for the buffer. Passing that name on would put a path in the editor's
	// error list that does not exist on disk.
	file     string
	line     int
	col      int
	severity Severity
	message  string
}

// CheckResult is one pass of `v -check` over a buffer.
pub struct CheckResult {
pub:
	diagnostics []Diagnostic
	exit_code   int
	// has_error comes from the exit code, not from the diagnostics. The exit
	// status counts failures the compiler reports without a line this parser
	// recognises, and a buffer that fails has to be seen to fail.
	has_error bool
	// raw keeps the compiler's output as it arrived, for logging and for the
	// person reporting a diagnostic that came back wrong.
	raw string
}

// check runs `v -check -nocolor -` over the buffer and returns its diagnostics.
//
// root, when set, is the compiler's working folder, so imports resolve against
// the module the buffer belongs to. path is the name the caller wants to see on
// the diagnostics; the compiler's own name for the buffer is never passed on.
pub fn (c Compiler) check(buffer string, root string, path string) !CheckResult {
	r := exec(c.abs_path, ['-check', '-nocolor', '-'], buffer, root, true)
	if r.spawn_err != '' {
		return error(r.spawn_err)
	}
	return CheckResult{
		diagnostics: parse_diagnostics(r.stdout, path)
		exit_code:   r.exit_code
		has_error:   r.exit_code != 0
		raw:         r.stdout
	}
}

// parse_diagnostics reads the header lines out of compiler output and ignores
// the rest of it. The banner the compiler prints above its findings and the
// quoted source under each one are skipped by shape rather than by recognising
// their text, which would tie visor to one wording.
pub fn parse_diagnostics(output string, path string) []Diagnostic {
	mut found := []Diagnostic{}
	for line in output.split_into_lines() {
		found << parse_diagnostic(line, path) or { continue }
	}
	return found
}

fn parse_diagnostic(line string, path string) ?Diagnostic {
	// A diagnostic header starts at column zero with the file name. Everything
	// else the compiler prints around its findings is indented: the quoted
	// source sits under a right-aligned line-number gutter. Without this, a
	// context line that happens to hold a run of numbers separated by colons
	// would read as a diagnostic of its own.
	if line == '' || line.starts_with(' ') || line.starts_with('	') {
		return none
	}
	mut cut := -1
	mut severity := Severity.error
	for candidate in [Severity.error, Severity.warning, Severity.notice] {
		at := line.index_(': ${candidate.str()}: ')
		if at < 0 {
			continue
		}
		if cut < 0 || at < cut {
			cut = at
			severity = candidate
		}
	}
	if cut < 0 {
		return none
	}
	name := severity.str()
	message := line[cut + name.len + 4..].trim_space()
	if message == '' {
		return none
	}
	// `<file>:<line>:<col>` is read from the right, so a path that itself holds
	// a colon still yields the two numbers.
	where := line[..cut].split(':')
	if where.len < 3 {
		return none
	}
	col := where[where.len - 1].int()
	line_number := where[where.len - 2].int()
	if line_number < 1 || col < 1 {
		return none
	}
	file := where[..where.len - 2].join(':')
	if file == '' {
		return none
	}
	return Diagnostic{
		file:     if file.contains(stdin_marker) { path } else { file }
		line:     line_number
		col:      col
		severity: severity
		message:  message
	}
}
