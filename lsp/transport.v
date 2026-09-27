module lsp

import io
import os

// StdoutSink writes one frame per message on file descriptor 1. fd_write loops
// until the whole frame is out, which is what the framing needs: a half written
// frame leaves the client waiting for bytes that never come.
pub struct StdoutSink {}

// send writes one framed message to standard output, blocking until the whole frame is out.
pub fn (mut s StdoutSink) send(message string) {
	os.fd_write(1, format_frame(message))
}

#include <unistd.h>

// RawStdin reads file descriptor 0 with the read syscall. Going through os.File
// would use libc's fread, and fread on a pipe keeps reading until it has the
// whole requested count or the stream ends: an editor that sends one frame and
// waits for the reply would wait for the reply that cannot come. One read
// syscall returns whatever bytes are there.
//
// Only the POSIX read is wired. A Windows port needs _read from io.h, and
// nothing in this repository builds for Windows yet.
struct RawStdin {}

fn (mut r RawStdin) read(mut buf []u8) !int {
	n := int(C.read(0, buf.data, usize(buf.len)))
	if n <= 0 {
		return error('the client closed its end of the stream')
	}
	return n
}

// serve_stdio runs the protocol loop on standard input and output and returns
// the code the process should exit with.
pub fn serve_stdio(version string) int {
	mut input := RawStdin{}
	mut reader := new_frame_reader(io.Reader(&input))
	mut sink := &StdoutSink{}
	mut server := new_server(sink)
	server.set_version(version)
	// before the loop, so the initialize reply already knows whether the compiler
	// the feature lanes need is there.
	server.probe_compiler()
	return serve_loop(mut server, mut reader)
}

#include <poll.h>

// poll_in is the poll event for "there are bytes to read".
const poll_in = 1

struct C.pollfd {
	fd      int
	events  i16
	revents i16
}

fn C.poll(fds &C.pollfd, nfds u64, timeout i32) int

// client_ready reports whether the client has bytes waiting, waiting up to
// timeout_ms for them. A negative timeout waits as long as the client takes.
//
// read(2) alone blocks until the client speaks, which would hold a scheduled
// check until the next keystroke. poll(2) is what lets the loop come back when
// a check falls due with the editor quiet.
//
// os.fd_is_pending is not the same question: it is a readiness check that never
// waits.
fn client_ready(timeout_ms int) bool {
	mut waiting := C.pollfd{
		fd:     0
		events: poll_in
	}
	if C.poll(&waiting, 1, timeout_ms) <= 0 {
		return false
	}
	return (waiting.revents & poll_in) != 0
}

// serve_loop reads a batch of frames and serves them until the exit
// notification arrives or the stream ends.
//
// A stream that ends without exit means the client is gone rather than done, so
// the code stays 1: the only clean ending is shutdown then exit.
pub fn serve_loop(mut s Server, mut fr FrameReader) int {
	for {
		// With nothing buffered, the wait for the client is shared with the
		// checks a buffer's edits earned. Sleeping on the client alone would
		// hold a report until the next keystroke arrived.
		wait := s.quiet_for_ms(clock())
		if !fr.has_bytes_waiting() && wait >= 0 && (wait == 0 || !client_ready(int(wait))) {
			s.pump_diagnostics(clock())
			continue
		}
		frames := fr.read_batch()
		if frames.len == 0 {
			return s.code_on_exit()
		}
		s.serve_batch(frames)
		if s.wants_exit() {
			return s.code_on_exit()
		}
	}
	return s.code_on_exit()
}
