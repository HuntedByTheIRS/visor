module vtool

import os
import strings
import time

// chunk is how much of a buffer is pushed onto the child's stdin before the
// pipes are read again. Handing over a whole megabyte in one call blocks as
// soon as the kernel's pipe buffer fills, and if the compiler answers on its
// own pipe before draining stdin, both sides wait on each other forever.
const chunk = 32 * 1024

// drain_pause is the idle time between two reads of the child's pipes. Without
// it the drain loop spins a core for as long as the compiler runs.
const drain_pause = 2 * time.millisecond

struct ExecResult {
	stdout    string
	stderr    string
	exit_code int
	// spawn_err marks a call that never started a process. It is kept apart
	// from exit_code because a compiler that failed to start has said nothing
	// about whether it supports a flag.
	spawn_err string
}

// read_pending moves everything the child has already written out of its pipes.
// Each read returns at most 4 KB, so one read per pass would make a long
// diagnostic list trickle out a pause at a time.
fn read_pending(mut p os.Process, mut out strings.Builder, mut errs strings.Builder) {
	for p.is_pending(.stdout) {
		out.write_string(p.stdout_read())
	}
	for p.is_pending(.stderr) {
		errs.write_string(p.stderr_read())
	}
}

// exec runs `cpath` with `input` on stdin and collects both output streams.
//
// Nothing here writes to disk. The buffer travels through the pipe and the
// compiler's own handling of stdin, which is what lets visor diagnose a file
// that has never been saved.
//
// merged sends the child's stderr into the same pipe as its stdout. The check
// path asks for that: diagnostics arrive on stderr, so merging leaves one pipe
// to drain and no second pipe that can fill while nobody reads it. The format
// path keeps the streams apart because its stdout is returned as source.
fn exec(cpath string, args []string, input string, work_folder string, merged bool) ExecResult {
	if !os.is_file(cpath) {
		return ExecResult{
			exit_code: -1
			spawn_err: '${cpath} is not a file'
		}
	}
	if !os.is_executable(cpath) {
		return ExecResult{
			exit_code: -1
			spawn_err: '${cpath} is not executable'
		}
	}
	mut p := os.new_process(cpath)
	p.set_args(args)
	if work_folder != '' {
		p.set_work_folder(work_folder)
	}
	if merged {
		p.set_redirect_stdio_merged()
	} else {
		p.set_redirect_stdio()
	}
	p.run()
	// A compiler that exits before reading the whole buffer leaves the pipe
	// with no reader at the other end. Writing to it then raises SIGPIPE, whose
	// default action kills visor mid-request; the compiler was already gone, so
	// nothing is lost by ignoring the signal and letting the write report the
	// broken pipe, which fd_write already swallows. visor is a server on a pipe
	// of its own, so it wants a closed connection to surface as an error rather
	// than as a silent death either way.
	//
	// The call sits after run() so that the child keeps the default
	// disposition. Only the side doing the writing needs it masked.
	os.signal_ignore(.pipe)
	mut out := strings.new_builder(4096)
	mut errs := strings.new_builder(1024)
	mut written := 0
	for written < input.len {
		next := if written + chunk < input.len { written + chunk } else { input.len }
		p.stdin_write(input[written..next])
		written = next
		read_pending(mut p, mut out, mut errs)
	}
	// Closing the parent's write end is what the compiler reads as end of
	// input. Without it `v -check -` waits on a pipe that will never close.
	// The field is cleared so that close() below does not close a number twice
	// after the kernel hands it to an unrelated open().
	os.fd_close(p.stdio_fd[0])
	p.stdio_fd[0] = -1
	for p.is_alive() {
		read_pending(mut p, mut out, mut errs)
		time.sleep(drain_pause)
	}
	// The child is gone, so both pipes are at end of file and these return what
	// was left in them without blocking. is_alive reaped the child already,
	// which is why wait() here returns straight away; it is still called so the
	// exit code comes from one place.
	out.write_string(p.stdout_slurp())
	errs.write_string(p.stderr_slurp())
	p.wait()
	code := p.code
	p.close()
	return ExecResult{
		stdout:    out.str()
		stderr:    errs.str()
		exit_code: code
	}
}
