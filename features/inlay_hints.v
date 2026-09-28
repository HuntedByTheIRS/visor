// Inlay hints are what the engine worked out, drawn where the reader is already
// looking: which parameter an argument lands on, which field a positional value
// initializes, what a `:=` infers to, and what a defer will run and where.
//
// Every hint is anchored at a byte offset into the buffer the caller holds. The
// parse counts in bytes and the protocol counts in UTF-16 code units, so the
// conversion belongs to the caller that has the text.
//
// One label is not a statement of its own: a defer runs at the end of its block,
// so its label sits after the last statement of that block, opening with a
// semicolon so it reads as the line's continuation rather than as another
// argument to the call in front of it.
//
// A hint is only ever emitted for something the engine resolved. An argument
// whose callee could not be found gets no label rather than a guessed one, and
// that is the whole difference between this lane and a grep for `(`.
module features

import engine.psi
import engine.psi.types

// HintKind is what a hint says. The numbers are the protocol's own: 1 is a type
// hint and 2 is a parameter hint, and a client may turn either kind off on its
// own.
pub enum HintKind {
	type_     = 1
	parameter = 2
}

// Hint is one inlay hint, ready to be placed in a buffer.
pub struct Hint {
pub:
	// offset is a byte offset into the text the hint was computed over.
	offset int
	label  string
	kind   HintKind
	// padding right asks the client for a space between the label and what
	// follows it, which is what keeps `factor:` from reading as part of the
	// argument.
	padding_right bool
	// tooltip is empty when the label is everything the hint knows. It carries
	// where an answer came from when that is somewhere the reader cannot see,
	// such as the parameter list of a function in another file.
	tooltip string
}

// HintOptions is which families a client asked for. They all default to on: a
// family is turned off by asking for it off, and a server that answered silence
// until it was told twice would look broken.
pub struct HintOptions {
pub mut:
	// parameters labels each call argument with the name of the parameter it
	// lands on.
	parameters bool = true
	// struct_fields labels each positional value of a struct literal with the
	// field it initializes.
	struct_fields bool = true
	// types labels a `:=` with the type the engine inferred for it.
	types bool = true
	// defers shows the code a defer will run at the point in the block where it
	// runs.
	defers bool = true
}

// hints_for walks the parse of one buffer and returns every hint the options
// ask for, in the order they appear.
pub fn hints_for(file &psi.PsiFile, options HintOptions) []Hint {
	mut hints := []Hint{}
	collect_hints(file.root, file.source_text, options, mut hints)
	mut sorted := hints.clone()
	sorted.sort_with_compare(fn (a &Hint, b &Hint) int {
		if a.offset == b.offset {
			return 0
		}
		return if a.offset < b.offset { -1 } else { 1 }
	})
	return sorted
}

// collect_hints adds the hints for one element and then for everything under it.
//
// The families are not exclusive: a `:=` whose initializer is a struct literal
// holding a call holds all of them at once, and each is added by the element it
// belongs to rather than by the outermost one.
fn collect_hints(element psi.PsiElement, text string, options HintOptions, mut hints []Hint) {
	kind := element.node().type_name
	if options.parameters && element is psi.CallExpression {
		parameter_hints(element, text, mut hints)
	}
	if options.struct_fields && element is psi.TypeInitializer {
		field_hints(element, text, mut hints)
	}
	if options.types && element is psi.VarDefinition {
		type_hint(element, text, mut hints)
	}
	if options.defers && kind == .block {
		defer_hints(element, text, mut hints)
	}
	for child in element.children() {
		collect_hints(child, text, options, mut hints)
	}
}

// parameter_hints labels the arguments of a call with the parameters they land
// on.
//
// An argument that already reads as the name it would be labelled with is left
// alone, so `scale(factor, 2)` gains nothing in front of `factor`. A call the
// engine cannot resolve, which is every builtin and every function from a module
// no root covers, gains nothing at all.
fn parameter_hints(call psi.CallExpression, text string, mut hints []Hint) {
	resolved := call.resolve() or { return }
	if resolved is psi.FunctionOrMethodDeclaration {
		signature := resolved.signature() or { return }
		parameters := signature.parameters()
		callee := resolved.name()
		for i, argument in call.arguments() {
			if i >= parameters.len {
				break
			}
			parameter := parameters[i]
			if parameter is psi.ParameterDeclaration {
				add_parameter_hint(argument, parameter, callee, text, mut hints)
			}
		}
	}
}

// add_parameter_hint labels one argument, unless the argument already reads as
// the parameter's own name.
fn add_parameter_hint(argument psi.PsiElement, parameter psi.ParameterDeclaration, callee string, text string, mut hints []Hint) {
	name := parameter.name()
	if name == '' || element_text(argument, text) == name {
		return
	}
	hints << Hint{
		offset:        element_start(argument)
		label:         '${name}:'
		kind:          .parameter
		padding_right: true
		tooltip:       parameter_tooltip(callee, parameter)
	}
}

