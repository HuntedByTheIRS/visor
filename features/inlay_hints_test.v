module features

import engine
import os

// These tests index a scratch module and then ask for hints in a buffer holding
// its own text, so every label is answered by the engine rather than by the
// spelling of the source.

const hints_dir_name = 'visor-features-inlay-hints-test'

const hint_util = 'module main

struct Point {
	x int
	y int
}

fn scale(p Point, factor int) Point {
	return Point{ p.x * factor, p.y * factor }
}

fn label(n int) string {
	return n.str()
}
'

// The buffer writes a positional struct literal, two calls and a defer, and it
// calls a builtin the engine has no declaration for.
const hint_buffer = 'module main

fn main() {
	base := Point{ 2, 3 }
	scaled := scale(base, 4)
	text := label(4)
	defer println(text)
	println(scaled)
	println(base)
}
'

// hints_in indexes a fresh copy of the scratch project, hands the buffer in, and
// returns the hints the options ask for.
fn hints_in(buffer string, options HintOptions) []Hint {
	dir := os.join_path(os.temp_dir(), hints_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), hint_util) or { panic(err.msg()) }

	mut session := engine.new_session()
	session.index_root(dir, os.join_path(os.temp_dir(), 'visor-features-inlay-hints-cache'))
	path := os.join_path(dir, 'main.v')
	session.put_buffer(path, buffer) or { panic(err.msg()) }
	file := session.file(path) or { panic('the buffer is not open: ${path}') }
	return hints_for(file, options)
}

// hint_labels is what a reader would see, in the order the hints appear.
fn hint_labels(hints []Hint) []string {
	mut labels := []string{cap: hints.len}
	for hint in hints {
		labels << hint.label
	}
	return labels
}

// find_hint returns the first hint carrying a label.
fn find_hint(hints []Hint, label string) ?Hint {
	for hint in hints {
		if hint.label == label {
			return hint
		}
	}
	return none
}

fn test_hints_name_the_arguments_and_the_fields() {
	hints := hints_in(hint_buffer, HintOptions{})
	println('the buffer drew: ${hint_labels(hints)}')

	// The struct literal first, then the call that takes it: the fields it
	// initializes, then the parameters its arguments land on. A type hint sits
	// at the end of its name, so it comes before the arguments of the call that
	// name is being assigned from.
	assert hint_labels(hints) == ['x:', 'y:', ': Point', 'p:', 'factor:', ': string', 'n:',
		'; defer: println(text)']
	for hint in hints {
		if hint.label in ['x:', 'y:', 'p:', 'factor:', 'n:'] {
			assert hint.kind == .parameter
		}
	}
}

fn test_a_hint_lands_on_the_text_it_describes() {
	hints := hints_in(hint_buffer, HintOptions{})

	// `x:` is drawn in front of the value that initializes x, and `p:` in front
	// of the argument that lands on p. An offset one off puts the label inside
	// the expression next to it.
	x_hint := find_hint(hints, 'x:') or { panic('no field hint') }
	assert hint_buffer[x_hint.offset..x_hint.offset + 1] == '2'
	p_hint := find_hint(hints, 'p:') or { panic('no parameter hint') }
	assert hint_buffer[p_hint.offset..p_hint.offset + 4] == 'base'

	// The type hint sits at the end of the name it describes.
	point_hint := find_hint(hints, ': Point') or { panic('no type hint') }
	assert hint_buffer[..point_hint.offset].ends_with('scaled')
	assert point_hint.kind == .type_
}

fn test_a_defer_hint_sits_where_the_code_runs() {
	hints := hints_in(hint_buffer, HintOptions{})
	defer_hint := find_hint(hints, '; defer: println(text)') or { panic('no defer hint') }

	// The anchor is the end of the last line of the body, which is the line above
	// the closing brace. A label on the brace lands after the brace, in front of
	// nothing.
	assert hint_buffer[defer_hint.offset - 1] == `)`
	assert hint_buffer[defer_hint.offset] == `\n`
	assert defer_hint.tooltip == 'println(text)'
}

const block_defer_buffer = 'module main

fn main() {
	defer {
		text := label(4)
		println(text)
	}
	println(1)
}
'

const nested_defer_buffer = 'module main

fn main() {
	defer println(1)
	if true {
		defer println(2)
	}
}
'

// A defer whose body is a block is the spelling the parser understands, and its
// code is what sits under the braces.
fn test_a_defer_block_shows_the_code_under_its_braces() {
	hints := hints_in(block_defer_buffer, HintOptions{})
	defer_hint := find_hint(hints, '; defer: text := label(4) println(text)') or {
		mut labels := []string{}
		for hint in hints {
			labels << hint.label
		}
		panic('no block defer hint, got ${labels}')
	}
	assert defer_hint.tooltip == 'text := label(4)\nprintln(text)'
	// The label follows the last statement of the block, so it opens with a
	// semicolon: without it the label reads as one more argument to whatever the
	// line ends with.
	assert defer_hint.label.starts_with('; defer: ')
}

// A defer written in a nested block runs at the end of that block, and it is
// that block's label to carry. Reading the lines of the outer block as well is
// what would put the same code in two hints.
fn test_a_defer_in_a_nested_block_belongs_to_that_block() {
	hints := hints_in(nested_defer_buffer, HintOptions{})
	mut labels := []string{}
	for hint in hints {
		labels << hint.label
	}
	assert '; defer: println(1)' in labels
	assert '; defer: println(2)' in labels
	assert labels.filter(it == '; defer: println(1)').len == 1
	assert labels.filter(it == '; defer: println(2)').len == 1
}

