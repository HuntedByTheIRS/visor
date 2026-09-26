module main

// editor_test drives the editor client in plugins/nvim against a real server,
// in a headless editor, and reports one verdict for every editor it is handed.
//
// Run it from the repository root:
//
//   v -o /tmp/visor .
//   v run tools/editor_test.vsh --bin /tmp/visor
//   v run tools/editor_test.vsh --bin /tmp/visor --nvim /opt/nvim-0.11.7/bin/nvim
//
// Two things make this worth a tool rather than a line of shell in CI. The
// floor the client claims (0.11) is checked here instead of trusted, so a run
// against an older editor fails saying so, in words, rather than as a Lua
// error about an API that is not there. And the per-script totals are added
// up: the runner answers 0 or 1, which says a run failed but not how much of
// the suite ran, and a run that printed no checks at all fails here instead of
// passing quietly.
//
// The scripts go through plugins/nvim/test/run.sh so the way an editor is
// started (headless, -u NONE, this directory on the runtimepath) is written
// down in one place.

import os

const usage = 'usage: v run tools/editor_test.vsh --bin <server> [--nvim <editor>]... [--script <script.lua>]...'

// floor is the oldest editor the client supports: 0.11 is where the semantic
// token calls the client starts exist. plugins/nvim/README.md states the same
// floor, and the two are meant to move together.
const floor_major = 0
const floor_minor = 11

// runner is the script that knows how to start an editor with this plugin.
const runner = 'plugins/nvim/test/run.sh'

// Version is the part of an editor's version string the floor is about.
struct Version {
	major int
	minor int
}

// Tally is what one editor's run of the suite came to.
struct Tally {
	editor string
mut:
	version string
	checks  int
	failed  int
	output  string
	problem string
}

// ok reports whether this editor's run is evidence. No checks run is a
// failure: it is what a misconfigured runner looks like, and it must not be
// mistaken for a clean suite.
fn (t Tally) ok() bool {
	return t.problem == '' && t.failed == 0 && t.checks > 0
}

// which resolves a program through PATH the way a shell would, and answers
// empty when there is none.
fn which(program string) string {
	res := os.execute('command -v ${program}')
	if res.exit_code != 0 {
		return ''
	}
	return res.output.trim_space()
}

// version_line runs `--version` and keeps the first line, which is where both
// Neovim and Vim put their version.
fn version_line(editor string) string {
	res := os.execute('${os.quoted_path(editor)} --version')
	if res.exit_code != 0 {
		return ''
	}
	lines := res.output.trim_space().split_into_lines()
	if lines.len == 0 {
		return ''
	}
	return lines[0].trim_space()
}

// to_int reads a run of digits, refusing anything else. A bare cast would
// answer 0 and turn a garbled version string into a pass.
fn to_int(text string) ?int {
	if text == '' {
		return none
	}
	for byte in text.bytes() {
		if byte < u8(`0`) || byte > u8(`9`) {
			return none
		}
	}
	return text.int()
}

// parse_version reads `NVIM v0.12.5` or `NVIM v0.12.0-dev-1234+gabc` and keeps
// the major and minor numbers, which is all the floor is about.
fn parse_version(line string) ?Version {
	for word in line.split(' ') {
		if word.len < 2 || word[0] != `v` || !word[1].is_digit() {
			continue
		}
		parts := word[1..].split('.')
		if parts.len < 2 {
			return none
		}
		major := to_int(parts[0]) or { return none }
		minor := to_int(parts[1]) or { return none }
		return Version{
			major: major
			minor: minor
		}
	}
	return none
}

// meets_floor reports whether the editor is new enough for the client, and the
// sentence to print when it is not.
fn (v Version) meets_floor() bool {
	if v.major != floor_major {
		return v.major > floor_major
	}
	return v.minor >= floor_minor
}

// counts_of sums the per-script totals the runner prints, lines shaped
// `56 checks, 0 failed`.
fn counts_of(output string) (int, int) {
	mut checks := 0
	mut failed := 0
	for line in output.split_into_lines() {
		trimmed := line.trim_space()
		if !trimmed.contains(' checks, ') || !trimmed.ends_with(' failed') {
			continue
		}
		halves := trimmed.split(' checks, ')
		if halves.len != 2 {
			continue
		}
		count := to_int(halves[0]) or { continue }
		misses := to_int(halves[1].split(' ')[0]) or { continue }
		checks += count
		failed += misses
	}
	return checks, failed
}

