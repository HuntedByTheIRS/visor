module vtool

import os

fn compiler() Compiler {
	return find() or { panic(err.msg()) }
}

// An executable that is not a compiler. It answers, and it exits zero, which is
// exactly the reply that must not be mistaken for a working flag.
fn not_a_compiler() string {
	for name in ['echo', 'true', 'sh'] {
		if found := os.find_abs_path_of_executable(name) {
			return found
		}
	}
	panic('the test environment has no echo, true or sh on PATH')
}

fn test_a_real_compiler_supports_every_flag() {
	report := compiler().probe()
	assert report.items.len == 4
	assert report.v_version.starts_with('V ')
	assert report.v_version_error == ''
	for kind in all_kinds {
		status := report.status_of(kind)
		assert status == .supported, '${kind.str()} came back ${status.str()}: ${report.detail_of(kind)}'
		assert report.supports(kind)
	}
}

fn test_a_program_that_is_not_a_compiler_reports_unsupported() {
	fake := not_a_compiler()
	c := find_from_env({
		env_command: fake
	}) or { panic(err.msg()) }
	report := c.probe()
	// Every flag is accounted for, so an empty report cannot be mistaken for a
	// clean bill of health.
	assert report.items.len == 4
	for kind in all_kinds {
		status := report.status_of(kind)
		assert status == .unsupported, '${kind.str()} came back ${status.str()}'
		assert report.supports(kind) == false
	}
}

fn test_an_unsupported_flag_says_what_the_program_did_instead() {
	c := find_from_env({
		env_command: not_a_compiler()
	}) or { panic(err.msg()) }
	report := c.probe()
	assert report.detail_of(.check) != ''
	assert report.detail_of(.format) != ''
	// The version call fails against the same binary, which is recorded rather
	// than thrown away.
	assert report.v_version == ''
	assert report.v_version_error != ''
}

fn test_a_path_that_cannot_run_is_unknown_not_unsupported() {
	// @DIR is a directory. It exists, so the path is real, and no process can
	// start from it, which is what unknown is for.
	not_runnable := Compiler{
		abs_path: @DIR
		origin:   'test'
	}
	for kind in all_kinds {
		got := not_runnable.probe_kind(kind)
		assert got.status == .unknown, '${kind.str()} came back ${got.status.str()}'
		assert got.detail != ''
	}
}

fn test_a_missing_compiler_probes_as_unknown() {
	missing := Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	report := missing.probe()
	assert report.items.len == 4
	assert report.status_of(.check) == .unknown
	assert report.v_version == ''
	assert report.v_version_error.contains('not a file')
}

fn test_one_kind_can_be_probed_on_its_own() {
	got := compiler().probe_kind(.check)
	assert got.kind == .check
	assert got.status == .supported
}
