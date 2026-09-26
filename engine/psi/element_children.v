// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

// sibling_of_type_backward returns the nearest earlier sibling with the
// given type.
pub fn (n &PsiElementImpl) sibling_of_type_backward(typ bindings.NodeType) ?PsiElement {
	mut res := PsiElement(n)
	for {
		res = res.prev_sibling_or_stub()?
		if res.element_type() == typ {
			return res
		}
	}

	return none
}

// children returns every child element in order. A stub-based element answers
// from its stub's children.
pub fn (n &PsiElementImpl) children() []PsiElement {
	if stub := n.get_stub() {
		children := stub.children_stubs()
		return children.get_psi()
	}

	if !n.is_valid_tree() {
		return []
	}

	mut result := []PsiElement{}
	mut child := n.node.first_child() or { return [] }
	for {
		result << create_element(child, n.containing_file)
		child = child.next_sibling() or { break }
	}
	return result
}

// named_children returns every child element whose type is not .unknown.
pub fn (n &PsiElementImpl) named_children() []PsiElement {
	if !n.is_valid_tree() {
		return []
	}

	if stub := n.get_stub() {
		children := stub.children_stubs()
		return children.get_psi()
	}

	mut result := []PsiElement{}
	mut child := n.node.first_child() or { return [] }
	for {
		if child.type_name != .unknown {
			result << create_element(child, n.containing_file)
		}
		child = child.next_sibling() or { break }
	}
	return result
}

// first_child returns the first child element, or none when there are none.
pub fn (n &PsiElementImpl) first_child() ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	child := n.node.first_child()?
	return create_element(child, n.containing_file)
}

// first_child_or_stub returns the first child, taken from the stub when the
// element is stub-based.
pub fn (n &PsiElementImpl) first_child_or_stub() ?PsiElement {
	if stub := n.get_stub() {
		child := stub.first_child()?
		return child.get_psi()
	}

	if !n.is_valid_tree() {
		return none
	}

	child := n.node.first_child()?
	return create_element(child, n.containing_file)
}

// last_child returns the last child element, or none when there are none.
pub fn (n &PsiElementImpl) last_child() ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}
	child := n.node.last_child()?
	return create_element(child, n.containing_file)
}

// last_child_or_stub returns the last child, taken from the stub when the
// element is stub-based.
pub fn (n &PsiElementImpl) last_child_or_stub() ?PsiElement {
	if stub := n.get_stub() {
		child := stub.last_child()?
		return child.get_psi()
	}

	if !n.is_valid_tree() {
		return none
	}

	child := n.node.last_child()?
	return create_element(child, n.containing_file)
}

// next_sibling returns the element's next sibling, or none at the end of the
// parent's children.
pub fn (n &PsiElementImpl) next_sibling() ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	sibling := n.node.next_sibling()?
	return create_element(sibling, n.containing_file)
}

// next_sibling_or_stub returns the next sibling, taken from the stub when the
// element is stub-based.
pub fn (n &PsiElementImpl) next_sibling_or_stub() ?PsiElement {
	if stub := n.get_stub() {
		sibling := stub.next_sibling()?
		if is_valid_stub(sibling) {
			return sibling.get_psi()
		}
		return none
	}

	if !n.is_valid_tree() {
		return none
	}

	return n.next_sibling()
}

// prev_sibling returns the element's previous sibling, or none at the start
// of the parent's children.
pub fn (n &PsiElementImpl) prev_sibling() ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	sibling := n.node.prev_sibling()?
	return create_element(sibling, n.containing_file)
}

// prev_sibling_of_type returns the nearest earlier sibling with the given
// type.
pub fn (n &PsiElementImpl) prev_sibling_of_type(typ bindings.NodeType) ?PsiElement {
	mut res := PsiElement(n)
	for {
		res = res.prev_sibling_or_stub()?
		if res.element_type() == typ {
			return res
		}
	}

	return none
}

// prev_sibling_or_stub returns the previous sibling, taken from the stub when
// the element is stub-based.
pub fn (n &PsiElementImpl) prev_sibling_or_stub() ?PsiElement {
	if stub := n.get_stub() {
		sibling := stub.prev_sibling()?
		if is_valid_stub(sibling) {
			return sibling.get_psi()
		}
		return none
	}

	return n.prev_sibling()
}

// find_child_by_type returns the first child element with the given type.
pub fn (n &PsiElementImpl) find_child_by_type(typ bindings.NodeType) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	ast_node := n.node.first_node_by_type(typ)?
	return create_element(ast_node, n.containing_file)
}

// has_child_of_type reports whether any child carries the given type.
pub fn (n &PsiElementImpl) has_child_of_type(typ bindings.NodeType) bool {
	if stub := n.get_stub() {
		return stub.has_child_of_type(node_type_to_stub_type(typ))
	}

	if !n.is_valid_tree() {
		return false
	}

	if _ := n.node.first_node_by_type(typ) {
		return true
	}

	return false
}

// find_child_by_type_or_stub returns the first child with the given type,
// taken from the stub when the element is stub-based.
pub fn (n &PsiElementImpl) find_child_by_type_or_stub(typ bindings.NodeType) ?PsiElement {
	if stub := n.get_stub() {
		child := stub.get_child_by_type(node_type_to_stub_type(typ))?
		return child.get_psi()
	}

	if !n.is_valid_tree() {
		return none
	}

	ast_node := n.node.first_node_by_type(typ)?
	return create_element(ast_node, n.containing_file)
}

// find_child_by_name returns the child the grammar files under a field name.
pub fn (n &PsiElementImpl) find_child_by_name(name string) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	ast_node := n.node.child_by_field_name(name)?
	return create_element(ast_node, n.containing_file)
}

// find_children_by_type returns every child element with the given type.
pub fn (n &PsiElementImpl) find_children_by_type(typ bindings.NodeType) []PsiElement {
	if !n.is_valid_tree() {
		return []
	}

	mut result := []PsiElement{}
	mut child := n.node.first_child() or { return [] }
	for {
		if child.type_name == typ {
			result << create_element(child, n.containing_file)
		}
		child = child.next_sibling() or { break }
	}
	return result
}

// find_children_by_type_or_stub returns every child with the given type,
// taken from the stub when the element is stub-based.
pub fn (n &PsiElementImpl) find_children_by_type_or_stub(typ bindings.NodeType) []PsiElement {
	if stub := n.get_stub() {
		return stub.get_children_by_type(node_type_to_stub_type(typ)).get_psi()
	}

	if !n.is_valid_tree() {
		return []
	}

	mut result := []PsiElement{}
	mut child := n.node.first_child() or { return [] }
	for {
		if child.type_name == typ {
			result << create_element(child, n.containing_file)
		}
		child = child.next_sibling() or { break }
	}
	return result
}

// find_last_child_by_type returns the last child element with the given type.
pub fn (n &PsiElementImpl) find_last_child_by_type(typ bindings.NodeType) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	ast_node := n.node.last_node_by_type(typ)?
	return create_element(ast_node, n.containing_file)
}