// field_hints labels the positional values of a struct literal with the fields
// they initialize.
//
// Only the positional spelling needs this: the keyed one writes the names in the
// text, and the parser hands it over as a map literal anyway. Array, map and
// channel literals reach here too and resolve to no fields, which is how they
// are left alone.
fn field_hints(initializer psi.TypeInitializer, text string, mut hints []Hint) {
	elements := initializer.element_list()
	if elements.len == 0 {
		return
	}
	fields := psi.fields_list(initializer.get_type())
	if fields.len == 0 {
		return
	}
	for i, item in elements {
		if i >= fields.len {
			break
		}
		if item.node().type_name == .keyed_element {
			continue
		}
		field := fields[i]
		if field is psi.FieldDeclaration {
			add_field_hint(item, field, initializer, text, mut hints)
		}
	}
}

// add_field_hint labels one positional value, unless the value already reads as
// the field's own name.
fn add_field_hint(item psi.PsiElement, field psi.FieldDeclaration, initializer psi.TypeInitializer, text string, mut hints []Hint) {
	name := field.name()
	if name == '' || element_text(item, text) == name {
		return
	}
	hints << Hint{
		offset:        element_start(item)
		label:         '${name}:'
		kind:          .parameter
		padding_right: true
		tooltip:       'field ${name}: ${field.get_type().readable_name()} of ${initializer.get_type().readable_name()}'
	}
}

// type_hint labels a `:=` with what the engine inferred for it.
//
// The initializer decides whether the hint is worth drawing. A value that spells
// its own type, `p := Point{ 2, 3 }`, is not news to the reader, and neither is
// an unknown type, which is what every unresolved call infers to.
fn type_hint(definition psi.VarDefinition, text string, mut hints []Hint) {
	typ := definition.get_type()
	name := typ.readable_name()
	if name == '' || name == 'unknown' || name == 'void' {
		return
	}
	if spells_its_type(definition, text, name) {
		return
	}
	identifier := definition.identifier() or { return }
	hints << Hint{
		offset:  element_end(identifier)
		label:   ': ${name}'
		kind:    .type_
		tooltip: type_tooltip(typ)
	}
}

// spells_its_type reports whether the initializer already writes the type in its
// own text, which is the case for every struct literal and every call typed as
// the value it returns.
fn spells_its_type(definition psi.VarDefinition, text string, name string) bool {
	declaration := definition.declaration() or { return false }
	initializer := declaration.initializer_of(definition) or { return false }
	initializer_text := element_text(initializer, text)
	for prefix in [name, name + '{', name + '.', name + '(', name + '['] {
		if initializer_text.starts_with(prefix) {
			return true
		}
	}
	return false
}

// defer_hints shows what a defer will run, at the point in its block where it
// runs.
//
// The block's closing brace is what the label is placed above, and several
// defers in one block become one label in the order they run, which is the
// reverse of the order they are written in; splitting them into one hint each
// would stack several labels on the same position and leave the client to decide
// what order they read in.
//
// The keyword is read out of the block's text rather than out of a node kind.
// `defer f()` does not parse: depending on what follows it the grammar leaves
// `defer` as an error token or swallows it whole, and in both shapes the call
// under it arrives as an ordinary statement of the block. What a reader sees is
// the keyword either way, so that is what is read, at this block's own depth, so
// a defer inside a nested block belongs to that block and is not counted twice.
fn defer_hints(block psi.PsiElement, text string, mut hints []Hint) {
	codes := deferred_bodies(element_text(block, text))
	if codes.len == 0 {
		return
	}
	mut shortened := []string{cap: codes.len}
	for i := codes.len - 1; i >= 0; i-- {
		shortened << shorten(codes[i])
	}
	hints << Hint{
		offset:  defer_anchor(text, element_end(block))
		label:   '; defer: ${shortened.join('; ')}'
		kind:    .type_
		tooltip: codes.join('\n')
	}
}

// deferred_bodies returns the code each defer in a block runs, in the order the
// source writes them.
//
// Depth is counted in braces so that only the statements written in this block
// are read. The braces inside a string or a comment are counted too, which is
// the one thing this walk gets wrong; a hint is not worth a lexer.
fn deferred_bodies(body string) []string {
	mut codes := []string{}
	lines := body.split_into_lines()
	mut depth := 0
	mut index := 0
	for index < lines.len {
		trimmed := lines[index].trim_space()
		if depth == 1 && is_defer_line(trimmed) {
			rest := trimmed[5..].trim_space()
			if rest.starts_with('{') {
				inner := deferred_block_lines(lines, index, rest)
				if inner != '' {
					codes << inner
				}
				index += inner_line_count(lines, index, rest)
			} else if rest != '' {
				codes << rest
			}
			index++
			continue
		}
		depth += brace_delta(trimmed)
		index++
	}
	return codes
}

