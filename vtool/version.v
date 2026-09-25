module vtool

// Version is one `v version` line taken apart.
pub struct Version {
pub:
	// raw is the line as printed. A bug report should quote this rather than
	// reassembling it from the fields.
	raw    string
	major  int
	minor  int
	patch  int
	commit string
}

// version runs `v version` and parses the single line it prints.
//
// The weekly V drift job compares this against the release visor was built for,
// so the version is read as data rather than shown as a string.
pub fn (c Compiler) version() !Version {
	r := exec(c.abs_path, ['version'], '', '', false)
	if r.spawn_err != '' {
		return error(r.spawn_err)
	}
	if r.exit_code != 0 {
		return error('`${c.abs_path} version` exited ${r.exit_code}: ${r.stderr.trim_space()}')
	}
	return parse_version(r.stdout)
}

// parse_version reads the `V 0.5.2 1b68924` shape.
//
// The commit is whatever the third field holds. V has printed both a short hash
// and a hash with a suffix there, and neither is used for a decision, so it is
// kept as text.
pub fn parse_version(output string) !Version {
	raw := output.trim_space()
	fields := raw.fields()
	if fields.len < 2 || fields[0] != 'V' {
		return error('cannot read a V version from `${raw}`')
	}
	numbers := fields[1].split('.')
	if numbers.len < 3 {
		return error('cannot read a V version from `${raw}`')
	}
	major := digits(numbers[0]) or { return error('cannot read a V version from `${raw}`') }
	minor := digits(numbers[1]) or { return error('cannot read a V version from `${raw}`') }
	// A pre-release suffix sticks to the patch number, as in `0.5.2-beta`, and
	// the suffix does not change which release this is.
	patch := digits(numbers[2].split('-')[0]) or {
		return error('cannot read a V version from `${raw}`')
	}
	commit := if fields.len > 2 { fields[2] } else { '' }
	return Version{
		raw:    raw
		major:  major
		minor:  minor
		patch:  patch
		commit: commit
	}
}

// digits reads a run of decimal digits.
//
// V's own string.int() answers zero for text it cannot read, which would turn
// `V x.y.z` into version 0.0.0 and hand back a release that never existed.
fn digits(text string) ?int {
	if text == '' {
		return none
	}
	mut value := 0
	for ch in text {
		if !ch.is_digit() {
			return none
		}
		value = value * 10 + int(ch - `0`)
	}
	return value
}
