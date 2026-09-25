module bindings

pub type TSParser = C.TSParser
pub type TSLanguage = C.TSLanguage

pub const language = unsafe { &TSLanguage(C.tree_sitter_v()) }

pub struct Parser[T] {
mut:
	raw_parser   &TSParser = unsafe { nil }          @[required]
	type_factory NodeTypeFactory[T] @[required]
}

pub fn new_parser[T](type_factory NodeTypeFactory[T]) &Parser[T] {
	mut parser := new_ts_parser()
	return &Parser[T]{
		raw_parser:   parser
		type_factory: type_factory
	}
}

@[inline]
pub fn (mut p Parser[T]) set_language(language &TSLanguage) {
	C.ts_parser_set_language(p.raw_parser, language)
}

@[inline]
pub fn (mut p Parser[T]) reset() {
	C.ts_parser_reset(p.raw_parser)
}

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

@[unsafe]
pub fn (tree &Tree[T]) free() {
	unsafe { tree.raw_tree.free() }
}

pub fn (tree Tree[T]) root_node() Node[T] {
	return new_tsnode[T](tree.type_factory, tree.raw_tree.root_node())
}

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

@[inline]
pub fn (node Node[T]) text(text string) string {
	return ts_node_text(node.raw_node, text)
}

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

@[inline]
pub fn (node Node[T]) first_char(text string) u8 {
	start_index := node.start_byte()
	if start_index >= u32(text.len) {
		return 0
	}
	return text[start_index]
}

@[inline]
pub fn (node Node[T]) text_length() u32 {
	start := C.ts_node_start_byte(node.raw_node)
	end := C.ts_node_end_byte(node.raw_node)
	return end - start
}

@[inline]
pub fn (node Node[T]) str() string {
	return ts_node_sexpr(node.raw_node)
}

@[inline]
pub fn (node Node[T]) start_point() TSPoint {
	return C.ts_node_start_point(node.raw_node)
}

@[inline]
pub fn (node Node[T]) end_point() TSPoint {
	return C.ts_node_end_point(node.raw_node)
}

@[inline]
pub fn (node Node[T]) start_byte() u32 {
	return C.ts_node_start_byte(node.raw_node)
}

@[inline]
pub fn (node Node[T]) end_byte() u32 {
	return C.ts_node_end_byte(node.raw_node)
}

@[inline]
pub fn (node Node[T]) range() TSRange {
	return TSRange{
		start_point: C.ts_node_start_point(node.raw_node)
		end_point:   C.ts_node_end_point(node.raw_node)
		start_byte:  C.ts_node_start_byte(node.raw_node)
		end_byte:    C.ts_node_end_byte(node.raw_node)
	}
}

@[inline]
pub fn (node Node[T]) is_null() bool {
	return C.ts_node_is_null(node.raw_node)
}

@[inline]
pub fn (node Node[T]) is_leaf() bool {
	return node.child_count() == 0
}

@[inline]
pub fn (node Node[T]) is_named() bool {
	return C.ts_node_is_named(node.raw_node)
}

@[inline]
pub fn (node Node[T]) is_missing() bool {
	return C.ts_node_is_missing(node.raw_node)
}

@[inline]
pub fn (node Node[T]) is_extra() bool {
	return C.ts_node_is_extra(node.raw_node)
}

@[inline]
pub fn (node Node[T]) has_changes() bool {
	return C.ts_node_has_changes(node.raw_node)
}

@[inline]
pub fn (node Node[T]) is_error() bool {
	return C.ts_node_has_error(node.raw_node)
}

pub fn (node Node[T]) parent() ?Node[T] {
	parent := ts_node_parent(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, parent)
}

pub fn (node Node[T]) parent_nth(depth int) ?Node[T] {
	mut res := node.raw_node
	for _ in 0 .. depth {
		res = ts_node_parent(res) or { return none }
	}
	return new_tsnode[T](node.type_factory, res)
}

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

