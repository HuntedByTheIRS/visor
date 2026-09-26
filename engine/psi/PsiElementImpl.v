// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

pub struct PsiElementImpl {
pub:
	node            AstNode // base node from Tree Sitter
	containing_file ?&PsiFile
	// stubs related
	stub_id    StubId = non_stubbed_element
	stubs_list ?&StubList
}

// new_psi_node builds an element over a tree-sitter node, optionally tied to
// the file the node was parsed from.
pub fn new_psi_node(containing_file ?&PsiFile, node AstNode) PsiElementImpl {
	return PsiElementImpl{
		node:            node
		containing_file: containing_file
	}
}

fn new_psi_node_from_stub(id StubId, stubs_list &StubList) PsiElementImpl {
	return PsiElementImpl{
		node:            zero_ast_node()
		containing_file: new_stub_psi_file(stubs_list.path, stubs_list)
		stub_id:         id
		stubs_list:      stubs_list
	}
}

// zero_ast_node is the placeholder node for stub-based elements, which have no
// tree-sitter node behind them. bindings.Node marks its fields @[required] and
// keeps the type factory private, so the node is built through the package's
// own constructor with a null C node; that resolves to NodeType.unknown, which
// is also what element_type() hands back for these elements.
fn zero_ast_node() AstNode {
	return bindings.new_tsnode[bindings.NodeType](bindings.type_factory, C.TSNode{})
}

fn (n &PsiElementImpl) is_valid_tree() bool {
	if n.stub_based() {
		return true
	}
	file := n.containing_file or { return true }
	return !isnil(file.tree)
}

// stub_id returns the element's slot in its stub list, or non_stubbed_element
// when the element is not stub-based.
pub fn (n &PsiElementImpl) stub_id() StubId {
	return n.stub_id
}

// stub_based reports whether the element was built from a stub rather than a
// tree-sitter node.
pub fn (n &PsiElementImpl) stub_based() bool {
	return n.stubs_list != none
}

// get_stub returns the stub backing the element, or none when the element is
// not stub-based.
pub fn (n &PsiElementImpl) get_stub() ?&StubBase {
	list := n.stub_list()?
	return list.get_stub(n.stub_id)
}

// stub_list returns the stub list the element belongs to, or none when it is
// not stub-based.
pub fn (n &PsiElementImpl) stub_list() ?&StubList {
	return n.stubs_list
}

// node returns the tree-sitter node behind the element. A stub-based element
// answers with a zero node.
pub fn (n &PsiElementImpl) node() AstNode {
	return n.node
}

// element_type returns the element's node type. A stub-based element reports
// the type its stub carries, and one with no live tree reports .unknown.
pub fn (n &PsiElementImpl) element_type() bindings.NodeType {
	if stub := n.get_stub() {
		return stub.element_type()
	}

	if !n.is_valid_tree() {
		return .unknown
	}

	return n.node.type_name
}

// containing_file returns the file the element was parsed from. A stub-based
// element answers with a file rebuilt around its stub list.
pub fn (n &PsiElementImpl) containing_file() ?&PsiFile {
	if list := n.stubs_list {
		return new_stub_psi_file(list.path, list)
	}

	return n.containing_file
}

// is_equal reports whether other is the same element. Elements match when
// their type and text range agree and the text under that range is the same.
pub fn (n &PsiElementImpl) is_equal(other PsiElement) bool {
	if n.element_type() != other.element_type() {
		return false
	}

	if n.text_range() != other.text_range() {
		return false
	}

	return n.get_text() == other.get_text()
}

// accept passes the element to the visitor.
pub fn (n &PsiElementImpl) accept(visitor PsiElementVisitor) {
	visitor.visit_element(n)
}

// accept_mut passes the element to a visitor whose own state may change.
pub fn (n &PsiElementImpl) accept_mut(mut visitor MutablePsiElementVisitor) {
	visitor.visit_element(n)
}

// find_element_at returns the deepest element covering offset, counted from
// the start of this element.
pub fn (n &PsiElementImpl) find_element_at(offset u32) ?PsiElement {
	if !n.is_valid_tree() {
		return none
	}

	start_byte := if n.node.type_name == .source_file { u32(0) } else { n.node.start_byte() }
	abs_offset := start_byte + offset
	el := n.node.descendant_for_byte_range(abs_offset, abs_offset)?
	return create_element(el, n.containing_file)
}

// find_reference_at returns the reference covering offset. An identifier at
// the offset is reported as the reference it sits in.
pub fn (n &PsiElementImpl) find_reference_at(offset u32) ?PsiElement {
	element := n.find_element_at(offset)?
	if element is Identifier {
		parent := element.parent()?
		if parent is ReferenceExpressionBase {
			return parent as PsiElement
		}
	}
	if element is ReferenceExpressionBase {
		return element as PsiElement
	}
	return none
}

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

// get_text returns the source text the element covers, or an empty string
// when there is no text to read.
pub fn (n &PsiElementImpl) get_text() string {
	if stub := n.get_stub() {
		return stub.text
	}

	if !n.is_valid_tree() {
		return ''
	}

	if file := n.containing_file() {
		return n.node.text(file.source_text)
	}

	return ''
}

// text_matches reports whether the element's text is value, without building
// the text first.
pub fn (n &PsiElementImpl) text_matches(value string) bool {
	if stub := n.get_stub() {
		return stub.text == value
	}

	if !n.is_valid_tree() {
		return false
	}

	if file := n.containing_file() {
		return n.node.text_matches(file.source_text, value)
	}

	return false
}

// text_range returns where the element starts and ends in the source.
pub fn (n &PsiElementImpl) text_range() TextRange {
	if stub := n.get_stub() {
		return stub.text_range
	}

	if !n.is_valid_tree() {
		return TextRange{}
	}

	return TextRange{
		line:       int(n.node.start_point().row)
		column:     int(n.node.start_point().column)
		end_line:   int(n.node.end_point().row)
		end_column: int(n.node.end_point().column)
	}
}

// text_length returns how many bytes the element's text is. A stub-based
// element reports the width of its recorded range instead.
pub fn (n &PsiElementImpl) text_length() int {
	if stub := n.get_stub() {
		range := stub.text_range
		return range.end_column - range.column
	}

	if !n.is_valid_tree() {
		return 0
	}

	return int(n.node.text_length())
}
