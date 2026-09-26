module lsp

import json2

// Position is an LSP position. Both fields are counted from zero, and character
// counts UTF-16 code units, not bytes.
pub struct Position {
pub:
	line      int
	character int
}

pub struct Range {
pub:
	start Position
	end   Position
}

// TextDocumentItem is the textDocument argument of didOpen and, without the
// text, of didChange and didSave.
pub struct TextDocumentItem {
pub:
	uri         string
	language_id string
	version     int
	text        string
}

// ContentChange is one entry of a didChange list. has_range is false for a
// whole-document replacement, which LSP allows even under incremental sync.
pub struct ContentChange {
pub:
	has_range bool
	range     Range
	text      string
}

pub struct TextDocument {
pub:
	uri         string
	language_id string
	version     int
	text        string
}

// DocumentStore holds the buffers the client has open. It is the only copy of a
// file that exists between saves, so the ranged edits have to land exactly where
// the client meant, down to the code unit.
pub struct DocumentStore {
mut:
	documents map[string]TextDocument
pub mut:
	// stale_updates counts didChange notifications carrying a version that did
	// not increase. The text is still applied, because the client's buffer is
	// what it just sent, but the count is the only sign the two sides disagree.
	stale_updates int
	// duplicate_opens counts didOpen for a document that was already open.
	duplicate_opens int
	// changes_applied counts individual content changes that landed.
	changes_applied int
}

// open_document stores the buffer from a didOpen. Opening a document that is
// already open is counted, and the newer text wins.
pub fn (mut ds DocumentStore) open_document(item TextDocumentItem) {
	if item.uri in ds.documents {
		ds.duplicate_opens++
	}
	ds.documents[item.uri] = TextDocument{
		uri:         item.uri
		language_id: item.language_id
		version:     item.version
		text:        item.text
	}
}

// close_document drops the buffer. It reports whether there was one to drop.
pub fn (mut ds DocumentStore) close_document(uri string) bool {
	if uri !in ds.documents {
		return false
	}
	ds.documents.delete(uri)
	return true
}

// save_document records a save. An empty text means the client sent no text with
// the save, which is the usual case: the buffer on disk is the one we hold.
pub fn (mut ds DocumentStore) save_document(uri string, text string) bool {
	if uri !in ds.documents {
		return false
	}
	if text != '' && text != ds.documents[uri].text {
		mut doc := ds.documents[uri]
		doc = TextDocument{
			uri:         doc.uri
			language_id: doc.language_id
			version:     doc.version
			text:        text
		}
		ds.documents[uri] = doc
	}
	return true
}

// apply_changes runs a didChange list against the stored buffer. Each change is
// applied to the result of the one before it, which is what incremental sync
// promises the client.
pub fn (mut ds DocumentStore) apply_changes(uri string, version int, changes []ContentChange) !TextDocument {
	if uri !in ds.documents {
		return error('${uri} is not open')
	}
	mut doc := ds.documents[uri]
	if version <= doc.version {
		ds.stale_updates++
	}
	mut text := doc.text
	for change in changes {
		text = apply_change(text, change)
		ds.changes_applied++
	}
	doc = TextDocument{
		uri:         doc.uri
		language_id: doc.language_id
		version:     version
		text:        text
	}
	ds.documents[uri] = doc
	return doc
}

// get returns the stored buffer for uri, or none when it is not open.
pub fn (ds &DocumentStore) get(uri string) ?TextDocument {
	if uri !in ds.documents {
		return none
	}
	return ds.documents[uri]
}

// is_open reports whether uri has a stored buffer.
pub fn (ds &DocumentStore) is_open(uri string) bool {
	return uri in ds.documents
}

// count returns the number of open buffers.
pub fn (ds &DocumentStore) count() int {
	return ds.documents.len
}

// uris returns the uri of every open buffer.
pub fn (ds &DocumentStore) uris() []string {
	return ds.documents.keys()
}

// apply_change splices one change into the text. A change without a range
// replaces everything, which is how a client that lost track resynchronises.
fn apply_change(text string, change ContentChange) string {
	if !change.has_range {
		return change.text
	}
	mut start := offset_for(text, change.range.start)
	mut end := offset_for(text, change.range.end)
	if end < start {
		// a backwards range is a client bug. Reading it as an insertion is the
		// option least likely to corrupt the rest of the buffer.
		end = start
	}
	if start > text.len {
		start = text.len
	}
	if end > text.len {
		end = text.len
	}
	return text[..start] + change.text + text[end..]
}

