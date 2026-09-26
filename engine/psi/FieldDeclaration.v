// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct FieldDeclaration {
	PsiElementImpl
}

// is_embedded_definition reports whether the field was written as an embedded definition.
pub fn (f &FieldDeclaration) is_embedded_definition() bool {
	return f.has_child_of_type(.embedded_definition)
}

// is_public reports whether the field is visible outside its module. Fields of an
// interface are always public.
pub fn (f &FieldDeclaration) is_public() bool {
	if owner := f.owner() {
		if owner is InterfaceDeclaration {
			return true // all interface fields are public by default
		}
	}

	_, is_pub := f.is_mutable_public()
	return is_pub
}

// doc_comment returns the field's doc comment text, or an empty string when it has none.
pub fn (f &FieldDeclaration) doc_comment() string {
	if stub := f.get_stub() {
		return stub.comment
	}

	if comment := f.find_child_by_type(.line_comment) {
		return comment.get_text().trim_string_left('//').trim(' \t')
	}

	return extract_doc_comment(f)
}

// identifier returns the field's name element, or none when the field was written
// without one.
pub fn (f &FieldDeclaration) identifier() ?PsiElement {
	return f.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the field's name.
pub fn (f FieldDeclaration) identifier_text_range() TextRange {
	if stub := f.get_stub() {
		return stub.identifier_text_range
	}

	identifier := f.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the field's name.
pub fn (f &FieldDeclaration) name() string {
	if stub := f.get_stub() {
		return stub.name
	}

	identifier := f.identifier() or { return '' }
	return identifier.get_text()
}

// get_type returns the declared type of the field.
pub fn (f &FieldDeclaration) get_type() types.Type {
	return infer_type(PsiElement(f))
}

// owner returns the struct or interface the field is declared in.
pub fn (f &FieldDeclaration) owner() ?PsiElement {
	if struct_ := f.parent_of_type(.struct_declaration) {
		return struct_
	}
	return f.parent_of_type(.interface_declaration)
}

// scope returns the field scope the field sits in, which carries the mut and pub
// of the block it belongs to.
pub fn (f &FieldDeclaration) scope() ?&StructFieldScope {
	element := f.sibling_of_type_backward(.struct_field_scope)?
	if element is StructFieldScope {
		return element
	}
	return none
}

// is_mutable_public reports whether the field's block is declared mut and whether
// it is declared pub.
pub fn (f &FieldDeclaration) is_mutable_public() (bool, bool) {
	scope := f.scope() or { return false, false }
	return scope.is_mutable_public()
}

// stub is the marker method that lets the field be rebuilt from an index stub.
pub fn (_ FieldDeclaration) stub() {}
