// semantic tokens: what the parse tree says a piece of text is.
//
// The walk is syntactic. It types the things a grammar can name on its own:
// declarations, the types they mention, literals, comments, attribute names,
// keywords and operators. What it does not type is a reference, because telling
// a call to a function from a field of the same name needs the index rather than
// the tree, and claiming one would be a guess dressed as an answer. A client
// with its own syntax highlighting keeps covering those.
module features

import engine

// token_kinds are the server's token types, by the names LSP gives them. A
// client that does not know one of these is served its fallback instead, which
// is decided at the wire, so the names here stay the spec's.
pub const token_kinds = [
	'namespace',
	'type',
	'struct',
	'enum',
	'interface',
	'typeParameter',
	'parameter',
	'variable',
	'property',
	'enumMember',
	'function',
	'method',
	'decorator',
	'keyword',
	'operator',
	'string',
	'number',
	'comment',
]!

// modifier_names are the token modifiers this server emits.
pub const modifier_declaration = 'declaration'
pub const modifier_readonly = 'readonly'
pub const modifier_names = [modifier_declaration, modifier_readonly]!

// SemanticToken is one span of text and what it is. The offsets are bytes, the
// way the parse tree reports them; the wire layer turns them into positions.
pub struct SemanticToken {
pub:
	start_byte int
	end_byte   int
	kind       string
	modifiers  []string
}

// span_kinds are the node kinds that are one token on their own. A node here is
// not walked further: a comment and a string both hold words that parse as
// something else.
const span_kinds = {
	'line_comment':               'comment'
	'block_comment':              'comment'
	'interpreted_string_literal': 'string'
	'raw_string_literal':         'string'
	'c_string_literal':           'string'
	'rune_literal':               'string'
	'int_literal':                'number'
	'float_literal':              'number'
	'type_reference_expression':  'type'
	'qualified_type':             'type'
	'field_name':                 'property'
}

// attribute_kinds are the nodes that hold an attribute's name. Only the name is
// typed: the `@[` and `]` around it are structure, and a value is whatever the
// ordinary rules make of it, so `@['/'; get]` leaves the path a string and types
// the two names beside it.
//
// `value_attribute` is a bare name and it is also the name half of a
// `key_value_attribute`, so one entry covers `@[inline]` and `@[sql: 'SELECT 1']`
// alike. An `if_attribute` is handed over whole, because `@[if debug]` is one
// attribute rather than a keyword with a name under it.
const attribute_kinds = {
	'value_attribute': 'decorator'
	'if_attribute':    'decorator'
}

// declaration_kinds are the nodes that declare a name, and what that name is.
// The name is the identifier under the node, which is emitted before the node's
// other children are walked.
const declaration_kinds = {
	'module_clause':               'namespace'
	'import_name':                 'namespace'
	'struct_declaration':          'struct'
	'struct_field_declaration':    'property'
	'enum_declaration':            'enum'
	'enum_field_definition':       'enumMember'
	'interface_declaration':       'interface'
	'interface_method_definition': 'method'
	'type_declaration':            'type'
	'parameter_declaration':       'parameter'
	'variadic_parameter':          'parameter'
	'receiver':                    'parameter'
	'generic_parameter':           'typeParameter'
	'type_parameter_declaration':  'typeParameter'
	'const_definition':            'variable'
	'global_var_declaration':      'variable'
	'var_declaration':             'variable'
}

// keywords are spelled out because the grammar hands them back as unknown
// nodes. The text is the only thing that says which one it is.
//
// The `$` ones are the compile-time constructs. `$if`, `$else` and `$for` arrive
// as unknown nodes like the rest, while the compile-time builtins arrive as
// identifiers whose name carries the `$`, which is the rule in `collect`.
const keywords = [
	'as',
	'asm',
	'assert',
	'atomic',
	'break',
	'const',
	'continue',
	'defer',
	'else',
	'enum',
	'false',
	'fn',
	'for',
	'go',
	'goto',
	'if',
	'implements',
	'import',
	'in',
	'interface',
	'is',
	'lock',
	'match',
	'module',
	'mut',
	'none',
	'or',
	'pub',
	'return',
	'rlock',
	'select',
	'shared',
	'spawn',
	'static',
	'struct',
	'thread',
	'true',
	'type',
	'union',
	'unsafe',
	'volatile',
	'$else',
	'$for',
	'$if',
]!

// operators are the ones worth colouring. Punctuation is left out on purpose:
// brackets, commas and colons are structure rather than meaning.
const operators = [
	'!',
	'!=',
	'!in',
	'!is',
	'%',
	'%=',
	'&',
	'&&',
	'&=',
	'&^',
	'&^=',
	'*',
	'*=',
	'+',
	'++',
	'+=',
	'-',
	'--',
	'-=',
	'/',
	'/=',
	':=',
	'<',
	'<-',
	'<<',
	'<<=',
	'<=',
	'=',
	'==',
	'>',
	'>=',
	'>>',
	'>>=',
	'>>>',
	'>>>=',
	'?.',
	'^',
	'^=',
	'|',
	'|=',
	'||',
	'~',
]!

// tokens_for parses a buffer and returns its tokens. A parser is built per call
// rather than kept: tree-sitter parser setup is cheap next to the parse, and a
// shared one would need locking once more than one request can be in flight.
pub fn tokens_for(text string, path string) []SemanticToken {
	mut parser := engine.new_parser_engine()
	parsed := parser.parse_source(text, path)
	tokens := tokens_in(parsed)
	parser.free()
	return tokens
}

