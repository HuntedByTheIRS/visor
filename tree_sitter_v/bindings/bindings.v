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

// text returns the slice of text the node spans.
@[inline]
pub fn (node Node[T]) text(text string) string {
	return ts_node_text(node.raw_node, text)
}

// text_matches reports whether the node's span in all_text is exactly text_to_find.
@[inline]
pub fn (node Node[T]) text_matches(all_text string, text_to_find string) bool {
	text_len := u32(text_to_find.len)
	node_len := node.text_length()

	// if the text we are looking for does not match in length,
	// then the text cannot exactly match
	if text_len != node_len {
		return false
	}

	return node.text(all_text) == text_to_find
}

// first_char returns the first byte of the node's span in text, or 0 when the span starts past the end.
@[inline]
pub fn (node Node[T]) first_char(text string) u8 {
	start_index := node.start_byte()
	if start_index >= u32(text.len) {
		return 0
	}
	return text[start_index]
}

// text_length returns the node's length in bytes.
@[inline]
pub fn (node Node[T]) text_length() u32 {
	start := C.ts_node_start_byte(node.raw_node)
	end := C.ts_node_end_byte(node.raw_node)
	return end - start
}

// str returns the node in s-expression form.
@[inline]
pub fn (node Node[T]) str() string {
	return ts_node_sexpr(node.raw_node)
}

// start_point returns the node's starting row and column.
@[inline]
pub fn (node Node[T]) start_point() TSPoint {
	return C.ts_node_start_point(node.raw_node)
}

// end_point returns the node's ending row and column.
@[inline]
pub fn (node Node[T]) end_point() TSPoint {
	return C.ts_node_end_point(node.raw_node)
}

// start_byte returns the node's starting byte offset.
@[inline]
pub fn (node Node[T]) start_byte() u32 {
	return C.ts_node_start_byte(node.raw_node)
}

// end_byte returns the node's ending byte offset.
@[inline]
pub fn (node Node[T]) end_byte() u32 {
	return C.ts_node_end_byte(node.raw_node)
}

// range returns the node's start point, end point and byte offsets as one value.
@[inline]
pub fn (node Node[T]) range() TSRange {
	return TSRange{
		start_point: C.ts_node_start_point(node.raw_node)
		end_point:   C.ts_node_end_point(node.raw_node)
		start_byte:  C.ts_node_start_byte(node.raw_node)
		end_byte:    C.ts_node_end_byte(node.raw_node)
	}
}

// is_null reports whether the node is the null node tree-sitter returns on failure.
@[inline]
pub fn (node Node[T]) is_null() bool {
	return C.ts_node_is_null(node.raw_node)
}

// is_leaf reports whether the node has no children.
@[inline]
pub fn (node Node[T]) is_leaf() bool {
	return node.child_count() == 0
}

// is_named reports whether the node is named in its grammar.
@[inline]
pub fn (node Node[T]) is_named() bool {
	return C.ts_node_is_named(node.raw_node)
}

// is_missing reports whether error recovery inserted the node.
@[inline]
pub fn (node Node[T]) is_missing() bool {
	return C.ts_node_is_missing(node.raw_node)
}

// is_extra reports whether the node is an extra, such as a comment.
@[inline]
pub fn (node Node[T]) is_extra() bool {
	return C.ts_node_is_extra(node.raw_node)
}

// has_changes reports whether the node was edited after the tree was built.
@[inline]
pub fn (node Node[T]) has_changes() bool {
	return C.ts_node_has_changes(node.raw_node)
}

// is_error reports whether the node or one of its descendants is an error.
@[inline]
pub fn (node Node[T]) is_error() bool {
	return C.ts_node_has_error(node.raw_node)
}

// parent returns the node's parent, or none for the root.
pub fn (node Node[T]) parent() ?Node[T] {
	parent := ts_node_parent(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, parent)
}

// parent_nth returns the ancestor depth levels above the node, or none when the tree ends first.
pub fn (node Node[T]) parent_nth(depth int) ?Node[T] {
	mut res := node.raw_node
	for _ in 0 .. depth {
		res = ts_node_parent(res) or { return none }
	}
	return new_tsnode[T](node.type_factory, res)
}

// is_parent_of reports whether the node is an ancestor of other.
pub fn (node Node[T]) is_parent_of(other Node[T]) bool {
	mut parent := other.parent() or { return false }

	for {
		if parent.equal(node) {
			return true
		}
		parent = parent.parent() or { break }
	}

	return false
}

