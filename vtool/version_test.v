module vtool

fn test_parses_the_release_line() {
	v := parse_version('V 0.5.2 1b68924\n') or { panic(err.msg()) }
	assert v.major == 0
	assert v.minor == 5
	assert v.patch == 2
	assert v.commit == '1b68924'
	assert v.raw == 'V 0.5.2 1b68924'
}

fn test_parses_a_longer_commit_hash() {
	v := parse_version('V 0.5.2 1b68924a3f0c') or { panic(err.msg()) }
	assert v.patch == 2
	assert v.commit == '1b68924a3f0c'
}

fn test_parses_a_prerelease_suffix() {
	v := parse_version('V 0.5.2-beta.1 abc1234') or { panic(err.msg()) }
	assert v.major == 0
	assert v.minor == 5
	assert v.patch == 2
	assert v.commit == 'abc1234'
}

fn test_parses_a_line_without_a_commit() {
	v := parse_version('V 1.2.3') or { panic(err.msg()) }
	assert v.major == 1
	assert v.minor == 2
	assert v.patch == 3
	assert v.commit == ''
}

fn test_rejects_output_that_is_not_a_version() {
	parse_version('version\n') or { return }
	assert false
}

fn test_rejects_output_with_too_few_numbers() {
	parse_version('V 0.5 abc1234') or { return }
	assert false
}

fn test_rejects_numbers_that_are_not_numbers() {
	parse_version('V x.y.z abc1234') or { return }
	assert false
}

fn test_runs_the_compiler_this_machine_has() {
	c := find() or { panic(err.msg()) }
	v := c.version() or { panic(err.msg()) }
	assert v.raw.starts_with('V ')
	assert v.commit != ''
	// visor targets V 0.5 and later. A floor rather than an exact match, so a
	// newer V is not a failing test, and an older one is.
	assert v.major > 0 || v.minor >= 5, 'visor needs V 0.5 or later, got ${v.raw}'
}
