module lsp

import vtool

// The probe runs before the loop reads a frame, so this is what a session that
// never got that far has: a server that knows whether it has a compiler.
fn test_a_server_with_no_compiler_keeps_the_reason() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.report_no_compiler('no compiler on PATH')
	assert s.compiler == none
	assert s.compiler_caps == none
	assert s.compiler_error == 'no compiler on PATH'
}

fn test_the_startup_probe_records_what_the_compiler_can_do() {
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.probe_compiler()
	assert s.compiler_error == ''
	found := s.compiler or { panic('no compiler was resolved') }
	assert found.abs_path != ''
	report := s.compiler_caps or { panic('the probe left no report') }
	// the compiler this project builds against can format and can check. A
	// report that says otherwise is a finding about the compiler rather than
	// about this test.
	assert report.supports(.format)
	assert report.supports(.check)
	assert report.v_version != '' || report.v_version_error != ''
}

fn test_a_compiler_that_cannot_run_is_reported_as_unknown() {
	// A path that is not a compiler says nothing about what the compiler can do,
	// which is why the probe keeps unknown apart from unsupported.
	missing := vtool.Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	mut sink := &BufferSink{}
	mut s := new_server(sink)
	s.take_compiler(missing)
	report := s.compiler_caps or { panic('a probe of a missing binary still reports') }
	assert !report.supports(.format)
	assert report.status_of(.format) == .unknown
	assert report.detail_of(.format).contains('not a file')
}