// child returns the child at index pos, unnamed children included.
pub fn (node Node[T]) child(pos u32) ?Node[T] {
	child := ts_node_child(node.raw_node, pos) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// child_count returns the number of children, named and anonymous.
@[inline]
pub fn (node Node[T]) child_count() u32 {
	return C.ts_node_child_count(node.raw_node)
}

// named_child returns the named child at index pos, or none when there is none.
pub fn (node Node[T]) named_child(pos u32) ?Node[T] {
	child := ts_node_named_child(node.raw_node, pos) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// named_child_count returns the number of named children.
@[inline]
pub fn (node Node[T]) named_child_count() u32 {
	return C.ts_node_named_child_count(node.raw_node)
}

// child_by_field_name returns the child the grammar puts in the given field, or none.
pub fn (node Node[T]) child_by_field_name(name string) ?Node[T] {
	child := ts_node_child_by_field_name(node.raw_node, name) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// first_child returns the node's first child, or none when it has no children.
pub fn (node Node[T]) first_child() ?Node[T] {
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := ts_node_child(node.raw_node, 0) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// last_child returns the node's last child, or none when it has no children.
pub fn (node Node[T]) last_child() ?Node[T] {
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := ts_node_child(node.raw_node, count_child - 1) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// next_sibling returns the sibling after the node, or none at the end.
pub fn (node Node[T]) next_sibling() ?Node[T] {
	sibling := ts_node_next_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

// prev_sibling returns the sibling before the node, or none at the start.
pub fn (node Node[T]) prev_sibling() ?Node[T] {
	sibling := ts_node_prev_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

// next_named_sibling returns the next sibling that is named, or none.
pub fn (node Node[T]) next_named_sibling() ?Node[T] {
	sibling := ts_node_next_named_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

// prev_named_sibling returns the previous sibling that is named, or none.
pub fn (node Node[T]) prev_named_sibling() ?Node[T] {
	sibling := ts_node_prev_named_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

// first_child_for_byte returns the first child whose span extends past offset, or none.
pub fn (node Node[T]) first_child_for_byte(offset u32) ?Node[T] {
	child := ts_node_first_child_for_byte(node.raw_node, offset) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// first_named_child_for_byte returns the first named child whose span extends past offset, or none.
pub fn (node Node[T]) first_named_child_for_byte(offset u32) ?Node[T] {
	child := ts_node_first_named_child_for_byte(node.raw_node, offset) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

// descendant_for_byte_range returns the smallest node spanning the byte range, or none.
pub fn (node Node[T]) descendant_for_byte_range(start_range u32, end_range u32) ?Node[T] {
	desc := ts_node_descendant_for_byte_range(node.raw_node, start_range, end_range) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

// descendant_for_point_range returns the smallest node spanning the row and column range, or none.
pub fn (node Node[T]) descendant_for_point_range(start_point TSPoint, end_point TSPoint) ?Node[T] {
	desc := ts_node_descendant_for_point_range(node.raw_node, start_point, end_point) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

// named_descendant_for_byte_range returns the smallest named node spanning the byte range, or none.
pub fn (node Node[T]) named_descendant_for_byte_range(start_range u32, end_range u32) ?Node[T] {
	desc := ts_node_named_descendant_for_byte_range(node.raw_node, start_range, end_range) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

// named_descendant_for_point_range returns the smallest named node spanning the row and column range, or none.
pub fn (node Node[T]) named_descendant_for_point_range(start_point TSPoint, end_point TSPoint) ?Node[T] {
	desc := ts_node_named_descendant_for_point_range(node.raw_node, start_point, end_point) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

// first_node_by_type returns the first child whose type is type_name, or none.
pub fn (node Node[T]) first_node_by_type(type_name T) ?Node[T] {
	mut named_child := node.named_child(0) or { return none }
	len := node.child_count()
	for i := 0; i < int(len); i++ {
		if named_child.type_name == type_name {
			return named_child
		}
		named_child = named_child.next_sibling() or { continue }
	}
	return none
}

// last_node_by_type returns the last child whose type is type_name, or none.
pub fn (node Node[T]) last_node_by_type(type_name T) ?Node[T] {
	len := node.child_count()
	mut named_child := node.named_child(len - 1) or { return none }
	for i := int(len - 1); i >= 0; i-- {
		if named_child.type_name == type_name {
			return named_child
		}
		named_child = named_child.prev_sibling() or { continue }
	}
	return none
}

// == reports whether two nodes wrap the same C node.
@[inline]
pub fn (node Node[T]) == (other_node Node[T]) bool {
	return C.ts_node_eq(node.raw_node, other_node.raw_node)
}

// equal reports whether two nodes wrap the same C node.
@[inline]
pub fn (node Node[T]) equal(other_node Node[T]) bool {
	return C.ts_node_eq(node.raw_node, other_node.raw_node)
}

// tree_cursor returns a cursor positioned at the node.
@[inline]
pub fn (node Node[T]) tree_cursor() TreeCursor[T] {
	return TreeCursor[T]{
		type_factory: node.type_factory
		raw_cursor:   C.ts_tree_cursor_new(node.raw_node)
	}
}

pub struct TreeCursor[T] {
	type_factory NodeTypeFactory[T] @[required]
pub mut:
	raw_cursor C.TSTreeCursor @[required]
}

// reset moves the cursor to node.
@[inline]
pub fn (mut cursor TreeCursor[T]) reset(node Node[T]) {
	C.ts_tree_cursor_reset(cursor.raw_cursor, node.raw_node)
}

// current_node returns the node the cursor points at, or none at the end.
@[inline]
pub fn (cursor TreeCursor[T]) current_node() ?Node[T] {
	got_node := ts_cursor_current_node(cursor.raw_cursor) or { return none }
	return new_tsnode[T](cursor.type_factory, got_node)
}

// current_field_name returns the field the cursor's node sits in, empty when it has none.
@[inline]
pub fn (cursor TreeCursor[T]) current_field_name() string {
	return ts_cursor_field_name(cursor.raw_cursor)
}

// to_parent moves the cursor to its parent, reporting whether there was one.
@[inline]
pub fn (mut cursor TreeCursor[T]) to_parent() bool {
	return C.ts_tree_cursor_goto_parent(cursor.raw_cursor)
}

// next moves the cursor to its next sibling, reporting whether there was one.
@[inline]
pub fn (mut cursor TreeCursor[T]) next() bool {
	return C.ts_tree_cursor_goto_next_sibling(cursor.raw_cursor)
}

// to_first_child moves the cursor to its first child, reporting whether there was one.
@[inline]
pub fn (mut cursor TreeCursor[T]) to_first_child() bool {
	return C.ts_tree_cursor_goto_first_child(cursor.raw_cursor)
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
