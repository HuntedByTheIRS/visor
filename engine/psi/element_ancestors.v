// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

// parent returns the element that contains this one, or none at the root.
// A stub-based element answers from its stub's parent.
pub fn (n &PsiElementImpl) parent() ?PsiElement {
	if stub := n.get_stub() {
		if isnil(stub) {
			return none
		}

		parent := stub.parent_stub()?
		if isnil(parent) {
			return none
		}

		if parent.stub_type() == .root {
			return none
		}

		if is_valid_stub(parent) {
			return parent.get_psi()
		}
		return none
	}

	if !n.is_valid_tree() {
		return none
	}

	parent := n.node.parent()?
	return create_element(parent, n.containing_file)
}

// parent_nth walks depth levels up the tree: 0 is the element itself, 1 its
// parent. It returns none before it gets that far.
pub fn (n &PsiElementImpl) parent_nth(depth int) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	parent := n.node.parent_nth(depth)?
	return create_element(parent, n.containing_file)
}

// parent_of_type returns the nearest ancestor with the given node type.
pub fn (n &PsiElementImpl) parent_of_type(typ bindings.NodeType) ?PsiElement {
	mut res := PsiElement(n)
	for {
		res = res.parent()?
		if res.element_type() == typ {
			return res
		}
	}

	return none
}

// parent_of_any_type returns the nearest ancestor whose type is one of types.
pub fn (n &PsiElementImpl) parent_of_any_type(types ...bindings.NodeType) ?PsiElement {
	mut res := PsiElement(n)
	for {
		res = res.parent()?
		element_type := res.element_type()
		if element_type in types {
			return res
		}
	}

	return none
}

// inside reports whether any ancestor of the element has the given type.
pub fn (n &PsiElementImpl) inside(typ bindings.NodeType) bool {
	mut res := PsiElement(n)
	for {
		res = res.parent() or { return false }
		if res.element_type() == typ {
			return true
		}
	}

	return false
}

// is_parent_of reports whether element sits anywhere below the receiver.
// Elements from different stub lists are never related.
pub fn (n &PsiElementImpl) is_parent_of(element PsiElement) bool {
	if stub := n.get_stub() {
		if element_stub := element.get_stub() {
			if stub.stub_list.path != element_stub.stub_list.path {
				return false
			}
		}
	}

	mut parent := element.parent() or { return false }

	for {
		if parent.is_equal(n) {
			return true
		}
		parent = parent.parent() or { break }
	}

	return false
}

// parent_of_type_or_self returns the nearest ancestor with the given type, or
// the element itself when its type already matches.
pub fn (n &PsiElementImpl) parent_of_type_or_self(typ bindings.NodeType) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	if n.node.type_name == typ {
		return create_element(n.node, n.containing_file)
	}
	mut parent := n.parent()?
	if parent.element_type() == typ {
		return parent
	}

	for {
		parent = parent.parent()?
		if parent.element_type() == typ {
			return parent
		}
	}

	return none
}