// offset_for turns a position into a byte offset into the UTF-8 text. LSP counts
// in UTF-16 code units, so a position past an astral character is not a byte
// count and using one would cut a rune in half.
//
// A position past the end of a line clamps to the end of that line, and a line
// past the end of the document clamps to the end of the text. Clients do send
// both, usually just after an edit they had not echoed back yet.
pub fn offset_for(text string, pos Position) int {
	mut offset := 0
	mut line := 0
	for line < pos.line && offset < text.len {
		if text[offset] == `\n` {
			line++
		}
		offset++
	}
	if line < pos.line {
		return text.len
	}
	mut units := 0
	for offset < text.len && units < pos.character {
		if text[offset] == `\n` {
			break
		}
		width, runes := utf8_width(text[offset])
		if units + runes > pos.character {
			// the position splits a surrogate pair. Land before the character
			// rather than inside it.
			break
		}
		units += runes
		offset += width
	}
	return offset
}

// utf8_width reads the width in bytes and in UTF-16 code units of the character
// starting at the lead byte. The four prefixes are the whole of UTF-8, and a
// byte that is not a lead byte, including a truncated rune at end of text, is
// counted as one unit so the caller always advances.
fn utf8_width(lead u8) (int, int) {
	if lead < 0x80 {
		return 1, 1
	}
	if lead & 0xe0 == 0xc0 {
		return 2, 1
	}
	if lead & 0xf0 == 0xe0 {
		return 3, 1
	}
	if lead & 0xf8 == 0xf0 {
		return 4, 2
	}
	return 1, 1
}

// position_for_offset is the other half of offset_for: it turns a byte offset
// back into the position a client counts, so a feature that reads byte offsets
// out of a parse tree can answer in the code units the wire speaks. Without it
// every position after the first non-ASCII character is short by one unit per
// astral character.
//
// An offset past the end of the text clamps to the end of it, and one that
// lands inside a character reports where that character starts, which is what
// offset_for does with a position that splits one.
pub fn position_for_offset(text string, offset int) Position {
	mut limit := offset
	if limit < 0 {
		limit = 0
	}
	if limit > text.len {
		limit = text.len
	}
	mut line := 0
	mut units := 0
	mut at := 0
	for at < limit {
		if text[at] == `\n` {
			line++
			units = 0
			at++
			continue
		}
		width, runes := utf8_width(text[at])
		if at + width > limit {
			// the offset is inside this character, so the position is the one
			// it starts at.
			break
		}
		units += runes
		at += width
	}
	return Position{
		line:      line
		character: units
	}
}

// parse_position reads a position out of the wire shape.
pub fn parse_position(value json2.Any) ?Position {
	obj := as_object(value) or { return none }
	line := obj['line'] or { return none }
	character := obj['character'] or { return none }
	return Position{
		line:      line.int()
		character: character.int()
	}
}

// parse_range reads a range out of the wire shape.
pub fn parse_range(value json2.Any) ?Range {
	obj := as_object(value) or { return none }
	return Range{
		start: parse_position(obj['start'] or { return none }) or { return none }
		end:   parse_position(obj['end'] or { return none }) or { return none }
	}
}

// parse_text_document reads the textDocument argument. languageId and text are
// optional because didChange and didSave send a subset of what didOpen sends.
pub fn parse_text_document(value json2.Any) ?TextDocumentItem {
	obj := as_object(value) or { return none }
	uri := obj['uri'] or { return none }
	mut item := TextDocumentItem{
		uri: uri.str()
	}
	if language := obj['languageId'] {
		item = TextDocumentItem{
			...item
			language_id: language.str()
		}
	}
	if version := obj['version'] {
		item = TextDocumentItem{
			...item
			version: version.int()
		}
	}
	if text := obj['text'] {
		item = TextDocumentItem{
			...item
			text: text.str()
		}
	}
	return item
}

// parse_changes reads the contentChanges array of a didChange. A change entry
// with a range key is incremental; one without it replaces the buffer.
pub fn parse_changes(value json2.Any) ?[]ContentChange {
	items := as_array(value) or { return none }
	mut changes := []ContentChange{cap: items.len}
	for item in items {
		obj := as_object(item) or { return none }
		text := obj['text'] or { return none }
		mut change := ContentChange{
			text: text.str()
		}
		if range_value := obj['range'] {
			change = ContentChange{
				...change
				has_range: true
				range:     parse_range(range_value) or { return none }
			}
		}
		changes << change
	}
	return changes
}
