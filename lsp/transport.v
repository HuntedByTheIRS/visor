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
	return serve_loop(mut server, mut reader)
}

// serve_loop reads a batch of frames and serves them until the exit
// notification arrives or the stream ends.
//
// A stream that ends without exit means the client is gone rather than done, so
// the code stays 1: the only clean ending is shutdown then exit.
pub fn serve_loop(mut s Server, mut fr FrameReader) int {
	for {
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
