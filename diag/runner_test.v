module diag

import vtool

// A buffer that parses everything except its third line, so the one diagnostic
// it earns has a known line and column.
const broken = 'fn main() {\n\tx := \n}\n'

const clean = 'fn main() {\n\tprintln(1)\n}\n'

// The give-away in the name V invents for the temporary source it parses a
// stdin buffer into. Spelling it here rather than importing it keeps this test
// reading the compiler's output rather than a constant from the layer it tests.
const compiler_temp_marker = '.v3_stdin_'

fn compiler() vtool.Compiler {
	return vtool.find() or { panic(err.msg()) }
}

fn test_an_unsaved_buffer_is_checked_through_the_pipe() {
	// Nothing is written for this: the text travels on stdin, and the report
	// comes back against the path the caller named. That is the whole reason a
	// buffer nobody has saved can be diagnosed at all.
	job := Job{
		uri:     'file:///tmp/proj/main.v'
		path:    '/tmp/proj/main.v'
		version: 1
		text:    broken
	}
	result := check(job, compiler()) or { panic(err.msg()) }
	assert result.has_error
	assert result.exit_code == 1
	assert result.diagnostics.len == 1
	d := result.diagnostics[0]
	assert d.file == '/tmp/proj/main.v'
	assert d.line == 3
	assert d.col == 1
	assert d.severity == .error
	assert d.message.contains('unexpected token')
	// The substitution has something to do: the compiler's own name for the
	// buffer is in the raw output, and it is not in the diagnostic.
	assert result.raw.contains(compiler_temp_marker), 'the raw output names no temporary file: ${result.raw}'
	assert !d.file.contains(compiler_temp_marker)
}

fn test_a_clean_unsaved_buffer_reports_nothing_and_exits_zero() {
	job := Job{
		uri:     'file:///tmp/proj/main.v'
		path:    '/tmp/proj/main.v'
		version: 1
		text:    clean
	}
	result := check(job, compiler()) or { panic(err.msg()) }
	assert !result.has_error
	assert result.exit_code == 0
	assert result.diagnostics.len == 0
}
