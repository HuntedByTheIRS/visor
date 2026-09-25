module lsp

import io

// A frame larger than this is refused instead of buffered. A didOpen carries a
// whole file, so the ceiling has to be generous, but Content-Length is client
// controlled and an 8 GB value should not become an 8 GB allocation.
pub const max_frame_bytes = 16 * 1024 * 1024

// A header block that never terminates is garbage rather than a slow client.
const max_header_bytes = 8 * 1024

// One read syscall worth of bytes. Frames are read into an accumulator, so the
// chunk size only decides how often we go back to the stream.
const read_chunk = 4096

pub enum FrameKind {
	message
	malformed
}

pub struct Frame {
pub:
	kind FrameKind
	// body is the JSON-RPC payload with the header block stripped. It is empty
	// for a malformed frame.
	body string
	// reason explains a malformed frame and is empty otherwise.
	reason string
}

// FrameReader turns a byte stream into frames. It keeps the bytes it could not
// turn into a frame yet, which is what lets a frame arrive in pieces.
pub struct FrameReader {
mut:
	r io.Reader
	// buf holds bytes that arrived but have not been consumed as frames.
	buf []u8
	// eof records that the stream ended. It is sticky: once true, fill stops
	// asking the reader.
	eof bool
	// trailing records that the leftover bytes at end of stream were already
	// reported, so they are reported once and not on every later call.
	trailing bool
pub mut:
	// malformed_frames counts frames the reader refused. The server keeps
	// running after each of them, so this is the only trace that they happened.
	malformed_frames int
}

pub fn new_frame_reader(r io.Reader) &FrameReader {
	return &FrameReader{
		r: r
	}
}

// read_batch returns every frame the stream currently holds. It blocks only
// when nothing is buffered, and then only until the first bytes arrive. An
// empty result means the stream ended and nothing is left to parse.
//
// Frames are handed back in a batch rather than one at a time on purpose:
// $/cancelRequest is acted on for the whole batch before any handler runs, so a
// client that writes a request and its cancellation together still gets the
// cancellation applied.
pub fn (mut fr FrameReader) read_batch() []Frame {
	mut out := []Frame{}
	for {
		for {
			f := fr.take() or { break }
			out << f
		}
		if out.len > 0 {
			return out
		}
		if !fr.fill() {
			if fr.buf.len > 0 && !fr.trailing {
				fr.trailing = true
				fr.malformed_frames++
				lost := fr.buf.len
				fr.buf = []
				return [Frame{
					kind:   .malformed
					reason: 'stream ended inside a frame with ${lost} bytes unread'
				}]
			}
			return out
		}
	}
	// not reachable: the loop only leaves through a return. The checker wants
	// the path spelled out.
	return out
}

// at_eof reports that the stream is done and nothing is left over.
pub fn (fr &FrameReader) at_eof() bool {
	return fr.eof && fr.buf.len == 0
}

// take parses one frame out of the buffer, or returns none when the buffer does
// not hold a whole frame yet. A frame it cannot use comes back as a malformed
// frame so the caller never has to distinguish "wait" from "drop".
fn (mut fr FrameReader) take() ?Frame {
	block := header_end(fr.buf) or {
		if fr.buf.len > max_header_bytes {
			fr.buf = []
			fr.malformed_frames++
			return Frame{
				kind:   .malformed
				reason: 'header block did not end within ${max_header_bytes} bytes'
			}
		}
		return none
	}
	length := content_length(fr.buf[..block.start]) or {
		fr.drop(block.after)
		fr.malformed_frames++
		return Frame{
			kind:   .malformed
			reason: 'header block without a usable Content-Length'
		}
	}
	if length > max_frame_bytes {
		fr.drop(block.after)
		fr.malformed_frames++
		return Frame{
			kind:   .malformed
			reason: 'Content-Length ${length} is over the ${max_frame_bytes} byte limit'
		}
	}
	if fr.buf.len < block.after + length {
		return none
	}
	body := fr.buf[block.after..block.after + length].bytestr()
	fr.drop(block.after + length)
	return Frame{
		kind: .message
		body: body
	}
}

// drop removes the first n bytes from the buffer. The copy keeps a short frame
// from pinning a large backing array that an earlier frame allocated.
fn (mut fr FrameReader) drop(n int) {
	if n >= fr.buf.len {
		fr.buf = []
		return
	}
	fr.buf = fr.buf[n..].clone()
}

// fill reads one chunk into the buffer. It reports false once the stream is
// done, whatever the reason it ended. A reader error and a clean end of stream
// are treated the same: there is nothing more to parse either way.
fn (mut fr FrameReader) fill() bool {
	if fr.eof {
		return false
	}
	mut chunk := []u8{len: read_chunk}
	n := fr.r.read(mut chunk) or {
		fr.eof = true
		return false
	}
	if n <= 0 {
		fr.eof = true
		return false
	}
	fr.buf << chunk[..n]
	return true
}

struct HeaderBlock {
	// start is the offset of the terminator, after is the first body byte.
	start int
	after int
}

// header_end finds the blank line that closes the header block. The transport
// speaks CRLF, but a lone LF pair is accepted too: clients that get that wrong
// are common enough that rejecting them buys nothing.
fn header_end(buf []u8) ?HeaderBlock {
	text := buf.bytestr()
	crlf := text.index('\r\n\r\n') or { -1 }
	lf := text.index('\n\n') or { -1 }
	if crlf < 0 && lf < 0 {
		return none
	}
	if crlf < 0 || (lf >= 0 && lf < crlf) {
		return HeaderBlock{
			start: lf
			after: lf + 2
		}
	}
	return HeaderBlock{
		start: crlf
		after: crlf + 4
	}
}

// content_length reads the Content-Length header out of a header block. The
// name is matched case insensitively because the spec spells it
// Content-Length and clients have been seen to spell it content-length.
fn content_length(block []u8) ?int {
	text := block.bytestr()
	for line in text.split_into_lines() {
		colon := line.index(':') or { continue }
		name := line[..colon].trim_space().to_lower()
		if name != 'content-length' {
			continue
		}
		value := line[colon + 1..].trim_space()
		if value == '' {
			return none
		}
		for ch in value {
			if ch < `0` || ch > `9` {
				return none
			}
		}
		return value.int()
	}
	return none
}

// format_frame is the byte string that carries one message. The header is the
// only newline the transport adds: the body is written exactly as it is.
pub fn format_frame(body string) string {
	return 'Content-Length: ${body.len}\r\n\r\n${body}'
}
