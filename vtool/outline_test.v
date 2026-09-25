module vtool

import os

fn compiler() Compiler {
	return find() or { panic(err.msg()) }
}

// This module's own source, so the test has a real file to outline without
// writing one.
fn a_source_file() string {
	return os.join_path(@DIR, 'outline.v')
}

fn test_returns_the_json_the_compiler_prints() {
	report := compiler().probe()
	got := compiler().ast(a_source_file(), report) or { panic(err.msg()) }
	assert got.trim_space().starts_with('{')
	assert got.contains('"files"')
	assert got.contains('"kind"')
}

fn test_the_positions_carry_no_line_and_no_column() {
	// The point of the gate on this call. If positions ever grow a line, this
	// test is the place that notices and the outline code can be revisited.
	report := compiler().probe()
	got := compiler().ast(a_source_file(), report) or { panic(err.msg()) }
	assert got.contains('"offset"')
	assert !got.contains('"line"')
	assert !got.contains('"col"')
}

fn test_a_probe_that_says_unsupported_stops_the_call() {
	// A compiler build with no ast subcommand is not asked at all, because an
	// empty answer from it would look like an empty file.
	blocked := CapabilityReport{
		items: {
			'ast_outline': Capability{
				kind:   .ast_outline
				status: .unsupported
				detail: 'no such subcommand'
			}
		}
	}
	compiler().ast(a_source_file(), blocked) or {
		assert err.msg().contains('unsupported')
		assert err.msg().contains('no such subcommand')
		return
	}
	assert false
}

fn test_a_probe_with_no_ast_entry_at_all_stops_the_call() {
	// Nothing was probed, so nothing is known, and not knowing is not a licence
	// to call the subcommand and pass an empty result on.
	compiler().ast(a_source_file(), CapabilityReport{}) or {
		assert err.msg().contains('unknown')
		return
	}
	assert false
}

fn test_a_file_that_does_not_exist_is_an_error() {
	report := compiler().probe()
	compiler().ast('/nonexistent/source.v', report) or {
		assert err.msg().contains('does not exist')
		return
	}
	assert false
}
