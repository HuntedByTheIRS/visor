module lsp

import io
import os

// StdoutSink writes one frame per message on file descriptor 1. fd_write loops
// until the whole frame is out, which is what the framing needs: a half written
// frame leaves the client waiting for bytes that never come.
pub struct StdoutSink {}

pub fn (mut s StdoutSink) send(message string) {
	os.fd_write(1, format_frame(message))
}

// serve_stdio runs the protocol loop on standard input and output and returns
// the code the process should exit with.
pub fn serve_stdio(version string) int {
	mut input := os.stdin()
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
