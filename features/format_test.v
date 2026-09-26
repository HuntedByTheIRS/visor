module features

import vtool

// The spelling `v fmt` produces from the unformatted buffer below. Written out
// so that a change in the formatter shows up as a failure here rather than as a
// second run of the compiler agreeing with the first.
const want_formatted = "fn main() {\n\tprintln('x')\n}\n"

const unformatted = 'fn   main(){\nprintln("x")\n}\n'

// A buffer no formatter can parse.
const unparsable = 'fn main() {\n\tx := \n}\n'

// V runs each _test.v file in its own binary, so another file's helper is not
// visible here. Every test file that needs a compiler resolves its own.
fn compiler() vtool.Compiler {
	return vtool.find() or { panic(err.msg()) }
}

fn test_a_buffer_that_needs_formatting_comes_back_as_one_edit() {
	result := format_buffer(compiler(), unformatted) or { panic(err.msg()) }
	assert !result.unchanged
	assert result.edits.len == 1
	assert result.edits[0].new_text == want_formatted
}

fn test_the_edit_covers_the_whole_buffer() {
	result := format_buffer(compiler(), unformatted) or { panic(err.msg()) }
	assert result.edits[0].start_byte == 0
	assert result.edits[0].end_byte == unformatted.len
}

fn test_a_formatted_buffer_comes_back_with_no_edits() {
	result := format_buffer(compiler(), want_formatted) or { panic(err.msg()) }
	assert result.unchanged
	assert result.edits.len == 0
}

fn test_an_empty_buffer_is_left_alone() {
	result := format_buffer(compiler(), '') or { panic(err.msg()) }
	assert result.unchanged
	assert result.edits.len == 0
}

fn test_a_buffer_that_cannot_be_parsed_is_an_error() {
	format_buffer(compiler(), unparsable) or {
		assert err.msg().contains('fmt')
		return
	}
	assert false
}

fn test_a_missing_compiler_is_an_error() {
	broken := vtool.Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	format_buffer(broken, want_formatted) or {
		assert err.msg().contains('not a file')
		return
	}
	assert false
}
