// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct StaticMethodDeclaration {
	PsiElementImpl
}

// generic_parameters returns the declaration's type parameter list, or none when it declares none.
pub fn (f &StaticMethodDeclaration) generic_parameters() ?&GenericParameters {
	generic_parameters := f.find_child_by_type_or_stub(.generic_parameters)?
	if generic_parameters is GenericParameters {
		return generic_parameters
	}
	return none
}

// is_public reports whether the declaration carries a public visibility modifier.
pub fn (f &StaticMethodDeclaration) is_public() bool {
	modifiers := f.visibility_modifiers() or { return false }
	return modifiers.is_public()
}

fn (f &StaticMethodDeclaration) get_type() types.Type {
	signature := f.signature() or { return types.unknown_type }
	return signature.get_type()
}

// identifier returns the node holding the method's name, or none when the declaration has no parsed tree.
pub fn (f StaticMethodDeclaration) identifier() ?PsiElement {
	return f.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the method's name, taken from the stub when one is attached.
pub fn (f StaticMethodDeclaration) identifier_text_range() TextRange {
	if stub := f.get_stub() {
		return stub.identifier_text_range
	}

	identifier := f.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// signature returns the declaration's parameters and result, or none when it has none.
pub fn (f StaticMethodDeclaration) signature() ?&Signature {
	signature := f.find_child_by_type_or_stub(.signature)?
	if signature is Signature {
		return signature
	}
	return none
}

// name returns the method's name, taken from the stub when one is attached.
pub fn (f StaticMethodDeclaration) name() string {
	if stub := f.get_stub() {
		return stub.name
	}

	identifier := f.identifier() or { return '' }
	return identifier.get_text()
}

// doc_comment returns the comment written above the declaration, or an empty string when it has none.
pub fn (f StaticMethodDeclaration) doc_comment() string {
	if stub := f.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(f)
}

// receiver_type returns the type of the method's receiver, or the unknown type when it cannot be resolved.
pub fn (f StaticMethodDeclaration) receiver_type() types.Type {
	receiver := f.receiver() or { return types.unknown_type }
	return receiver.get_type()
}

// receiver returns the declaration's static receiver, or none when it has none.
pub fn (f StaticMethodDeclaration) receiver() ?&StaticReceiver {
	element := f.find_child_by_type_or_stub(.static_receiver)?
	if element is StaticReceiver {
		return element
	}
	return none
}

// visibility_modifiers returns the declaration's visibility modifiers, or none when it has none.
pub fn (f StaticMethodDeclaration) visibility_modifiers() ?&VisibilityModifiers {
	modifiers := f.find_child_by_type_or_stub(.visibility_modifiers)?
	if modifiers is VisibilityModifiers {
		return modifiers
	}
	return none
}

// owner returns the interface, struct or alias the receiver type names, or none when it is none of them.
pub fn (f StaticMethodDeclaration) owner() ?PsiElement {
	receiver := f.receiver()?
	typ := receiver.get_type()
	unwrapped := types.unwrap_generic_instantiation_type(types.unwrap_pointer_type(typ))
	if unwrapped is types.InterfaceType {
		return *find_interface(unwrapped.qualified_name())?
	}
	if unwrapped is types.StructType {
		return *find_struct(unwrapped.qualified_name())?
	}
	if unwrapped is types.AliasType {
		return *find_alias(unwrapped.qualified_name())?
	}
	return none
}

// fingerprint returns a string that changes when the method's name, parameter count or result changes.
pub fn (f StaticMethodDeclaration) fingerprint() string {
	signature := f.signature() or { return '' }
	count_params := signature.parameters().len
	has_return_type := if _ := signature.result() { true } else { false }
	return '${f.name()}:${count_params}:${has_return_type}'
}

// stub is a marker method that makes the declaration a StubBasedPsiElement, so it can be built from stubs too.
pub fn (_ StaticMethodDeclaration) stub() {}
