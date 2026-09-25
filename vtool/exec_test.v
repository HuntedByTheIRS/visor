module vtool

import os
import strings

fn cat() string {
	return os.find_abs_path_of_executable('cat') or { panic('the test environment has no `cat` on PATH') }
}

fn sh() string {
	return os.find_abs_path_of_executable('sh') or { panic('the test environment has no `sh` on PATH') }
}

// A body of text several times the kernel pipe buffer, so a run that moves it
// without deadlocking has exercised both directions rather than sliding through
// in one pipe's worth.
fn big_text() string {
	mut text := strings.new_builder(300 * 1024)
	mut i := 0
	for text.len < 300 * 1024 {
		text.write_string('line ${i}\n')
		i++
	}
	return text.str()
}

fn test_the_buffer_arrives_on_stdin() {
	r := exec(cat(), [], 'fn main() {}\n', '', false)
	assert r.spawn_err == ''
	assert r.exit_code == 0
	assert r.stdout == 'fn main() {}\n'
}

fn test_the_child_sees_end_of_input() {
	// cat prints nothing until stdin closes, so a returned string of the right
	// length is proof that the write end was closed rather than left open.
	r := exec(cat(), [], 'trailing text with no newline', '', false)
	assert r.spawn_err == ''
	assert r.exit_code == 0
	assert r.stdout == 'trailing text with no newline'
}

fn test_a_large_buffer_completes() {
	input := big_text()
	assert input.len > 4 * chunk
	r := exec(cat(), [], input, '', false)
	assert r.spawn_err == ''
	assert r.exit_code == 0
	assert r.stdout.len == input.len
}

fn test_a_large_reply_on_stderr_is_drained() {
	// The unmerged path has two pipes. If the parent waited on stdout while the
	// child filled stderr, neither side would ever move, so this test returning
	// at all is the result being checked, along with the byte count.
	input := big_text()
	r := exec(sh(), ['-c', 'cat 1>&2'], input, '', false)
	assert r.spawn_err == ''
	assert r.exit_code == 0
	assert r.stdout == ''
	assert r.stderr.len == input.len
}

fn test_a_missing_binary_reports_a_spawn_error() {
	r := exec('/nonexistent/definitely-not-a-compiler', [], '', '', false)
	assert r.spawn_err != ''
	assert r.exit_code == -1
}

fn test_a_file_that_cannot_run_reports_a_spawn_error() {
	not_a_program := os.join_path(@DIR, 'exec.v')
	assert os.exists(not_a_program)
	r := exec(not_a_program, [], '', '', false)
	assert r.spawn_err != ''
	assert r.exit_code == -1
}

fn test_the_work_folder_is_the_child_directory() {
	want := os.dir(cat())
	r := exec(sh(), ['-c', 'pwd'], '', want, false)
	assert r.spawn_err == ''
	assert r.exit_code == 0
	assert r.stdout.trim_space() == want
}