// tokens_in walks a parsed file and returns its tokens in document order.
pub fn tokens_in(file engine.ParsedFile) []SemanticToken {
	mut out := []SemanticToken{}
	collect(file.root, file.text, mut out)
	// A declaration emits its name before the modifiers and keywords that come
	// before it in the file, so the walk's own order is not the file's. The wire
	// encoding counts from the previous token, which makes the order a
	// correctness requirement rather than a preference.
	out.sort(a.start_byte < b.start_byte)
	return out
}

fn collect(node engine.Node, text string, mut out []SemanticToken) {
	if kind := span_kinds[node.kind] {
		emit(mut out, node, kind, [])
		return
	}
	if kind := attribute_kinds[node.kind] {
		emit(mut out, node, kind, [])
		return
	}
	if node.kind == 'ERROR' {
		// A call-style attribute has no node of its own. `@[deprecated('use x')]`
		// arrives as an ERROR holding `@[` and the name, with the argument list
		// and the closing bracket behind it as statements of their own. The docs
		// spell that form and the compiler reads it, so the name is read out of
		// the rejected node rather than left as the one attribute a reader
		// cannot tell from a mistake.
		//
		// The walk carries on into the node: what else an error holds is other
		// broken code, and skipping it would take the tokens under it with it.
		if name := error_attribute_name(node, text) {
			emit(mut out, name, 'decorator', [])
		}
	}
	if node.kind == 'identifier' && text[node.start_byte..node.end_byte].starts_with('$') {
		// A name that begins with a `$` is one of the compiler's own: `$env`,
		// `$embed_file`, `$tmpl`, `$compile_error`. That is what the `$` means in
		// V and why there is no declaration to look up.
		emit(mut out, node, 'keyword', [])
		return
	}
	if node.kind == 'unknown' {
		// The grammar reports keywords and operators as unnamed nodes, so the
		// text is what identifies them. Everything else here is punctuation or
		// a line ending.
		spelling := text[node.start_byte..node.end_byte]
		if spelling in keywords {
			emit(mut out, node, 'keyword', [])
		} else if spelling in operators {
			emit(mut out, node, 'operator', [])
		}
		return
	}
	if node.kind == 'function_declaration' {
		// A receiver is what makes a function declaration a method, and the
		// grammar reports both as function_declaration.
		kind := if has_child(node, 'receiver') { 'method' } else { 'function' }
		for name in declared_names(node) {
			emit(mut out, name, kind, [modifier_declaration])
		}
	} else if node.kind == 'call_expression' {
		// `$embed_file('main.v').to_string()` is a method: the receiver is an
		// expression, and V has no function values to call through one. A call
		// reached through a plain name, `os.read_file(...)` or `x.trim_space()`,
		// is left to the client's own highlighting, because telling a module
		// function from a method on a variable needs the index rather than the
		// tree.
		if field := selector_call_field(node) {
			emit(mut out, field, 'method', [])
		}
	} else if kind := declaration_kinds[node.kind] {
		modifiers := if kind == 'variable' && node.kind == 'const_definition' {
			[modifier_declaration, modifier_readonly]
		} else {
			[modifier_declaration]
		}
		for name in declared_names(node) {
			emit(mut out, name, kind, modifiers)
		}
	}
	for child in node.children {
		collect(child, text, mut out)
	}
}

fn emit(mut out []SemanticToken, node engine.Node, kind string, modifiers []string) {
	out << SemanticToken{
		start_byte: int(node.start_byte)
		end_byte:   int(node.end_byte)
		kind:       kind
		modifiers:  modifiers
	}
}

// error_attribute_name is the name of an attribute the grammar refused to build
// a node for, or none when the error is something else.
//
// Only the shape a call-style attribute leaves is recognised: an error opening
// with `@[` and carrying the name under it. Any other error is some other
// mistake, and reading a name out of it would claim a token the text does not
// support.
fn error_attribute_name(node engine.Node, text string) ?engine.Node {
	if !text[node.start_byte..node.end_byte].starts_with('@[') {
		return none
	}
	for child in node.children {
		if child.kind == 'reference_expression' {
			return child
		}
	}
	return none
}

// selector_call_field is the name a call goes through when it goes through a
// selector and the thing it is called on is not a plain name.
fn selector_call_field(call engine.Node) ?engine.Node {
	mut selector := engine.Node{}
	for child in call.children {
		if child.kind == 'selector_expression' {
			selector = child
			break
		}
	}
	if selector.children.len < 2 {
		return none
	}
	if selector.children[0].kind == 'reference_expression' {
		return none
	}
	// The selector holds the receiver, the dot, and then the name.
	field := selector.children[selector.children.len - 1]
	if field.kind == 'reference_expression' {
		return field
	}
	return none
}

fn has_child(node engine.Node, kind string) bool {
	return node.children.any(it.kind == kind)
}

// declared_names returns the identifiers a declaration node names.
//
// Most declarations hold their name as a direct child. The two that do not are
// the variable forms, where `mut count := 0` puts the name inside the first
// expression list and only the second one holds the value.
fn declared_names(node engine.Node) []engine.Node {
	mut found := []engine.Node{}
	for child in node.children {
		if child.kind in ['identifier', 'mutable_identifier'] {
			found << child
		}
	}
	if found.len > 0 {
		return found
	}
	if node.children.len > 0 && node.children[0].kind == 'expression_list' {
		collect_identifiers(node.children[0], mut found)
	}
	return found
}

fn collect_identifiers(node engine.Node, mut found []engine.Node) {
	if node.kind == 'identifier' || node.kind == 'mutable_identifier' {
		found << node
		return
	}
	for child in node.children {
		collect_identifiers(child, mut found)
	}
}
