module vtool

// The spelling `v fmt` produces from this, down to the tabs and the single
// quotes. Asserted against a literal rather than against a second run of the
// compiler, so a change in formatting shows up as a failure here.
const want_formatted = "fn main() {\n\tprintln('x')\n}\n"

// A buffer no formatter can parse.
const unparsable = 'fn main() {\n\tx := \n}\n'

// V runs each _test.v file in its own binary, so a helper written in one of
// them is not visible from another. Every test file that needs a compiler
// resolves its own.
fn compiler() Compiler {
	return find() or { panic(err.msg()) }
}

fn test_formatting_matches_the_compilers_own_output() {
	got := compiler().format('fn   main(){\nprintln("x")\n}\n') or { panic(err.msg()) }
	assert got == want_formatted
}

fn test_an_already_formatted_buffer_comes_back_unchanged() {
	got := compiler().format(want_formatted) or { panic(err.msg()) }
	assert got == want_formatted
}

fn test_quotes_and_indentation_are_the_compilers_choices() {
	// A double-quoted string, spaces for indentation and no space before the
	// brace, all of which the formatter rewrites.
	input := 'fn main() {\n    println("x")\n}\n'
	got := compiler().format(input) or { panic(err.msg()) }
	assert got == want_formatted
	assert !got.contains('"x"')
}

fn test_an_empty_buffer_is_accepted() {
	got := compiler().format('') or { panic(err.msg()) }
	assert got == ''
}

fn test_a_buffer_that_cannot_be_parsed_is_an_error() {
	compiler().format(unparsable) or {
		assert err.msg().contains('fmt')
		return
	}
	assert false
}

fn test_a_missing_compiler_is_an_error() {
	broken_compiler := Compiler{
		abs_path: '/nonexistent/definitely-not-a-compiler'
		origin:   'test'
	}
	broken_compiler.format(want_formatted) or {
		assert err.msg().contains('not a file')
		return
	}
	assert false
}
