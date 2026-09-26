module bindings

// V 0.5.2 resolves a method on the receiver of a C struct method, but not on a
// C struct value reached through a field or a generic parameter, which is how
// bindings.v holds these values. The operations that carry logic, and the ones
// that answer none for a null node, are therefore written out here as plain
// functions. The methods above stay for callers that hold the node as a
// receiver.
// ts_node_type_name returns the grammar type name of a node.
pub fn ts_node_type_name(node C.TSNode) string {
	if C.ts_node_is_null(node) {
		return '<null node>'
	}
	c := &char(C.ts_node_type(node))
	return unsafe { c.vstring() }
}

// ts_node_sexpr returns the node and its children as an s-expression.
pub fn ts_node_sexpr(node C.TSNode) string {
	if C.ts_node_is_null(node) {
		return '<null node>'
	}
	sexpr := C.ts_node_string(node)
	return unsafe { sexpr.vstring() }
}

// ts_node_text returns the source text a node covers, read out of text.
pub fn ts_node_text(node C.TSNode, text string) string {
	if C.ts_node_is_null(node) {
		return ''
	}
	start_index := C.ts_node_start_byte(node)
	end_index := C.ts_node_end_byte(node)
	if start_index >= end_index || start_index >= u32(text.len) || end_index > u32(text.len) {
		return ''
	}
	return text.substr(int(start_index), int(end_index))
}

// ts_node_parent returns the parent of a node.
pub fn ts_node_parent(node C.TSNode) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	parent := C.ts_node_parent(node)
	if C.ts_node_is_null(parent) {
		return none
	}
	return parent
}

// ts_node_child returns the child at an index.
pub fn ts_node_child(node C.TSNode, index u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	child := C.ts_node_child(node, index)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// ts_node_named_child returns the named child at an index, with anonymous
// children skipped.
pub fn ts_node_named_child(node C.TSNode, index u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	child := C.ts_node_named_child(node, index)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// ts_node_child_by_field_name returns the child in a grammar field.
pub fn ts_node_child_by_field_name(node C.TSNode, name string) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	child := C.ts_node_child_by_field_name(node, &char(name.str), u32(name.len))
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// ts_node_next_sibling returns the sibling after a node.
pub fn ts_node_next_sibling(node C.TSNode) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	sibling := C.ts_node_next_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

// ts_node_prev_sibling returns the sibling before a node.
pub fn ts_node_prev_sibling(node C.TSNode) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	sibling := C.ts_node_prev_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

// ts_node_next_named_sibling returns the next sibling with a grammar name.
pub fn ts_node_next_named_sibling(node C.TSNode) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	sibling := C.ts_node_next_named_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

// ts_node_prev_named_sibling returns the previous sibling with a grammar
// name.
pub fn ts_node_prev_named_sibling(node C.TSNode) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	sibling := C.ts_node_prev_named_sibling(node)
	if C.ts_node_is_null(sibling) {
		return none
	}
	return sibling
}

// ts_node_first_child_for_byte returns the first child starting at or after
// a byte offset.
pub fn ts_node_first_child_for_byte(node C.TSNode, offset u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	child := C.ts_node_first_child_for_byte(node, offset)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// ts_node_first_named_child_for_byte does the same over named children.
pub fn ts_node_first_named_child_for_byte(node C.TSNode, offset u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	child := C.ts_node_first_named_child_for_byte(node, offset)
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// ts_node_descendant_for_byte_range returns the smallest node covering a
// byte range.
pub fn ts_node_descendant_for_byte_range(node C.TSNode, start_range u32, end_range u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	desc := C.ts_node_descendant_for_byte_range(node, start_range, end_range)
	if C.ts_node_is_null(desc) {
		return none
	}
	return desc
}

// ts_node_descendant_for_point_range does the same for a row and column
// range.
pub fn ts_node_descendant_for_point_range(node C.TSNode, start_point C.TSPoint, end_point C.TSPoint) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	desc := C.ts_node_descendant_for_point_range(node, start_point, end_point)
	if C.ts_node_is_null(desc) {
		return none
	}
	return desc
}

// ts_node_named_descendant_for_byte_range returns the smallest named node
// covering a byte range.
pub fn ts_node_named_descendant_for_byte_range(node C.TSNode, start_range u32, end_range u32) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	desc := C.ts_node_named_descendant_for_byte_range(node, start_range, end_range)
	if C.ts_node_is_null(desc) {
		return none
	}
	return desc
}

// ts_node_named_descendant_for_point_range does the same for a row and
// column range.
pub fn ts_node_named_descendant_for_point_range(node C.TSNode, start_point C.TSPoint, end_point C.TSPoint) ?C.TSNode {
	if C.ts_node_is_null(node) {
		return none
	}
	desc := C.ts_node_named_descendant_for_point_range(node, start_point, end_point)
	if C.ts_node_is_null(desc) {
		return none
	}
	return desc
}
