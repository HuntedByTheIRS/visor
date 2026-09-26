module bindings

// The tree cursor.

fn C.ts_tree_cursor_new(node C.TSNode) C.TSTreeCursor

pub type TSTreeCursor = C.TSTreeCursor

// tree_cursor starts a cursor at this node.
@[inline]
pub fn (node C.TSNode) tree_cursor() TSTreeCursor {
	return C.ts_tree_cursor_new(node)
}

@[typedef]
pub struct C.TSTreeCursor {
	tree    voidptr
	id      voidptr
	context [3]u32
}

fn C.ts_tree_cursor_delete(cursor &C.TSTreeCursor)
fn C.ts_tree_cursor_reset(cursor &C.TSTreeCursor, node C.TSNode)
fn C.ts_tree_cursor_current_node(cursor &C.TSTreeCursor) C.TSNode
fn C.ts_tree_cursor_current_field_name(cursor &C.TSTreeCursor) &char
fn C.ts_tree_cursor_goto_parent(cursor &C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_next_sibling(cursor &C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_first_child(cursor &C.TSTreeCursor) bool
fn C.ts_tree_cursor_first_child_for_byte(cursor &C.TSTreeCursor, idx u32) i64
fn C.ts_tree_cursor_copy(cursor &C.TSTreeCursor) C.TSTreeCursor

// delete releases the cursor.
@[inline; unsafe]
pub fn (cursor &C.TSTreeCursor) delete() {
	C.ts_tree_cursor_delete(cursor)
}

@[inline]
fn (mut cursor C.TSTreeCursor) reset(node C.TSNode) {
	C.ts_tree_cursor_reset(cursor, node)
}

pub type TSNode = C.TSNode

// current_node returns the node the cursor points at, none when it points
// at nothing.
@[inline]
pub fn (cursor &C.TSTreeCursor) current_node() ?TSNode {
	got_node := C.ts_tree_cursor_current_node(cursor)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

// current_field_name returns the grammar field the cursor sits on.
@[inline]
pub fn (cursor &C.TSTreeCursor) current_field_name() string {
	c := &char(C.ts_tree_cursor_current_field_name(cursor))
	return unsafe { c.vstring() }
}

// to_parent moves the cursor to the parent, false when it cannot.
@[inline]
pub fn (mut cursor C.TSTreeCursor) to_parent() bool {
	return C.ts_tree_cursor_goto_parent(cursor)
}

// next moves the cursor to the next sibling, false when there is none.
@[inline]
pub fn (mut cursor C.TSTreeCursor) next() bool {
	return C.ts_tree_cursor_goto_next_sibling(cursor)
}

// to_first_child moves the cursor to the first child, false when there is
// none.
@[inline]
pub fn (mut cursor C.TSTreeCursor) to_first_child() bool {
	return C.ts_tree_cursor_goto_first_child(cursor)
}

// ts_cursor_field_name returns the grammar field the cursor sits on.
pub fn ts_cursor_field_name(cursor &C.TSTreeCursor) string {
	c := &char(C.ts_tree_cursor_current_field_name(cursor))
	return unsafe { c.vstring() }
}

// ts_cursor_current_node returns the node the cursor points at.
pub fn ts_cursor_current_node(cursor &C.TSTreeCursor) ?C.TSNode {
	got_node := C.ts_tree_cursor_current_node(cursor)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}
