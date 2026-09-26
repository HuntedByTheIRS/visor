module bindings

// Walking a node: its parent, children, siblings, fields and byte ranges.

// V 0.5.2 resolves a method on the receiver of a C struct method but not on a
// local of that C struct type, so the checks on locals below call the C
// functions the methods forward to.
// parent_nth walks up this many parents, none when the tree ends first.
pub fn (node C.TSNode) parent_nth(depth int) ?TSNode {
	if node.is_null() {
		return none
	}
	mut res := node
	for _ in 0 .. depth {
		res = C.ts_node_parent(res)
	}
	if C.ts_node_is_null(res) {
		return none
	}
	return res
}

// parent returns the node above this one, none for a null node or the
// root.
pub fn (node C.TSNode) parent() ?C.TSNode {
	if node.is_null() {
		return none
	}
	parent := C.ts_node_parent(node)
	if C.ts_node_is_null(parent) {
		return none
	}
	return parent
}

// first_child returns the first child, none when there is none.
pub fn (node C.TSNode) first_child() ?C.TSNode {
	if node.is_null() {
		return none
	}
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := C.ts_node_child(node, 0)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// last_child returns the last child, none when there is none.
pub fn (node C.TSNode) last_child() ?C.TSNode {
	if node.is_null() {
		return none
	}
	count_child := node.child_count()
	if count_child == 0 {
		return none
	}
	child := C.ts_node_child(node, count_child - 1)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

fn (node C.TSNode) child(index u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	child := C.ts_node_child(node, index)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

@[inline]
fn (node C.TSNode) child_count() u32 {
	return C.ts_node_child_count(node)
}

fn (node C.TSNode) named_child(pos u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	child := C.ts_node_named_child(node, pos)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

fn (node C.TSNode) named_child_count() u32 {
	if node.is_null() {
		return 0
	}
	return C.ts_node_named_child_count(node)
}

// child_by_field_name returns the child in the named grammar field.
pub fn (node C.TSNode) child_by_field_name(name string) ?C.TSNode {
	if node.is_null() {
		return none
	}
	child := C.ts_node_child_by_field_name(node, &char(name.str), u32(name.len))
	if C.ts_node_is_null(child) {
		return none
	}

	return child
}

fn (node C.TSNode) next_sibling() ?C.TSNode {
	if node.is_null() {
		return none
	}
	sibling := C.ts_node_next_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

fn (node C.TSNode) prev_sibling() ?C.TSNode {
	if node.is_null() {
		return none
	}
	sibling := C.ts_node_prev_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

fn (node C.TSNode) next_named_sibling() ?C.TSNode {
	if node.is_null() {
		return none
	}
	sibling := C.ts_node_next_named_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

fn (node C.TSNode) prev_named_sibling() ?C.TSNode {
	if node.is_null() {
		return none
	}
	sibling := C.ts_node_prev_named_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

fn (node C.TSNode) first_child_for_byte(offset u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_first_child_for_byte(node, offset)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

fn (node C.TSNode) first_named_child_for_byte(offset u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_first_named_child_for_byte(node, offset)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

fn (node C.TSNode) descendant_for_byte_range(start_range u32, end_range u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_descendant_for_byte_range(node, start_range, end_range)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

fn (node C.TSNode) descendant_for_point_range(start_point C.TSPoint, end_point C.TSPoint) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_descendant_for_point_range(node, start_point, end_point)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

fn (node C.TSNode) named_descendant_for_byte_range(start_range u32, end_range u32) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_named_descendant_for_byte_range(node, start_range, end_range)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}

fn (node C.TSNode) named_descendant_for_point_range(start_point C.TSPoint, end_point C.TSPoint) ?C.TSNode {
	if node.is_null() {
		return none
	}
	got_node := C.ts_node_named_descendant_for_point_range(node, start_point, end_point)
	if C.ts_node_is_null(got_node) {
		return none
	}
	return got_node
}
