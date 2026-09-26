module bindings

// A node and the readers over it: text, points, bytes, ranges, the type name.

@[typedef]
pub struct C.TSNode {
	context [4]u32
	id      voidptr
	tree    &TSTree
}

fn C.ts_node_string(node C.TSNode) &char
fn C.ts_node_type(node C.TSNode) &char
fn C.ts_node_is_null(node C.TSNode) bool
fn C.ts_node_is_named(node C.TSNode) bool
fn C.ts_node_is_missing(node C.TSNode) bool
fn C.ts_node_is_extra(node C.TSNode) bool
fn C.ts_node_has_changes(node C.TSNode) bool
fn C.ts_node_has_error(node C.TSNode) bool

fn C.ts_node_start_point(node C.TSNode) C.TSPoint
fn C.ts_node_end_point(node C.TSNode) C.TSPoint
fn C.ts_node_start_byte(node C.TSNode) u32
fn C.ts_node_end_byte(node C.TSNode) u32

fn C.ts_node_parent(node C.TSNode) C.TSNode
fn C.ts_node_child(node C.TSNode, index u32) C.TSNode
fn C.ts_node_child_count(node C.TSNode) u32
fn C.ts_node_named_child(node C.TSNode, index u32) C.TSNode
fn C.ts_node_named_child_count(node C.TSNode) u32
fn C.ts_node_child_by_field_name(node C.TSNode, field_name &char, field_name_length u32) C.TSNode

fn C.ts_node_next_sibling(node C.TSNode) C.TSNode
fn C.ts_node_prev_sibling(node C.TSNode) C.TSNode
fn C.ts_node_next_named_sibling(node C.TSNode) C.TSNode
fn C.ts_node_prev_named_sibling(node C.TSNode) C.TSNode

fn C.ts_node_first_child_for_byte(node C.TSNode, offset u32) C.TSNode
fn C.ts_node_first_named_child_for_byte(node C.TSNode, offset u32) C.TSNode

fn C.ts_node_descendant_for_byte_range(node C.TSNode, start_offset u32, end_offset u32) C.TSNode
fn C.ts_node_descendant_for_point_range(node C.TSNode, start_point C.TSPoint, end_point C.TSPoint) C.TSNode
fn C.ts_node_named_descendant_for_byte_range(node C.TSNode, start_offset u32, end_offset u32) C.TSNode
fn C.ts_node_named_descendant_for_point_range(node C.TSNode, start_point C.TSPoint, end_point C.TSPoint) C.TSNode

fn C.ts_node_eq(node C.TSNode, another_node C.TSNode) bool

// text returns the source text this node covers, and an empty string when
// the range falls outside the text it was given.
pub fn (node C.TSNode) text(text string) string {
	start_index := node.start_byte()
	end_index := node.end_byte()
	if start_index >= end_index || start_index >= u32(text.len) || end_index > u32(text.len) {
		return ''
	}
	return text.substr(int(start_index), int(end_index))
}

@[inline]
fn (node C.TSNode) sexpr_str() string {
	if node.is_null() {
		return '<null node>'
	}

	sexpr := C.ts_node_string(node)
	return unsafe { sexpr.vstring() }
}

// text_length returns how many bytes the node covers.
@[inline]
pub fn (node C.TSNode) text_length() u32 {
	start := node.start_byte()
	end := node.end_byte()
	return end - start
}

// start_point returns the row and column the node starts at, and 0,0 for a
// null node.
@[inline]
pub fn (node C.TSNode) start_point() C.TSPoint {
	if node.is_null() {
		return C.TSPoint{0, 0}
	}

	return C.ts_node_start_point(node)
}

fn (node C.TSNode) end_point() C.TSPoint {
	if node.is_null() {
		return C.TSPoint{0, 0}
	}

	return C.ts_node_end_point(node)
}

fn (node C.TSNode) start_byte() u32 {
	if node.is_null() {
		return 0
	}

	return C.ts_node_start_byte(node)
}

fn (node C.TSNode) end_byte() u32 {
	if node.is_null() {
		return 0
	}

	return C.ts_node_end_byte(node)
}

@[inline]
fn (node C.TSNode) range() C.TSRange {
	return C.TSRange{
		start_point: node.start_point()
		end_point:   node.end_point()
		start_byte:  node.start_byte()
		end_byte:    node.end_byte()
	}
}

// type_name returns the grammar type name, and a marker when the node is
// null.
pub fn (node C.TSNode) type_name() string {
	if node.is_null() {
		return '<null node>'
	}
	c := &char(C.ts_node_type(node))
	return unsafe { c.vstring() }
}

@[inline]
fn (node C.TSNode) is_null() bool {
	return C.ts_node_is_null(node)
}

@[inline]
fn (node C.TSNode) is_named() bool {
	return C.ts_node_is_named(node)
}

@[inline]
fn (node C.TSNode) is_missing() bool {
	return C.ts_node_is_missing(node)
}

@[inline]
fn (node C.TSNode) is_extra() bool {
	return C.ts_node_is_extra(node)
}

@[inline]
fn (node C.TSNode) has_changes() bool {
	return C.ts_node_has_changes(node)
}

fn (node C.TSNode) is_error() bool {
	if node.is_null() {
		return true
	}
	return C.ts_node_has_error(node)
}
