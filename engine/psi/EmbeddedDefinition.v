// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct EmbeddedDefinition {
	PsiElementImpl
}

// owner returns the struct or interface declaration that embeds this element.
pub fn (n &EmbeddedDefinition) owner() ?PsiElement {
	if struct_ := n.parent_of_type(.struct_declaration) {
		return struct_
	}
	return n.parent_of_type(.interface_declaration)
}

// identifier_text_range returns the source range of the embedded type's name.
pub fn (n &EmbeddedDefinition) identifier_text_range() TextRange {
	if stub := n.get_stub() {
		return stub.identifier_text_range
	}

	identifier := n.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// identifier returns the name element of the embedded type, read from whichever type node holds it.
pub fn (n &EmbeddedDefinition) identifier() ?PsiElement {
	if qualified_type := n.find_child_by_type_or_stub(.qualified_type) {
		return qualified_type.last_child_or_stub()
	}
	if generic_type := n.find_child_by_type_or_stub(.generic_type) {
		return generic_type.first_child_or_stub()
	}
	if ref_expression := n.find_child_by_type_or_stub(.type_reference_expression) {
		return ref_expression.first_child_or_stub()
	}
	return none
}

// name returns the embedded type's name, or an empty string when it cannot be read.
pub fn (n &EmbeddedDefinition) name() string {
	if stub := n.get_stub() {
		return stub.name
	}

	identifier := n.identifier() or { return '' }
	return identifier.get_text()
}

// is_public is always true; an embedded type takes the visibility of the declaration that embeds it.
pub fn (_ &EmbeddedDefinition) is_public() bool {
	return true
}

// get_type returns the inferred type of the embedded type.
pub fn (n &EmbeddedDefinition) get_type() types.Type {
	return infer_type(PsiElement(n))
}

fn (_ &EmbeddedDefinition) stub() {}
