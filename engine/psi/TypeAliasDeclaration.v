// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct TypeAliasDeclaration {
	PsiElementImpl
}

// get_type returns the alias type built from the declaration name, module and aliased type.
pub fn (a &TypeAliasDeclaration) get_type() types.Type {
	types_list := a.types()
	inner_type := if types_list.len > 0 {
		convert_type(types_list[0])
	} else {
		types.Type(types.unknown_type)
	}
	return types.new_alias_type(a.name(), a.module_name(), inner_type)
}

// generic_parameters returns the generic parameters declared on the alias, or none when it has none.
pub fn (a &TypeAliasDeclaration) generic_parameters() ?&GenericParameters {
	generic_parameters := a.find_child_by_type_or_stub(.generic_parameters)?
	if generic_parameters is GenericParameters {
		return generic_parameters
	}
	return none
}

// is_public reports whether the alias carries a pub visibility modifier.
pub fn (a &TypeAliasDeclaration) is_public() bool {
	modifiers := a.visibility_modifiers() or { return false }
	return modifiers.is_public()
}

// module_name returns the fully qualified name of the module the alias is declared in.
pub fn (a &TypeAliasDeclaration) module_name() string {
	file := a.containing_file() or { return '' }
	return stubs_index.get_module_qualified_name(file.path)
}

// doc_comment returns the comment block above the declaration, or an empty string when there is none.
pub fn (a TypeAliasDeclaration) doc_comment() string {
	if stub := a.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(a)
}

// types returns the type expressions the alias stands for.
pub fn (a &TypeAliasDeclaration) types() []PlainType {
	inner_types := a.find_children_by_type_or_stub(.plain_type)
	mut result := []PlainType{cap: inner_types.len}
	for type_ in inner_types {
		if type_ is PlainType {
			result << type_
		}
	}
	return result
}

// identifier returns the name node of the alias, or none when the declaration is malformed.
pub fn (a TypeAliasDeclaration) identifier() ?PsiElement {
	return a.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the alias name, using the stub when the declaration comes from an index.
pub fn (a &TypeAliasDeclaration) identifier_text_range() TextRange {
	if stub := a.get_stub() {
		return stub.identifier_text_range
	}

	identifier := a.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the alias name as written in source.
pub fn (a TypeAliasDeclaration) name() string {
	if stub := a.get_stub() {
		return stub.name
	}

	identifier := a.identifier() or { return '' }
	return identifier.get_text()
}

// visibility_modifiers returns the node holding the modifiers, or none when the alias has none.
pub fn (a TypeAliasDeclaration) visibility_modifiers() ?&VisibilityModifiers {
	modifiers := a.find_child_by_type_or_stub(.visibility_modifiers)?
	if modifiers is VisibilityModifiers {
		return modifiers
	}
	return none
}

fn (_ &TypeAliasDeclaration) stub() {}
