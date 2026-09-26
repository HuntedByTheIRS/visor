module bindings

pub type TSParser = C.TSParser
pub type TSLanguage = C.TSLanguage

pub const language = C.tree_sitter_v()

pub struct Parser[T] {
mut:
	raw_parser   &TSParser = unsafe { nil }          @[required]
	type_factory NodeTypeFactory[T] @[required]
}

// new_parser creates a parser that resolves node types through type_factory.
pub fn new_parser[T](type_factory NodeTypeFactory[T]) &Parser[T] {
	mut parser := new_ts_parser()
	return &Parser[T]{
		raw_parser:   parser
		type_factory: type_factory
	}
}

// set_language selects the grammar the parser uses.
@[inline]
pub fn (mut p Parser[T]) set_language(language &TSLanguage) {
	C.ts_parser_set_language(p.raw_parser, language)
}

// reset clears any state the parser carries between parses.
@[inline]
pub fn (mut p Parser[T]) reset() {
	C.ts_parser_reset(p.raw_parser)
}

// free releases the underlying C parser.
@[inline]
pub fn (p &Parser[T]) free() {
	unsafe {
		C.ts_parser_delete(p.raw_parser)
	}
}

@[params]
pub struct ParseConfig {
pub:
	source string @[required]
	tree   &TSTree = &TSTree(unsafe { nil })
}

// parse_string parses source with the language set earlier and returns the tree.
pub fn (mut p Parser[T]) parse_string(cfg ParseConfig) &Tree[T] {
	tree := ts_parser_parse_string(p.raw_parser, cfg.source, cfg.tree)
	return &Tree[T]{
		raw_tree:     tree
		type_factory: p.type_factory
	}
}

pub interface NodeTypeFactory[T] {
	get_type(type_name string) T
}

pub struct Tree[T] {
	type_factory NodeTypeFactory[T] @[required]
pub:
	raw_tree &TSTree = unsafe { nil } @[required]
}

// free releases the underlying C tree.
@[unsafe]
pub fn (tree &Tree[T]) free() {
	unsafe { tree.raw_tree.free() }
}

// root_node returns the tree's root node, the one spanning the whole source.
pub fn (tree Tree[T]) root_node() Node[T] {
	return new_tsnode[T](tree.type_factory, tree.raw_tree.root_node())
}

// new_tsnode wraps a raw C node in a Node, resolving its type through factory.
pub fn new_tsnode[T](factory NodeTypeFactory[T], node TSNode) Node[T] {
	return Node[T]{
		raw_node:     node
		type_factory: factory
		type_name:    factory.get_type(ts_node_type_name(node))
	}
}

pub struct Node[T] {
	type_factory NodeTypeFactory[T] @[required]
pub:
	raw_node  TSNode @[required]
	type_name T      @[required]
}

pub type TSRange = C.TSRange

// str renders the range's points and byte offsets on separate lines.
pub fn (r TSRange) str() string {
	return '
{
    start: ${TSPoint(r.start_point)}
    end: ${TSPoint(r.end_point)}
    start_byte: ${r.start_byte}
    end_byte: ${r.end_byte}
}
'.trim_indent()
}

pub type TSPoint = C.TSPoint

// str renders the point as a row and column pair.
pub fn (p TSPoint) str() string {
	return '(${p.row}, ${p.column})'
}
