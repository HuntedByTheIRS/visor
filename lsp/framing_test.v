module lsp

import io

// ChunkReader hands out a fixed number of bytes per read so a test can make a
// frame arrive in pieces, which is what a pipe does under load.
struct ChunkReader {
mut:
	data []u8
	pos  int
	step int
}

fn (mut c ChunkReader) read(mut buf []u8) !int {
	if c.pos >= c.data.len {
		return io.Eof{}
	}
	avail := c.data.len - c.pos
	n := if c.step > 0 && c.step < avail { c.step } else { avail }
	m := if n < buf.len { n } else { buf.len }
	for i in 0 .. m {
		buf[i] = c.data[c.pos + i]
	}
	c.pos += m
	return m
}

fn reader_for(data string, step int) &FrameReader {
	mut c := &ChunkReader{
		data: data.bytes()
		step: step
	}
	return new_frame_reader(io.Reader(c))
}

fn test_reads_a_whole_frame() {
	mut fr := reader_for(format_frame('{"jsonrpc":"2.0","method":"initialized"}'), 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .message
	assert frames[0].body == '{"jsonrpc":"2.0","method":"initialized"}'
	assert frames[0].reason == ''
	assert fr.malformed_frames == 0
}

fn test_reads_a_frame_split_across_reads() {
	text := format_frame('{"jsonrpc":"2.0","method":"initialized","params":{"a":1}}')
	// one byte per read: the header, the blank line and the body all arrive
	// separately, and none of that may be treated as a frame boundary.
	mut fr := reader_for(text, 1)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .message
	assert frames[0].body == '{"jsonrpc":"2.0","method":"initialized","params":{"a":1}}'
	assert fr.malformed_frames == 0
}

fn test_reads_two_frames_in_one_batch() {
	text := format_frame('{"id":1}') + format_frame('{"id":2}')
	mut fr := reader_for(text, 0)
	frames := fr.read_batch()
	assert frames.len == 2
	assert frames[0].body == '{"id":1}'
	assert frames[1].body == '{"id":2}'
	assert fr.read_batch().len == 0
	assert fr.at_eof()
}

fn test_accepts_a_bare_newline_header() {
	mut fr := reader_for('Content-Length: 8\n\n{"id":1}', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].body == '{"id":1}'
}

fn test_content_length_is_matched_case_insensitively() {
	mut fr := reader_for('content-length: 8\r\n\r\n{"id":1}', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].body == '{"id":1}'
}

fn test_malformed_header_does_not_kill_the_next_frame() {
	// the first block has no Content-Length, so it cannot be framed. The reader
	// drops it and the good frame after it still has to come through.
	text := 'X-Nonsense: 1\r\n\r\n' + format_frame('{"id":7}')
	mut fr := reader_for(text, 0)
	frames := fr.read_batch()
	assert frames.len == 2
	assert frames[0].kind == .malformed
	assert frames[0].reason.contains('Content-Length')
	assert frames[1].kind == .message
	assert frames[1].body == '{"id":7}'
	assert fr.malformed_frames == 1
}

fn test_non_numeric_content_length_is_refused() {
	mut fr := reader_for('Content-Length: soon\r\n\r\n{}', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .malformed
	assert frames[0].reason.contains('Content-Length')
}

fn test_content_length_over_the_limit_is_refused() {
	mut fr := reader_for('Content-Length: 99999999999\r\n\r\n', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .malformed
	assert frames[0].reason.contains('limit')
}

fn test_garbage_between_frames_does_not_swallow_the_next_frame() {
	// a bad Content-Length leaves the reader without a byte count, so whatever
	// follows the block is unmeasured. The frame after it still has to arrive.
	text := 'Content-Length: nope\r\n\r\n' + '{garbage' + format_frame('{"id":9}')
	mut fr := reader_for(text, 0)
	frames := fr.read_batch()
	assert frames.len == 2
	assert frames[0].kind == .malformed
	assert frames[1].kind == .message
	assert frames[1].body == '{"id":9}'
}

fn test_stream_ending_inside_a_frame_is_reported_once() {
	mut fr := reader_for('Content-Length: 40\r\n\r\n{"id":1}', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .malformed
	assert frames[0].reason.contains('inside a frame')
	// the leftover bytes are reported once, not on every later call.
	assert fr.read_batch().len == 0
	assert fr.at_eof()
}

fn test_a_zero_length_body_is_an_empty_message() {
	mut fr := reader_for('Content-Length: 0\r\n\r\n', 0)
	frames := fr.read_batch()
	assert frames.len == 1
	assert frames[0].kind == .message
	assert frames[0].body == ''
}

fn test_format_frame_is_the_wire_format() {
	out := format_frame('{"id":1}')
	assert out == 'Content-Length: 8\r\n\r\n{"id":1}'
	// the body is not followed by a newline: a client that reads to the next
	// blank line would otherwise hang.
	assert !out.ends_with('\n')
}
