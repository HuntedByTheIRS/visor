module vtool

// CapabilityStatus is what the probe learned about one flag visor leans on.
pub enum CapabilityStatus {
	// supported means the compiler ran the invocation and produced the shape of
	// output the matching call parses. A clean exit code on its own is not
	// enough: a program that accepts every argument and prints nothing would
	// pass that test, and then every buffer would look clean.
	supported
	// unsupported means the compiler ran and did not do the thing. detail holds
	// what it said instead.
	unsupported
	// unknown means no process ran, so nothing was learned about the flags. A
	// path that points at something other than a compiler lands here, and it is
	// kept apart from unsupported because it says nothing about the flags.
	unknown
}

// CapabilityKind names the invocations visor depends on.
pub enum CapabilityKind {
	check
	check_syntax
	ast_outline
	format
}

// all_kinds is written out because V has no enum iterator, and a report that
// quietly skipped a kind would look the same as one where every kind passed.
pub const all_kinds = [
	CapabilityKind.check,
	CapabilityKind.check_syntax,
	CapabilityKind.ast_outline,
	CapabilityKind.format,
]

// Capability is one probe result.
pub struct Capability {
pub:
	kind   CapabilityKind
	status CapabilityStatus
	detail string
}

// CapabilityReport is every probe result plus the version they were measured
// against.
pub struct CapabilityReport {
pub:
	// v_version is the line `v version` answered with. A bug report should state
	// it, because a flag probe is only meaningful against a named compiler.
	v_version string
	// v_version_error is set when that call failed. The flags are still probed,
	// since a compiler that cannot report its version may well check code.
	v_version_error string
	items           map[string]Capability
}

pub fn (r CapabilityReport) status_of(kind CapabilityKind) CapabilityStatus {
	item := r.items[kind.str()] or { Capability{ kind: kind, status: .unknown } }
	return item.status
}

pub fn (r CapabilityReport) detail_of(kind CapabilityKind) string {
	item := r.items[kind.str()] or { Capability{ kind: kind, status: .unknown } }
	return item.detail
}

pub fn (r CapabilityReport) supports(kind CapabilityKind) bool {
	return r.status_of(kind) == .supported
}

// The probe buffers are written to fail on purpose. A probe run against a clean
// buffer could not tell a working `-check` from a compiler that ignores stdin,
// because both stay quiet.
const probe_broken = 'fn main() {\n\tx := \n}\n'

// The formatter rewrites double quotes to single ones, so finding the single
// quoted spelling in the reply is what shows the buffer was read and formatted
// rather than echoed back.
const probe_unformatted = 'fn   main(){\nprintln("x")\n}\n'
const probe_formatted = "println('x')"

// probe runs every capability check and records the version it ran against.
pub fn (c Compiler) probe() CapabilityReport {
	mut items := map[string]Capability{}
	for kind in all_kinds {
		items[kind.str()] = c.probe_kind(kind)
	}
	mut raw := ''
	mut version_error := ''
	if v := c.version() {
		raw = v.raw
	} else {
		version_error = err.msg()
	}
	return CapabilityReport{
		v_version:       raw
		v_version_error: version_error
		items:           items
	}
}

// probe_kind asks one question: does this compiler do the thing visor needs
// from that invocation?
pub fn (c Compiler) probe_kind(kind CapabilityKind) Capability {
	match kind {
		.check {
			return expect_diagnostic(kind, exec(c.abs_path, ['-check', '-nocolor', '-'],
				probe_broken, '', true))
		}
		.check_syntax {
			return expect_diagnostic(kind, exec(c.abs_path, ['-check-syntax', '-nocolor', '-'],
				probe_broken, '', true))
		}
		.ast_outline {
			// Asking for no file at all prints the subcommand's usage, which
			// names the exact invocation visor makes. Nothing is read and
			// nothing is written this way.
			return expect_outline(kind, exec(c.abs_path, ['ast'], '', '', false))
		}
		.format {
			return expect_format(kind, exec(c.abs_path, ['fmt', '-'], probe_unformatted, '', false))
		}
	}
}

// expect_diagnostic covers both check modes. A compile error against the probe
// buffer is what shows the flag exists and that the diagnostic shape the parser
// reads is the one the compiler prints.
fn expect_diagnostic(kind CapabilityKind, r ExecResult) Capability {
	if r.spawn_err != '' {
		return Capability{ kind: kind, status: .unknown, detail: r.spawn_err }
	}
	if r.exit_code != 0 && r.stdout.contains('error:') {
		return Capability{
			kind:   kind
			status: .supported
			detail: 'reported the error written into the probe buffer'
		}
	}
	if r.stdout.trim_space() == '' {
		return Capability{
			kind:   kind
			status: .unsupported
			detail: 'the invocation produced no diagnostic for a buffer that cannot compile'
		}
	}
	return Capability{ kind: kind, status: .unsupported, detail: first_line(r.stdout) }
}

// expect_outline reads the usage text `v ast` prints when it is given no file.
// The text naming `v ast -p` is the signal, because that is the invocation the
// outline path makes.
fn expect_outline(kind CapabilityKind, r ExecResult) Capability {
	if r.spawn_err != '' {
		return Capability{ kind: kind, status: .unknown, detail: r.spawn_err }
	}
	said := r.stdout + '\n' + r.stderr
	if said.contains('unknown command') {
		return Capability{ kind: kind, status: .unsupported, detail: first_line(said) }
	}
	if said.contains('v ast -p') {
		return Capability{ kind: kind, status: .supported, detail: 'listed the `v ast -p` invocation' }
	}
	return Capability{ kind: kind, status: .unsupported, detail: first_line(said) }
}

// expect_format asks for the formatted spelling of the probe buffer. A zero
// exit code does not carry that weight on its own: a command that echoes its
// own arguments would satisfy it.
fn expect_format(kind CapabilityKind, r ExecResult) Capability {
	if r.spawn_err != '' {
		return Capability{ kind: kind, status: .unknown, detail: r.spawn_err }
	}
	if r.exit_code == 0 && r.stdout.contains(probe_formatted) {
		return Capability{ kind: kind, status: .supported, detail: 'rewrote the probe buffer' }
	}
	if r.stdout.trim_space() == '' && r.stderr.trim_space() == '' {
		return Capability{
			kind:   kind
			status: .unsupported
			detail: 'accepted the invocation and wrote nothing back'
		}
	}
	return Capability{ kind: kind, status: .unsupported, detail: first_line(r.stdout + '\n' + r.stderr) }
}

// first_line reduces a compiler's output to one line a person can act on. The
// banner V prints above its findings is skipped so that a rejection is what
// comes back rather than boilerplate.
fn first_line(text string) string {
	for line in text.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('Compiler output from') {
			continue
		}
		return trimmed
	}
	return 'said nothing'
}