pub fn (node Node[T]) child(pos u32) ?Node[T] {
	child := ts_node_child(node.raw_node, pos) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

@[inline]
pub fn (node Node[T]) child_count() u32 {
	return C.ts_node_child_count(node.raw_node)
}

pub fn (node Node[T]) named_child(pos u32) ?Node[T] {
	child := ts_node_named_child(node.raw_node, pos) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

@[inline]
pub fn (node Node[T]) named_child_count() u32 {
	return C.ts_node_named_child_count(node.raw_node)
}

pub fn (node Node[T]) child_by_field_name(name string) ?Node[T] {
	child := ts_node_child_by_field_name(node.raw_node, name) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

pub fn (node Node[T]) first_child() ?Node[T] {
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := ts_node_child(node.raw_node, 0) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

pub fn (node Node[T]) last_child() ?Node[T] {
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := ts_node_child(node.raw_node, count_child - 1) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

pub fn (node Node[T]) next_sibling() ?Node[T] {
	sibling := ts_node_next_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

pub fn (node Node[T]) prev_sibling() ?Node[T] {
	sibling := ts_node_prev_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

pub fn (node Node[T]) next_named_sibling() ?Node[T] {
	sibling := ts_node_next_named_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

pub fn (node Node[T]) prev_named_sibling() ?Node[T] {
	sibling := ts_node_prev_named_sibling(node.raw_node) or { return none }
	return new_tsnode[T](node.type_factory, sibling)
}

pub fn (node Node[T]) first_child_for_byte(offset u32) ?Node[T] {
	child := ts_node_first_child_for_byte(node.raw_node, offset) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

pub fn (node Node[T]) first_named_child_for_byte(offset u32) ?Node[T] {
	child := ts_node_first_named_child_for_byte(node.raw_node, offset) or { return none }
	return new_tsnode[T](node.type_factory, child)
}

pub fn (node Node[T]) descendant_for_byte_range(start_range u32, end_range u32) ?Node[T] {
	desc := ts_node_descendant_for_byte_range(node.raw_node, start_range, end_range) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

pub fn (node Node[T]) descendant_for_point_range(start_point TSPoint, end_point TSPoint) ?Node[T] {
	desc := ts_node_descendant_for_point_range(node.raw_node, start_point, end_point) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

pub fn (node Node[T]) named_descendant_for_byte_range(start_range u32, end_range u32) ?Node[T] {
	desc := ts_node_named_descendant_for_byte_range(node.raw_node, start_range, end_range) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

pub fn (node Node[T]) named_descendant_for_point_range(start_point TSPoint, end_point TSPoint) ?Node[T] {
	desc := ts_node_named_descendant_for_point_range(node.raw_node, start_point, end_point) or {
		return none
	}
	return new_tsnode[T](node.type_factory, desc)
}

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

@[inline]
pub fn (node Node[T]) == (other_node Node[T]) bool {
	return C.ts_node_eq(node.raw_node, other_node.raw_node)
}

@[inline]
pub fn (node Node[T]) equal(other_node Node[T]) bool {
	return C.ts_node_eq(node.raw_node, other_node.raw_node)
}

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

@[inline]
pub fn (mut cursor TreeCursor[T]) reset(node Node[T]) {
	C.ts_tree_cursor_reset(cursor.raw_cursor, node.raw_node)
}

@[inline]
pub fn (cursor TreeCursor[T]) current_node() ?Node[T] {
	got_node := ts_cursor_current_node(cursor.raw_cursor) or { return none }
	return new_tsnode[T](cursor.type_factory, got_node)
}

@[inline]
pub fn (cursor TreeCursor[T]) current_field_name() string {
	return ts_cursor_field_name(cursor.raw_cursor)
}

@[inline]
pub fn (mut cursor TreeCursor[T]) to_parent() bool {
	return C.ts_tree_cursor_goto_parent(cursor.raw_cursor)
}

@[inline]
pub fn (mut cursor TreeCursor[T]) next() bool {
	return C.ts_tree_cursor_goto_next_sibling(cursor.raw_cursor)
}

@[inline]
pub fn (mut cursor TreeCursor[T]) to_first_child() bool {
	return C.ts_tree_cursor_goto_first_child(cursor.raw_cursor)
}

pub type TSRange = C.TSRange

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

pub fn (p TSPoint) str() string {
	return '(${p.row}, ${p.column})'
}
