// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct EnumDeclaration {
	PsiElementImpl
}

// is_public reports whether the enum is declared public.
pub fn (e &EnumDeclaration) is_public() bool {
	modifiers := e.visibility_modifiers() or { return false }
	return modifiers.is_public()
}

// get_type returns the enum type for this declaration, qualified by its module.
pub fn (e &EnumDeclaration) get_type() types.Type {
	module_fqn := if file := e.containing_file() {
		stubs_index.get_module_qualified_name(file.path)
	} else {
		''
	}
	return types.new_enum_type(e.name(), module_fqn)
}

// identifier returns the enum's name identifier, if the declaration has one.
pub fn (e EnumDeclaration) identifier() ?PsiElement {
	return e.find_child_by_type(.identifier)
}

// identifier_text_range returns the source range of the enum's name.
pub fn (e EnumDeclaration) identifier_text_range() TextRange {
	if stub := e.get_stub() {
		return stub.identifier_text_range
	}

	identifier := e.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the enum's name, or an empty string when it cannot be read.
pub fn (e EnumDeclaration) name() string {
	if stub := e.get_stub() {
		return stub.name
	}

	identifier := e.identifier() or { return '' }
	return identifier.get_text()
}

// doc_comment returns the documentation comment written above the enum.
pub fn (e EnumDeclaration) doc_comment() string {
	if stub := e.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(e)
}

// visibility_modifiers returns the enum's visibility modifiers, if it has any.
pub fn (e EnumDeclaration) visibility_modifiers() ?&VisibilityModifiers {
	modifiers := e.find_child_by_type_or_stub(.visibility_modifiers)?
	if modifiers is VisibilityModifiers {
		return modifiers
	}
	return none
}

// fields returns the enum's field definitions.
pub fn (e EnumDeclaration) fields() []PsiElement {
	if stub := e.get_stub() {
		return stub.get_children_by_type(.enum_field_definition).get_psi()
	}

	return e.find_children_by_type(.enum_field_definition)
}

// attributes returns the attributes attached to the enum.
pub fn (s &EnumDeclaration) attributes() []PsiElement {
	attributes := s.find_child_by_type_or_stub(.attributes) or { return [] }
	if attributes is Attributes {
		return attributes.attributes()
	}

	return []
}

// is_flag reports whether the enum is marked with a flag attribute.
pub fn (e EnumDeclaration) is_flag() bool {
	attributes := e.attributes()

	for attr in attributes {
		if attr is Attribute {
			keys := attr.keys()
			return 'flag' in keys
		}
	}

	return false
}

// stub is a marker method that makes EnumDeclaration a StubBasedPsiElement.
pub fn (_ EnumDeclaration) stub() {}
