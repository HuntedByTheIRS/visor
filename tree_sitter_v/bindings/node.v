module bindings

// Node[T], the accessors and walkers over a node in a tree.

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