// value_of reads the argument after a flag, refusing a flag that dangles.
fn value_of(args []string, index int, flag string) string {
	if index + 1 >= args.len {
		eprintln('editor_test: ${flag} needs a value')
		eprintln(usage)
		exit(1)
	}
	return args[index + 1]
}

// run_one runs the suite under one editor and keeps what it printed, so a
// failure can be shown with the checks that failed rather than a bare exit
// code.
fn run_one(editor string, server string, scripts []string, root string) Tally {
	mut tally := Tally{
		editor: editor
	}
	line := version_line(editor)
	if line == '' {
		tally.problem = 'could not run `${editor} --version`'
		return tally
	}
	tally.version = line
	version := parse_version(line) or {
		tally.problem = 'no version in `${line}`'
		return tally
	}
	if !version.meets_floor() {
		tally.problem = 'needs ${floor_major}.${floor_minor} or newer, and this is ${line}'
		return tally
	}
	mut parts := [
		os.quoted_path(os.join_path(root, runner)),
		'--bin',
		os.quoted_path(server),
		'--nvim',
		os.quoted_path(editor),
	]
	for script in scripts {
		parts << os.quoted_path(script)
	}
	res := os.execute(parts.join(' '))
	tally.output = res.output.trim_right('\n')
	tally.checks, tally.failed = counts_of(res.output)
	if res.exit_code != 0 && tally.failed == 0 {
		tally.problem = 'the runner exited ${res.exit_code} without a check failing'
	}
	return tally
}

fn main() {
	root := os.dir(@DIR)
	if !os.exists(os.join_path(root, 'v.mod')) {
		eprintln('editor_test: ${@DIR} is not inside a V module tree')
		exit(1)
	}
	mut server := os.getenv('VISOR_BIN')
	mut editors := []string{}
	mut scripts := []string{}
	args := os.args[1..]
	mut index := 0
	for index < args.len {
		match args[index] {
			'--bin' {
				server = value_of(args, index, '--bin')
				index += 2
			}
			'--nvim' {
				editors << value_of(args, index, '--nvim')
				index += 2
			}
			'--script' {
				scripts << value_of(args, index, '--script')
				index += 2
			}
			'-h', '--help' {
				println(usage)
				exit(0)
			}
			else {
				eprintln('editor_test: unknown argument `${args[index]}`')
				eprintln(usage)
				exit(1)
			}
		}
	}
	if server == '' {
		server = which('visor')
	}
	if server == '' {
		eprintln('editor_test: no server binary. Pass --bin, set \$VISOR_BIN, or put visor on PATH.')
		exit(1)
	}
	if !os.is_executable(server) {
		eprintln('editor_test: ${server} is not executable')
		exit(1)
	}
	if editors.len == 0 {
		found := which('nvim')
		if found == '' {
			eprintln('editor_test: no editor. Pass --nvim, or put nvim on PATH.')
			exit(1)
		}
		editors << found
	}
	if !os.exists(os.join_path(root, runner)) {
		eprintln('editor_test: ${root} does not hold ${runner}')
		exit(1)
	}

	println('editor_test: server ${server}')
	mut tallies := []Tally{}
	for editor in editors {
		tallies << run_one(editor, server, scripts, root)
	}

	mut passed := 0
	mut checks := 0
	mut failed := 0
	for tally in tallies {
		if tally.output != '' {
			println(tally.output)
		}
		if tally.ok() {
			passed++
			checks += tally.checks
			failed += tally.failed
			println('ok   ${tally.version}, ${tally.checks} checks, ${tally.failed} failed')
			continue
		}
		println('FAIL ${tally.editor}')
		if tally.problem != '' {
			println('    ${tally.problem}')
		} else {
			println('    ${tally.checks} checks, ${tally.failed} failed')
		}
	}
	println('')
	if passed < tallies.len {
		println('${tallies.len - passed} failed, ${passed} passed')
		exit(1)
	}
	println('${passed} editor(s), ${checks} checks, no failures')
}
