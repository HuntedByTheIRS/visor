module lsp

import io

// ByteReader feeds a fixed string to the frame reader, all at once or a byte at a
// time, which is how the serve loop is driven without spawning a process.
struct ByteReader {
mut:
	data []u8
	pos  int
	step int
}

fn (mut r ByteReader) read(mut buf []u8) !int {
	if r.pos >= r.data.len {
		return io.Eof{}
	}
	left := r.data.len - r.pos
	want := if r.step > 0 && r.step < left { r.step } else { left }
	n := if want < buf.len { want } else { buf.len }
	for i in 0 .. n {
		buf[i] = r.data[r.pos + i]
	}
	r.pos += n
	return n
}

fn loop_over(text string, step int) (&BufferSink, int) {
	mut reader_source := &ByteReader{
		data: text.bytes()
		step: step
	}
	mut reader := new_frame_reader(io.Reader(reader_source))
	// the sink is separate from the frame reader: the loop writes through the
	// server's sink, and this one collects what a real transport would have sent.
	mut sink := &BufferSink{}
	mut server := new_server(sink)
	server.set_version('0.0.1')
	code := serve_loop(mut server, mut reader)
	return sink, code
}

fn test_exit_without_shutdown_ends_with_code_one() {
	text := format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		format_frame('{"jsonrpc":"2.0","method":"initialized","params":{}}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}')
	sink, code := loop_over(text, 0)
	// exit without shutdown is the failure path even inside one batch.
	assert code == 1
	assert sink.messages.len == 1
}

fn test_shutdown_then_exit_ends_with_code_zero() {
	text := format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		format_frame('{"jsonrpc":"2.0","id":2,"method":"shutdown"}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}')
	sink, code := loop_over(text, 0)
	assert code == 0
	assert sink.messages.len == 2
}

fn test_the_loop_runs_frames_that_arrive_one_byte_at_a_time() {
	text := format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		format_frame('{"jsonrpc":"2.0","id":2,"method":"shutdown"}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}')
	_, code := loop_over(text, 1)
	assert code == 0
}

fn test_a_stream_that_ends_without_exit_keeps_the_failure_code() {
	text := format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}')
	_, code := loop_over(text, 0)
	assert code == 1
}

fn test_a_malformed_frame_does_not_stop_the_session() {
	text := 'Content-Length: nope\r\n\r\n' +
		format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		'{not a frame at all' +
		format_frame('{"jsonrpc":"2.0","id":2,"method":"shutdown"}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}')
	mut reader_source := &ByteReader{
		data: text.bytes()
	}
	mut reader := new_frame_reader(io.Reader(reader_source))
	mut sink := &BufferSink{}
	mut server := new_server(sink)
	code := serve_loop(mut server, mut reader)
	// the bad header and the unmeasured run behind it are counted, and the
	// session still reaches shutdown and exit.
	assert server.refused_frames == 2
	assert code == 0
	assert sink.messages.len == 2
}

fn test_a_body_that_is_not_json_gets_a_parse_error() {
	// the frame is well formed, so the body is served and the server answers a
	// parse error with a null id.
	text := format_frame('{not json') +
		format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		format_frame('{"jsonrpc":"2.0","id":2,"method":"shutdown"}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}')
	sink, code := loop_over(text, 0)
	assert code == 0
	assert sink.messages.len == 3
	first := parse_message(sink.messages[0])
	assert first.error_code == code_parse_error
	assert first.id_key() == ''
}

fn test_a_second_session_on_the_same_loop_is_not_possible() {
	// exit ends the loop, and the frames after it in the same batch are not
	// served: a client that sends more after exit is already gone.
	text := format_frame('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}') +
		format_frame('{"jsonrpc":"2.0","id":2,"method":"shutdown"}') +
		format_frame('{"jsonrpc":"2.0","method":"exit"}') +
		format_frame('{"jsonrpc":"2.0","id":3,"method":"shutdown"}')
	sink, code := loop_over(text, 0)
	assert code == 0
	assert sink.messages.len == 2
}
