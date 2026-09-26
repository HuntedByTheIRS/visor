module main

// check_warnings is this tree's warning gate. It compiles every module, runs
// vet over the repository, and fails when any of that prints a diagnostic.
//
//   v run tools/check_warnings.vsh
//
// Four passes:
//
//   sweep    `v -shared -check` over every directory holding V sources.
//            -shared is what lets one command cover a module directory and a
//            program directory alike. Without it, a directory holding no `main`
//            module answers with an error about the missing `main` module and
//            nothing else.
//   programs `v -check` over every file in a directory that holds standalone
//            programs, where one sweep per file is the only thing that works.
//   tests    `v -check` over every `_test.v` file, which the package sweep
//            skips: V ignores test files when it compiles a package.
//   vet      `v vet .`: missing documentation, and the compiler's suggestions
//            about code that can be written better.
//   build    `v -o <tmp> .`: the shipping binary, where link errors and C
//            compiler complaints land.
//
// Silence is the pass condition. vet exits 0 while printing warnings, and the
// compiler prints notices without failing, so no exit code can carry the
// verdict here. Any line printed by any pass fails the gate.
//
// Every run proves the gate can go red: it plants a type error and an
// undocumented public function in a scratch directory and checks that two of
// the passes report them. A gate that cannot fail is not evidence that the tree
// is clean.
//
// The compiler is not pinned, and the gate prints the version it ran against,
// because a V upgrade that adds a warning turns this red with no commit behind
// it.

import os

const usage = 'usage: v run tools/check_warnings.vsh'

// skipped_dirs holds the trees that are not compiled into anything: git's own
// state, the local tooling state, and the test fixtures.
const skipped_dirs = ['.git', '.omh', 'testdata']

// program_dirs holds directories that are not modules: each `.v` file in them is
// a program of its own, so sweeping the directory would collide on `main`. The
// files are checked one at a time instead, and the directory sweep leaves them
// alone.
const program_dirs = ['tree_sitter_v/examples']

// compiler is the V that built this script, so the gate checks the tree with
// the same compiler the caller used.
const compiler = @VEXE

// Finding is one pass that printed something the gate cannot accept.
struct Finding {
	target string
	cmd    string
	output string
}

// Targets is what the walk found: the directories holding checked-in V sources,
// and the test files, which the compiler reads on a separate pass.
struct Targets {
mut:
	dirs  []string
	tests []string
}

struct Gate {
mut:
	passed   int
	findings []Finding
}

// check records one pass. Silence and a zero exit are the only passing outcome.
fn (mut g Gate) check(target string, cmd string) {
	res := os.execute(cmd)
	if res.exit_code == 0 && res.output.trim_space() == '' {
		g.passed++
		println('ok   ${target}')
		return
	}
	g.findings << Finding{
		target: target
		cmd:    cmd
		output: res.output.trim_space()
	}
	println('FAIL ${target}')
}

// expects_reported reads the same pass the other way around: the command has to
// print something, or the gate is blind.
fn (mut g Gate) expects_reported(target string, cmd string) {
	res := os.execute(cmd)
	if res.exit_code != 0 || res.output.trim_space() != '' {
		g.passed++
		println('ok   ${target}')
		return
	}
	g.findings << Finding{
		target: target
		cmd:    cmd
		output: 'the pass printed nothing'
	}
	println('FAIL ${target}')
}

// walk collects the build targets under root. A directory holding only tests is
// not a target of its own, and the fixtures are data.
fn walk(root string) Targets {
	mut found := Targets{}
	mut pending := [root]
	for pending.len > 0 {
		current := pending.pop()
		mut holds_source := false
		for entry in os.ls(current) or { []string{} } {
			full := os.join_path(current, entry)
			if os.is_dir(full) {
				if entry !in skipped_dirs {
					pending << full
				}
				continue
			}
			if !entry.ends_with('.v') {
				continue
			}
			if entry.ends_with('_test.v') {
				found.tests << full
			} else {
				holds_source = true
			}
		}
		if holds_source {
			found.dirs << current
		}
	}
	found.dirs.sort()
	found.tests.sort()
	return found
}

// name reports a path the way the run prints it.
fn name(root string, path string) string {
	if path == root {
		return '.'
	}
	if path.starts_with(root) {
		return path[root.len + 1..]
	}
	return path
}

fn sweep_dir(path string) string {
	return '${compiler} -shared -check ${os.quoted_path(path)}'
}

fn check_file(path string) string {
	return '${compiler} -check ${os.quoted_path(path)}'
}

fn vet_cmd(path string) string {
	return '${compiler} vet ${os.quoted_path(path)} -nocolor'
}

// prove_it_can_fail plants the two findings the gate exists to catch, one per
// kind of pass, and reads them the same way the real run does.
fn (mut g Gate) prove_it_can_fail() {
	scratch := os.join_path(os.temp_dir(), 'visor-check-warnings-planted')
	os.rmdir_all(scratch) or {}
	os.mkdir_all(scratch) or {
		g.findings << Finding{
			target: 'the gate can fail'
			output: 'could not create ${scratch}: ${err}'
		}
		return
	}
	os.write_file(os.join_path(scratch, 'planted.v'), 'module planted\n\npub fn planted(x int) string {\n\treturn x\n}\n') or {
		g.findings << Finding{
			target: 'the gate can fail'
			output: 'could not write the planted module: ${err}'
		}
		return
	}
	g.expects_reported('sweep notices a type error', sweep_dir(scratch))
	g.expects_reported('vet notices an undocumented public function', vet_cmd(scratch))
	os.rmdir_all(scratch) or {}
}

fn main() {
	if os.args.len > 1 {
		eprintln(usage)
		exit(1)
	}
	root := os.dir(@DIR)
	if !os.exists(os.join_path(root, 'v.mod')) {
		eprintln('check_warnings: ${@DIR} is not inside a V module tree')
		exit(1)
	}
	println('check_warnings: ${os.execute('${compiler} version').output.trim_space()}')
	mut gate := Gate{}
	found := walk(root)
	if found.dirs.len == 0 {
		eprintln('check_warnings: no V sources under ${root}')
		exit(1)
	}
	for path in found.dirs {
		if name(root, path) in program_dirs {
			continue
		}
		gate.check('sweep ${name(root, path)}', sweep_dir(path))
	}
	for dir in program_dirs {
		full := os.join_path(root, dir)
		entries := os.ls(full) or {
			gate.findings << Finding{
				target: 'programs ${dir}'
				output: 'could not list ${full}: ${err}'
			}
			continue
		}
		mut programs := []string{}
		for entry in entries {
			if entry.ends_with('.v') {
				programs << os.join_path(full, entry)
			}
		}
		programs.sort()
		if programs.len == 0 {
			gate.findings << Finding{
				target: 'programs ${dir}'
				output: 'no programs under ${full}'
			}
		}
		for program in programs {
			gate.check('program ${name(root, program)}', check_file(program))
		}
	}
	for path in found.tests {
		gate.check('tests ${name(root, path)}', check_file(path))
	}
	gate.check('vet', vet_cmd(root))
	gate.check('build', '${compiler} -o ${os.quoted_path(os.join_path(os.temp_dir(), 'visor-check-warnings'))} ${os.quoted_path(root)}')
	gate.prove_it_can_fail()
	println('')
	if gate.findings.len > 0 {
		for finding in gate.findings {
			println('--- ${finding.target}')
			println('    \$ ${finding.cmd}')
			println(finding.output)
			println('')
		}
		println('${gate.findings.len} failed, ${gate.passed} passed')
		exit(1)
	}
	println('${gate.passed} passes, no warnings and no errors')
}
