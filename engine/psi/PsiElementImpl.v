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
