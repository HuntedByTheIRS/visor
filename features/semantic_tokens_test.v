module features

const sample = '@[heap]
pub struct Server {
pub mut:
	name    string
	workers int = 4
}

// Severity ranks a finding.
pub enum Severity {
	error
	warning
}

pub interface Store {
	get(key string) ?string
}

const default_name = \'visor\'

type Handler = fn (string) string

pub fn greet(name string, loud bool) string {
	mut count := 0
	mut ratio := 1.5
	for _ in 0 .. 3 {
		count += 1
	}
	if loud {
		return \'HELLO name\'
	}
	return "hello 0x2a 3.5"
}

fn (s &Server) start() {
	println(greeter.greeting())
}'

// The compile-time constructs belong to the compiler rather than to a module, so
// they carry their own `$` and there is nothing in the index for them to point at.
const compile_time_sample = "module main

fn main() {
	x := \$embed_file('main.v').to_string()
	println(\$env('HOME'))
	\$if linux {
		println('linux')
	}
	y := x.trim_space()
	println(os.args)
}
"

fn test_a_compile_time_name_is_a_keyword() {
	tokens := tokens_of(compile_time_sample)
	assert kind_of(compile_time_sample, tokens, '$embed_file') == 'keyword'
	assert kind_of(compile_time_sample, tokens, '$env') == 'keyword'
	assert kind_of(compile_time_sample, tokens, '$if') == 'keyword'
}

// The receiver is an expression, and V has no function values to call through
// one, so the name the call goes through is a method.
fn test_a_call_on_an_expression_names_its_method() {
	tokens := tokens_of(compile_time_sample)
	assert kind_of(compile_time_sample, tokens, 'to_string') == 'method'
}

// A call reached through a plain name is left to the client's own highlighting:
// telling the `os` module from a variable named `os` needs the index, which this
// walk does not have.
fn test_a_call_through_a_name_is_not_typed() {
	tokens := tokens_of(compile_time_sample)
	assert kind_of(compile_time_sample, tokens, 'trim_space') == 'no token for trim_space'
}

fn tokens_of(source string) []SemanticToken {
	return tokens_for(source, 'sample.v')
}

// kind_of returns the kind of the token whose source text is exactly spelled,
// or a line saying there is none. The tests use needles that appear in the
// sample once as the kind they are checking.
fn kind_of(source string, tokens []SemanticToken, spelling string) string {
	for token in tokens {
		if source[token.start_byte..token.end_byte] == spelling {
			return token.kind
		}
	}
	return 'no token for ${spelling}'
}

fn modifiers_of(source string, tokens []SemanticToken, spelling string) []string {
	for token in tokens {
		if source[token.start_byte..token.end_byte] == spelling {
			return token.modifiers
		}
	}
	return []
}

fn has_modifier(modifiers []string, want string) bool {
	return want in modifiers
}

fn test_keywords_come_through_as_keywords() {
	tokens := tokens_of(sample)
	assert kind_of(sample, tokens, 'struct') == 'keyword'
	assert kind_of(sample, tokens, 'return') == 'keyword'
	assert kind_of(sample, tokens, 'mut') == 'keyword'
}

fn test_declared_names_get_the_type_of_thing_they_declare() {
	tokens := tokens_of(sample)
	assert kind_of(sample, tokens, 'Server') == 'struct'
	assert kind_of(sample, tokens, 'Severity') == 'enum'
	assert kind_of(sample, tokens, 'warning') == 'enumMember'
	assert kind_of(sample, tokens, 'Store') == 'interface'
	assert kind_of(sample, tokens, 'Handler') == 'type'
	assert kind_of(sample, tokens, 'default_name') == 'variable'
	assert kind_of(sample, tokens, 'count') == 'variable'
	assert kind_of(sample, tokens, 'name') == 'property'
	assert kind_of(sample, tokens, 'workers') == 'property'
}

fn test_a_function_with_a_receiver_is_a_method() {
	tokens := tokens_of(sample)
	assert kind_of(sample, tokens, 'start') == 'method'
	assert kind_of(sample, tokens, 'greet') == 'function'
}

fn test_parameters_and_types_are_typed() {
	tokens := tokens_of(sample)
	assert kind_of(sample, tokens, 'loud') == 'parameter'
	assert kind_of(sample, tokens, 'int') == 'type'
	assert kind_of(sample, tokens, 'bool') == 'type'
}

fn test_literals_comments_attributes_and_operators_are_typed() {
	tokens := tokens_of(sample)
	assert kind_of(sample, tokens, '4') == 'number'
	assert kind_of(sample, tokens, '1.5') == 'number'
	assert kind_of(sample, tokens, "'visor'") == 'string'
	assert kind_of(sample, tokens, '"hello 0x2a 3.5"') == 'string'
	// the 3.5 in that string is not a number: a string literal is one token and
	// nothing inside it is walked
	assert kind_of(sample, tokens, '3.5') == 'no token for 3.5'
	assert kind_of(sample, tokens, '// Severity ranks a finding.') == 'comment'
	assert kind_of(sample, tokens, '@[heap]') == 'decorator'
	assert kind_of(sample, tokens, ':=') == 'operator'
}

fn test_a_const_is_read_only() {
	tokens := tokens_of(sample)
	modifiers := modifiers_of(sample, tokens, 'default_name')
	assert has_modifier(modifiers, modifier_declaration)
	assert has_modifier(modifiers, modifier_readonly)
	// a local variable is declared and nothing more
	local := modifiers_of(sample, tokens, 'count')
	assert local.len == 1
	assert has_modifier(local, modifier_declaration)
}

fn test_a_reference_is_left_to_the_client() {
	tokens := tokens_of(sample)
	// greeting is called, not declared, and telling a call from a field of the
	// same name needs the index rather than the tree. Nothing here claims it.
	assert kind_of(sample, tokens, 'greeting') == 'no token for greeting'
}

fn test_tokens_come_back_in_document_order_without_overlapping() {
	tokens := tokens_of(sample)
	assert tokens.len > 20
	for i in 1 .. tokens.len {
		assert tokens[i].start_byte >= tokens[i - 1].end_byte
	}
}

fn test_every_token_carries_a_kind_the_legend_knows() {
	tokens := tokens_of(sample)
	for token in tokens {
		assert token.kind in token_kinds
	}
}

fn test_a_block_comment_is_one_token() {
	source := '/* a comment\n   over three\n   lines */\nfn main() {}'
	tokens := tokens_of(source)
	mut comments := 0
	for token in tokens {
		if token.kind == 'comment' {
			comments++
			// the wire layer is what splits a token that spans lines, so the
			// feature layer reports what the tree said
			assert source[token.start_byte..token.end_byte].starts_with('/*')
			assert source[token.start_byte..token.end_byte].ends_with('*/')
		}
	}
	assert comments == 1
}

fn test_a_buffer_with_nothing_in_it_has_no_tokens() {
	assert tokens_of('').len == 0
	assert tokens_of('\n').len == 0
}

fn test_an_unsaved_buffer_can_be_walked() {
	// nothing here reads from disk, which is what lets a buffer that has never
	// been saved be highlighted
	tokens := tokens_for('fn main() {}\n', 'nowhere.v')
	assert tokens.len > 0
}