// deferred_block_lines returns the code inside a `defer { ... }` that starts on
// the line at `index`, with its braces taken off.
fn deferred_block_lines(lines []string, index int, first_line string) string {
	rest := first_line[1..]
	// A block written on one line carries its code between its own braces, and
	// there is nothing under it to walk.
	if brace_delta(first_line) <= 0 {
		inner := rest.trim_space()
		if inner.ends_with('}') {
			return inner[..inner.len - 1].trim_space()
		}
	}
	mut body := []string{}
	// The line the keyword is on has already opened the block, so the count
	// starts at one and runs until the brace that closes it.
	mut depth := 1
	mut line_index := index
	mut inner_rest := rest
	for {
		depth += brace_delta(inner_rest)
		if depth <= 0 {
			break
		}
		if inner_rest.trim_space() != '' {
			body << inner_rest.trim_space()
		}
		line_index++
		if line_index >= lines.len {
			break
		}
		inner_rest = lines[line_index]
	}
	return body.join('\n').trim_space()
}

// inner_line_count is how many lines a `defer { ... }` covers, so the walk can
// step over the body it has already read.
fn inner_line_count(lines []string, index int, first_line string) int {
	mut depth := 1
	mut line_index := index
	mut rest := first_line[1..]
	for {
		depth += brace_delta(rest)
		if depth <= 0 {
			return line_index - index
		}
		line_index++
		if line_index >= lines.len {
			return line_index - index
		}
		rest = lines[line_index]
	}
}

// is_defer_line reports whether a trimmed line is a defer: the keyword and then
// a space or the braces under it.
fn is_defer_line(trimmed string) bool {
	if !trimmed.starts_with('defer') {
		return false
	}
	if trimmed.len == 5 {
		return false
	}
	next := trimmed[5]
	return next == ` ` || next == `	` || next == `{`
}

// brace_delta is how many blocks a line opens or closes.
fn brace_delta(line string) int {
	mut delta := 0
	for c in line {
		if c == `{` {
			delta++
		}
		if c == `}` {
			delta--
		}
	}
	return delta
}

// defer_anchor is where a deferred label is drawn: the end of the last line of
// the block's body, which is the line above the closing brace.
//
// The brace itself is where the deferred code runs, and a label sitting on it
// lands after the brace at the far left of nothing. The reader wants it next to
// the statement it follows, so the anchor walks back over the whitespace in
// front of the brace and stops after the last thing written.
//
// A block whose body shares the brace's line has nothing above to attach to, and
// there the brace is the anchor.
fn defer_anchor(text string, block_end int) int {
	mut brace := block_end - 1
	if brace > text.len - 1 {
		brace = text.len - 1
	}
	if brace < 0 {
		return 0
	}
	mut index := brace
	for index > 0 && is_block_whitespace(text[index - 1]) {
		index--
	}
	// Nothing above the brace to attach to, or the body shares the brace's line.
	if index == 0 || !text[index..brace + 1].contains('\n') {
		return brace
	}
	return index
}

// is_block_whitespace reports whether a byte is whitespace the block's own
// indentation is made of, which is what a label skips back over.
fn is_block_whitespace(c u8) bool {
	return c == ` ` || c == `	` || c == `\n` || c == `\r`
}

// shorten keeps a deferred body to something a client can draw on one line. Two
// lines are the most a hint carries; the rest goes in the tooltip.
fn shorten(code string) string {
	lines := code.split_into_lines().filter(it.trim_space() != '')
	if lines.len == 0 {
		return code
	}
	if lines.len <= 2 {
		mut joined := []string{cap: lines.len}
		for line in lines {
			joined << line.trim_space()
		}
		return joined.join(' ')
	}
	return lines.first().trim_space() + ' ...'
}

// parameter_tooltip says which parameter a label names and where it was declared.
fn parameter_tooltip(callee string, parameter psi.ParameterDeclaration) string {
	typ := parameter.get_type().readable_name()
	mut text := 'parameter ${parameter.name()}: ${typ}'
	if callee != '' {
		text += ' of ${callee}()'
	}
	if location := element_location(parameter) {
		text += ', declared at ${location}'
	}
	return text
}

// type_tooltip says where the type came from, which is the part of the answer a
// grey word on its own does not carry.
fn type_tooltip(typ types.Type) string {
	if typ is types.StructType {
		return 'struct ${typ.readable_name()}, declared in module ${typ.module_name()}'
	}
	if typ is types.AliasType {
		return 'alias for ${typ.readable_name()}'
	}
	return 'inferred type ${typ.readable_name()}'
}

// element_location names a file and a line for an element, which is as much of a
// location as fits in a tooltip.
fn element_location(element psi.PsiElement) ?string {
	file := element.containing_file() or { return none }
	range := element.text_range()
	name := file.path.split('/').last()
	return '${name}:${range.line + 1}'
}

// element_text returns the buffer text an element covers.
fn element_text(element psi.PsiElement, text string) string {
	return span_text(text, element_start(element), element_end(element)).trim_space()
}

// element_start is the byte the element starts at.
fn element_start(element psi.PsiElement) int {
	return int(element.node().start_byte())
}

// element_end is the byte after the last one the element covers.
fn element_end(element psi.PsiElement) int {
	return int(element.node().end_byte())
}

// span_text returns text[start..stop], clamped to the text, so a tree that
// outlived the buffer it was parsed from yields nothing rather than a panic.
fn span_text(text string, start int, stop int) string {
	if start < 0 || stop > text.len || start >= stop {
		return ''
	}
	return text[start..stop]
}
