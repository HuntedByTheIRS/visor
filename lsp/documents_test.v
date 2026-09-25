module lsp

fn open_store() DocumentStore {
	mut ds := DocumentStore{}
	ds.open_document(TextDocumentItem{
		uri:         'file:///tmp/a.v'
		language_id: 'v'
		version:     1
		text:        'fn main() {\n\tprintln(1)\n}\n'
	})
	return ds
}

fn edit(has_range bool, sl int, sc int, el int, ec int, text string) ContentChange {
	return ContentChange{
		has_range: has_range
		range:     Range{
			start: Position{
				line:      sl
				character: sc
			}
			end:   Position{
				line:      el
				character: ec
			}
		}
		text:      text
	}
}

fn test_open_and_read_a_document() {
	ds := open_store()
	assert ds.count() == 1
	assert ds.is_open('file:///tmp/a.v')
	doc := ds.get('file:///tmp/a.v') or { panic('document is missing') }
	assert doc.version == 1
	assert doc.language_id == 'v'
	assert doc.text.starts_with('fn main()')
}

fn test_close_removes_the_buffer() {
	mut ds := open_store()
	assert ds.close_document('file:///tmp/a.v')
	assert !ds.is_open('file:///tmp/a.v')
	assert !ds.close_document('file:///tmp/a.v')
	assert ds.count() == 0
}

fn test_ranged_edit_replaces_a_word() {
	mut ds := open_store()
	doc := ds.apply_changes('file:///tmp/a.v', 2, [
		edit(true, 1, 9, 1, 10, '42'),
	]) or { panic('edit failed: ${err}') }
	assert doc.text == 'fn main() {\n\tprintln(42)\n}\n'
	assert doc.version == 2
}

fn test_an_edit_can_insert_a_line() {
	mut ds := open_store()
	doc := ds.apply_changes('file:///tmp/a.v', 2, [
		edit(true, 1, 0, 1, 0, '\tprintln(0)\n'),
	]) or { panic('edit failed: ${err}') }
	assert doc.text == 'fn main() {\n\tprintln(0)\n\tprintln(1)\n}\n'
}

fn test_changes_apply_one_after_another() {
	mut ds := open_store()
	doc := ds.apply_changes('file:///tmp/a.v', 2, [
		edit(true, 1, 9, 1, 10, '12'),
		edit(true, 1, 10, 1, 11, '7'),
	]) or { panic('edit failed: ${err}') }
	// the second change is positioned against the text the first one produced.
	assert doc.text == 'fn main() {\n	println(17)\n}\n'
	assert ds.changes_applied == 2
}

fn test_a_change_without_a_range_replaces_the_whole_buffer() {
	mut ds := open_store()
	doc := ds.apply_changes('file:///tmp/a.v', 2, [
		edit(false, 0, 0, 0, 0, 'module main\n'),
	]) or { panic('edit failed: ${err}') }
	assert doc.text == 'module main\n'
}

fn test_positions_count_utf16_units_not_bytes() {
	mut ds := DocumentStore{}
	// the emoji is four bytes and two UTF-16 code units.
	ds.open_document(TextDocumentItem{
		uri:     'file:///tmp/b.v'
		version: 1
		text:    "fn main() {\n\tprintln('\U0001F600')\n}\n"
	})
	doc := ds.apply_changes('file:///tmp/b.v', 2, [
		edit(true, 1, 10, 1, 12, 'x'),
	]) or { panic('edit failed: ${err}') }
	// a byte offset would have landed inside the emoji and left the closing
	// quote where the emoji used to start.
	assert doc.text == "fn main() {\n\tprintln('x')\n}\n"
}

fn test_a_position_past_the_end_of_the_line_clamps() {
	text := 'abc\ndef\n'
	assert offset_for(text, Position{
		line:      0
		character: 99
	}) == 3
	assert offset_for(text, Position{
		line:      1
		character: 2
	}) == 6
	assert offset_for(text, Position{
		line:      9
		character: 0
	}) == text.len
}

fn test_a_position_that_splits_a_surrogate_pair_lands_before_it() {
	text := 'a\U0001F600b'
	// the emoji starts at unit 1 and takes two units. Unit 2 is inside it.
	assert offset_for(text, Position{
		line:      0
		character: 2
	}) == 1
	assert offset_for(text, Position{
		line:      0
		character: 3
	}) == 5
}

fn test_editing_a_document_that_is_not_open_is_an_error() {
	mut ds := open_store()
	if _ := ds.apply_changes('file:///tmp/other.v', 2, [edit(false, 0, 0, 0, 0, 'x')]) {
		assert false
	} else {
		assert true
	}
}

fn test_a_version_that_does_not_advance_is_counted() {
	mut ds := open_store()
	ds.apply_changes('file:///tmp/a.v', 1, [edit(false, 0, 0, 0, 0, 'x')]) or {}
	assert ds.stale_updates == 1
}

fn test_parse_changes_reads_ranged_and_whole_document_edits() {
	params := '{"textDocumentChanges":[{"range":{"start":{"line":0,"character":0},' +
		'"end":{"line":1,"character":0}},"text":"a"},{"text":"b"}]}'
	root := parse_message('{"jsonrpc":"2.0","method":"x","params":${params}}')
	obj := as_object(root.params) or { panic('params is not an object') }
	changes := parse_changes(obj['textDocumentChanges'] or { panic('missing key') }) or {
		panic('changes did not parse')
	}
	assert changes.len == 2
	assert changes[0].has_range
	assert changes[0].range.end.line == 1
	assert changes[0].text == 'a'
	assert !changes[1].has_range
	assert changes[1].text == 'b'
}

fn test_parse_text_document_reads_the_parts_that_are_there() {
	params := '{"textDocument":{"uri":"file:///x.v","languageId":"v","version":3,"text":"hi"}}'
	root := parse_message('{"jsonrpc":"2.0","method":"x","params":${params}}')
	obj := as_object(root.params) or { panic('params is not an object') }
	item := parse_text_document(obj['textDocument'] or { panic('missing key') }) or {
		panic('did not parse')
	}
	assert item.uri == 'file:///x.v'
	assert item.language_id == 'v'
	assert item.version == 3
	assert item.text == 'hi'
}

fn test_parse_text_document_accepts_the_thin_form() {
	// didChange and didSave send the uri and version with no language and no
	// text, so those fields have to be optional.
	params := '{"textDocument":{"uri":"file:///x.v","version":4}}'
	root := parse_message('{"jsonrpc":"2.0","method":"x","params":${params}}')
	obj := as_object(root.params) or { panic('params is not an object') }
	item := parse_text_document(obj['textDocument'] or { panic('missing key') }) or {
		panic('did not parse')
	}
	assert item.uri == 'file:///x.v'
	assert item.language_id == ''
	assert item.version == 4
	assert item.text == ''
}
