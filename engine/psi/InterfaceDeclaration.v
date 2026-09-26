// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct InterfaceDeclaration {
	PsiElementImpl
}

// generic_parameters returns the generic parameters declared on the interface, or none when it has none.
pub fn (s &InterfaceDeclaration) generic_parameters() ?&GenericParameters {
	generic_parameters := s.find_child_by_type_or_stub(.generic_parameters)?
	if generic_parameters is GenericParameters {
		return generic_parameters
	}
	return none
}

// is_public reports whether the interface carries a pub visibility modifier.
pub fn (s &InterfaceDeclaration) is_public() bool {
	modifiers := s.visibility_modifiers() or { return false }
	return modifiers.is_public()
}

// module_name returns the fully qualified name of the module the interface is declared in.
pub fn (s &InterfaceDeclaration) module_name() string {
	file := s.containing_file() or { return '' }
	return stubs_index.get_module_qualified_name(file.path)
}

// get_type returns the interface type built from the declaration name and module.
pub fn (s &InterfaceDeclaration) get_type() types.Type {
	return types.new_interface_type(s.name(), s.module_name())
}

// attributes returns the attributes attached to the interface, or an empty list when it has none.
pub fn (s &InterfaceDeclaration) attributes() []PsiElement {
	attributes := s.find_child_by_type(.attributes) or { return [] }
	if attributes is Attributes {
		return attributes.attributes()
	}

	return []
}

// identifier returns the name node of the interface, or none when the declaration is malformed.
pub fn (s InterfaceDeclaration) identifier() ?PsiElement {
	return s.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the interface name, using the stub when the declaration comes from an index.
pub fn (s InterfaceDeclaration) identifier_text_range() TextRange {
	if stub := s.get_stub() {
		return stub.identifier_text_range
	}

	identifier := s.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the interface name as written in source.
pub fn (s InterfaceDeclaration) name() string {
	if stub := s.get_stub() {
		return stub.name
	}

	identifier := s.identifier() or { return '' }
	return identifier.get_text()
}

// doc_comment returns the comment block above the declaration, or an empty string when there is none.
pub fn (s InterfaceDeclaration) doc_comment() string {
	if stub := s.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(s)
}

// visibility_modifiers returns the node holding the modifiers, or none when the interface has none.
pub fn (s InterfaceDeclaration) visibility_modifiers() ?&VisibilityModifiers {
	modifiers := s.find_child_by_type_or_stub(.visibility_modifiers)?
	if modifiers is VisibilityModifiers {
		return modifiers
	}
	return none
}

// fields returns the interface's own fields followed by the fields of the interfaces it embeds.
pub fn (s InterfaceDeclaration) fields() []PsiElement {
	mut fields := s.own_fields()

	embedded_types := s.embedded_definitions()
		.map(types.unwrap_alias_type(it.get_type()))
		.filter(it is types.InterfaceType)

	for embedded_type in embedded_types {
		if interface_ := find_interface(embedded_type.qualified_name()) {
			fields << interface_.fields()
		}
	}

	return fields
}

// own_fields returns the field declarations written in the interface body, without those inherited from embedded interfaces.
pub fn (s InterfaceDeclaration) own_fields() []PsiElement {
	field_declarations := s.find_children_by_type_or_stub(.struct_field_declaration)
	mut result := []PsiElement{cap: field_declarations.len}
	for field_declaration in field_declarations {
		if first_child := field_declaration.first_child_or_stub() {
			if first_child.element_type() != .embedded_definition {
				result << field_declaration
			}
		}
	}
	return result
}

// embedded_definitions returns the embedded interface definitions of the interface.
pub fn (s InterfaceDeclaration) embedded_definitions() []&EmbeddedDefinition {
	field_declarations := s.find_children_by_type_or_stub(.struct_field_declaration)
	mut result := []&EmbeddedDefinition{cap: field_declarations.len}
	for field_declaration in field_declarations {
		if embedded_definition := field_declaration.find_child_by_type_or_stub(.embedded_definition) {
			if embedded_definition is EmbeddedDefinition {
				result << embedded_definition
			}
		}
	}
	return result
}

// methods returns the method declarations of the interface.
pub fn (s InterfaceDeclaration) methods() []PsiElement {
	return s.find_children_by_type_or_stub(.interface_method_definition)
}

// find_method returns the method with the given name, or none when the interface has no such method.
pub fn (s InterfaceDeclaration) find_method(name string) ?&InterfaceMethodDeclaration {
	methods := s.methods()
	for method in methods {
		if method is InterfaceMethodDeclaration {
			if name == method.name() {
				return method
			}
		}
	}

	return none
}

// stub is the marker method of StubBasedPsiElement and has no behaviour of its own.
pub fn (_ InterfaceDeclaration) stub() {}
