module bindings

// TreeCursor[T], the cursor that walks a tree node by node.

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
