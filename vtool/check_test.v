module vtool

import os

// A buffer that parses everything except its third line, so the single
// diagnostic it earns has a known line and column.
const broken = 'fn main() {\n\tx := \n}\n'

// Nothing wrong here at all.
const clean = 'fn main() {\n\tprintln(1)\n}\n'

// The compiler only prints a warning when it also has an error to report, and
// an unused import only warns outside `module main`. This buffer arranges both:
// the warning about `os` sits on line 3, and the missing main module is the
// error on line 1.
const warns_about_an_import = 'module foo\n\nimport os\n\npub fn f() int {\n\treturn 1\n}\n'

// One notice and one error, so a run with more than one diagnostic and more
// than one severity is covered.
const notice_and_error = 'fn main() {\n\tx := 1\n\tif true {\n\t\tx := 2\n\t\tprintln(x)\n\t}\n\tprintln(x)\n}\n'

fn compiler() Compiler {
	return find() or { panic(err.msg()) }
}

fn test_a_clean_buffer_reports_nothing() {
	r := compiler().check(clean, '', '/tmp/clean.v') or { panic(err.msg()) }
	assert r.exit_code == 0
	assert r.has_error == false
	assert r.diagnostics.len == 0
	assert r.raw == ''
}

fn test_a_broken_buffer_reports_one_error() {
	r := compiler().check(broken, '', '/tmp/broken.v') or { panic(err.msg()) }
	assert r.has_error == true
	assert r.exit_code == 1
	assert r.diagnostics.len == 1
	d := r.diagnostics[0]
	assert d.severity == .error
	assert d.line == 3
	assert d.col == 1
	assert d.message.contains('unexpected token')
}

fn test_the_compilers_temporary_name_becomes_the_callers_path() {
	// The name has to be substituted, not merely tolerated: the compiler names
	// its own temporary source, and that name is nowhere on disk.
	want := '/home/someone/project/src/main.v'
	r := compiler().check(broken, '', want) or { panic(err.msg()) }
	assert r.raw.contains(stdin_marker), 'the substitution has nothing to do: ${r.raw}'
	assert r.diagnostics.len == 1
	assert r.diagnostics[0].file == want
}

fn test_no_returned_diagnostic_names_the_compilers_temporary_file() {
	r := compiler().check(notice_and_error, '', 'buffer.v') or { panic(err.msg()) }
	assert r.diagnostics.len > 0
	for d in r.diagnostics {
		assert !d.file.contains(stdin_marker)
	}
}

fn test_a_notice_and_an_error_both_come_back() {
	r := compiler().check(notice_and_error, '', 'buffer.v') or { panic(err.msg()) }
	assert r.has_error == true
	assert r.diagnostics.len == 2
	mut levels := map[Severity]int{}
	for d in r.diagnostics {
		levels[d.severity] = (levels[d.severity] or { 0 }) + 1
	}
	assert levels[.notice] == 1
	assert levels[.error] == 1
	notice := r.diagnostics.filter(it.severity == .notice)[0]
	assert notice.line == 3
	assert notice.col == 5
	assert notice.message.contains('always true')
	problem := r.diagnostics.filter(it.severity == .error)[0]
	assert problem.line == 4
	assert problem.col == 3
	assert problem.message.contains('redefinition')
}

fn test_a_warning_keeps_its_severity() {
	r := compiler().check(warns_about_an_import, '', 'buffer.v') or { panic(err.msg()) }
	warnings := r.diagnostics.filter(it.severity == .warning)
	assert warnings.len == 1
	w := warnings[0]
	assert w.line == 3
	assert w.col == 8
	assert w.message.contains('never used')
	assert w.file == 'buffer.v'
}

fn test_a_missing_compiler_is_an_error_not_an_empty_result() {
	broken_compiler := Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	broken_compiler.check(clean, '', 'buffer.v') or {
		assert err.msg().contains('not a file')
		return
	}
	assert false
}

fn test_a_root_that_does_not_exist_still_returns_diagnostics() {
	// The child ignores a chdir that fails, so a wrong root costs import
	// resolution rather than the whole check.
	r := compiler().check(broken, '/nonexistent/root', 'buffer.v') or { panic(err.msg()) }
	assert r.diagnostics.len == 1
}

fn test_checking_leaves_no_files_behind() {
	before := os.ls(@DIR) or { panic(err.msg()) }
	compiler().check(broken, @DIR, os.join_path(@DIR, 'never_written.v')) or {
		panic(err.msg())
	}
	after := os.ls(@DIR) or { panic(err.msg()) }
	assert after.len == before.len
	for name in after {
		assert !name.contains(stdin_marker), 'a temporary source was left behind: ${name}'
	}
}

fn test_a_warning_line_maps_to_warning() {
	output := "src/main.v:3:8: warning: module 'os' is imported but never used\n    1 | module foo\n"
	diags := parse_diagnostics(output, 'src/main.v')
	assert diags.len == 1
	assert diags[0].severity == .warning
	assert diags[0].file == 'src/main.v'
	assert diags[0].line == 3
	assert diags[0].col == 8
	assert diags[0].message == "module 'os' is imported but never used"
}

fn test_a_notice_line_maps_to_notice() {
	output := 'src/main.v:3:5: notice: condition is always true\n'
	diags := parse_diagnostics(output, 'src/main.v')
	assert diags.len == 1
	assert diags[0].severity == .notice
	assert diags[0].line == 3
	assert diags[0].col == 5
}

fn test_a_path_holding_a_colon_still_yields_a_position() {
	output := 'odd:name.v:12:7: error: something\n'
	diags := parse_diagnostics(output, '')
	assert diags.len == 1
	assert diags[0].file == 'odd:name.v'
	assert diags[0].line == 12
	assert diags[0].col == 7
}

fn test_context_lines_are_not_diagnostics() {
	// V prints the quoted source under a line-number gutter. A context line that
	// happens to hold numbers separated by colons must not be read as a second
	// finding.
	output := 'a.v:4:5: error: real\n    4 | a:9:8: error: copy'
	diags := parse_diagnostics(output, 'a.v')
	assert diags.len == 1
	assert diags[0].message == 'real'
	assert diags[0].line == 4
	assert diags[0].col == 5
}

fn test_the_banner_above_the_findings_is_not_a_diagnostic() {
	output := 'Compiler output from the default V compiler:\na.v:1:1: error: real\n'
	diags := parse_diagnostics(output, 'a.v')
	assert diags.len == 1
	assert diags[0].message == 'real'
}

fn test_lines_that_are_not_diagnostics_are_skipped() {
	output := 'a.v:1:1: error:\na.v:x:y: error: bad col\na.v:1: error: no col\nnot a diagnostic\n'
	diags := parse_diagnostics(output, 'a.v')
	assert diags.len == 0
}