// The compile-time builtins are the compiler's own: nothing in the index declares
// `$env` or `$embed_file`, so what they produce is written down in the engine next
// to its other builtins.
const compile_time_buffer = "module main

fn main() {
	x := \$embed_file('main.v').to_string()
	println(x)
	y := \$env('HOME')
	println(y)
	z := \$res('thing')
	println(z)
}
"

fn test_a_compile_time_builtin_is_labelled_with_what_it_produces() {
	hints := hints_in(compile_time_buffer, HintOptions{})
	assert hint_labels(hints) == [': string', ': string']
}

// A builtin this server has not written down gets no label, the same way a call it
// cannot resolve does: a guess is worse than a gap.
fn test_a_compile_time_builtin_this_server_does_not_know_gets_nothing() {
	hints := hints_in(compile_time_buffer, HintOptions{})
	assert find_hint(hints, ': []u8') == none
	assert find_hint(hints, ': void') == none
}

fn test_a_value_that_spells_its_own_type_is_not_labelled() {
	hints := hints_in(hint_buffer, HintOptions{})
	// `base := Point{ 2, 3 }` says Point twice already. `scaled` and `text` do
	// not, and both are labelled.
	assert hint_labels(hints).filter(it == ': Point').len == 1
	assert find_hint(hints, ': string') != none
}

fn test_a_call_the_engine_cannot_resolve_is_left_alone() {
	hints := hints_in(hint_buffer, HintOptions{})
	// println is a builtin with no declaration in any root, so the arguments
	// of the two println calls get no label from a guess.
	mut labels := []string{}
	for hint in hints {
		if hint.label == 'x:' || hint.label == 'a:' || hint.label == 's:' {
			labels << hint.label
		}
	}
	assert labels.len == 1
}

fn test_each_family_is_turned_off_by_asking() {
	without_types := hints_in(hint_buffer, HintOptions{
		types: false
	})
	assert find_hint(without_types, ': Point') == none
	assert find_hint(without_types, 'x:') != none

	without_defers := hints_in(hint_buffer, HintOptions{
		defers: false
	})
	assert find_hint(without_defers, '; defer: println(text)') == none

	without_parameters := hints_in(hint_buffer, HintOptions{
		parameters: false
	})
	assert find_hint(without_parameters, 'p:') == none
	assert find_hint(without_parameters, ': Point') != none

	without_fields := hints_in(hint_buffer, HintOptions{
		struct_fields: false
	})
	assert find_hint(without_fields, 'x:') == none
	assert find_hint(without_fields, 'p:') != none

	without_attributes := hints_in(attribute_buffer, HintOptions{
		attributes: false
	})
	assert hint_labels(without_attributes) == []
}

// A function and a module carry their attributes on the lines above them, which
// is where a reader stops seeing them once the declaration grows. The comment
// after the module name is what tells an anchor that follows the declaration from
// one that follows the line the declaration happens to be written on.
const attribute_buffer = '@[translated]
module main // the fixture

@[inline]
@[unsafe]
fn add(a int, b int) int {
	return a + b
}
'

// Every shape an attribute name comes in: `name: value`, a condition, a
// call-style attribute with named arguments, and a route whose path and methods
// both count.
const attribute_forms_buffer = "module main

@[callconv: 'stdcall']
@[if debug]
@[deprecated(msg: 'use add')]
@['/index'; get]
fn window_proc() {}
"

fn test_a_declaration_names_the_attributes_it_carries() {
	hints := hints_in(attribute_buffer, HintOptions{})
	assert hint_labels(hints) == ['    | TRANSLATED', '    | INLINE::UNSAFE']
}

fn test_an_attribute_label_sits_at_the_end_of_the_declaration() {
	hints := hints_in(attribute_buffer, HintOptions{})

	// After the name of the module, not at the end of the line the name is on,
	// and after the brace the body opens with.
	module_hint := find_hint(hints, '    | TRANSLATED') or { panic('no module hint') }
	assert attribute_buffer[..module_hint.offset].ends_with('module main')
	assert attribute_buffer[module_hint.offset..].starts_with(' //')

	function_hint := find_hint(hints, '    | INLINE::UNSAFE') or { panic('no function hint') }
	assert attribute_buffer[..function_hint.offset].ends_with('{')
	assert function_hint.kind == .type_
	// the label names the attributes and the tooltip carries what they say
	assert function_hint.tooltip == '@[inline]\n@[unsafe]'
}

fn test_the_label_names_every_shape_an_attribute_comes_in() {
	hints := hints_in(attribute_forms_buffer, HintOptions{})
	// A route's path loses the quotes the source writes it with, a condition is
	// shown whole, and a call-style attribute is named by the word before its
	// arguments rather than by the text up to the first colon.
	assert hint_labels(hints) == ['    | CALLCONV::IF DEBUG::DEPRECATED::/INDEX::GET']
}

fn test_a_declaration_without_attributes_gets_no_label() {
	hints := hints_in('module main\n\nfn plain() {}\n', HintOptions{})
	assert hints.len == 0
}
