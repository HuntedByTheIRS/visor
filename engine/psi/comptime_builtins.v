module psi

import engine.psi.types

// comptime_call_type is what a compile-time builtin produces, or none when the
// call is not one the compiler answers itself.
//
// These builtins belong to the compiler rather than to any file. There is no
// declaration for the index to find and no stub to look in, so what each of them
// produces is written down here: `$env('HOME')` is a string on whatever machine
// runs the build, and `$embed_file` builds a type of its own.
//
// Only the builtins that produce a value are named. `$compile_error` stops the
// build instead of producing one, so a `:=` reading it is dead code and gets no
// label either way.
pub fn comptime_call_type(element CallExpression) ?types.Type {
	spelling := comptime_callee_spelling(element)
	if !spelling.starts_with('$') {
		return none
	}
	if spelling.contains('(') {
		// A method called on what a builtin produced, as in
		// `$embed_file('main.v').to_string()`. The embedded file is a compiler
		// type with no stub behind it, so the methods that read it back as text
		// are written down here as well.
		name := spelling.all_after_last('.')
		receiver := spelling.all_before_last('.')
		if receiver.starts_with('$embed_file') && name in ['to_string', 'str'] {
			return types.string_type
		}
		return none
	}
	if spelling in ['$env', '$tmpl'] {
		return types.string_type
	}
	if spelling == '$embed_file' {
		return types.new_struct_type('EmbedFileStruct', 'v.embed_file')
	}
	return none
}

// comptime_callee_spelling is the source text a call goes through. For a call
// through a selector it is the whole selector, which is how the receiver and the
// method name are read back out of it.
fn comptime_callee_spelling(element CallExpression) string {
	expr := element.expression() or { return '' }
	file := element.containing_file() or { return '' }
	node := expr.node()
	return file.source_text[node.start_byte()..node.end_byte()]
}
