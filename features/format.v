// features answers the questions an editor asks.
//
// The answers are plain data. Nothing here knows about JSON-RPC, because the
// wire belongs to lsp/: a feature that takes a buffer and a compiler and returns
// an edit can be tested without a client, and the encoding of that edit lives in
// one place instead of in every feature.
module features

import vtool

// DocumentEdit replaces the bytes between start_byte and end_byte with new_text.
// The offsets are bytes into the buffer, because that is what the compiler and
// the parse tree speak; the wire layer turns them into positions a client
// counts.
pub struct DocumentEdit {
pub:
	start_byte int
	end_byte   int
	new_text   string
}

// FormatResult is what the buffer needs after `v fmt` saw it.
pub struct FormatResult {
pub:
	edits []DocumentEdit
	// unchanged is the case where the buffer already matches what the formatter
	// writes. An empty edit list alone would not say whether that was the reason
	// or the formatter did nothing at all.
	unchanged bool
}

// format_buffer runs the buffer through `v fmt -` and returns the edit that
// brings it in line, or no edits when it is already in line.
//
// The edit covers the whole buffer. `v fmt` formats whole files and has no mode
// for a region, so a smaller edit would claim a precision the formatter does not
// have.
pub fn format_buffer(compiler vtool.Compiler, buffer string) !FormatResult {
	formatted := compiler.format(buffer)!
	if formatted == buffer {
		return FormatResult{
			unchanged: true
		}
	}
	return FormatResult{
		edits: [
			DocumentEdit{
				start_byte: 0
				end_byte:   buffer.len
				new_text:   formatted
			},
		]
	}
}
