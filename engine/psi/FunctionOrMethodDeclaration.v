// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct FunctionOrMethodDeclaration {
	PsiElementImpl
}

// generic_parameters returns the generic parameters declared on the function, or none when it has none.
pub fn (f &FunctionOrMethodDeclaration) generic_parameters() ?&GenericParameters {
	generic_parameters := f.find_child_by_type_or_stub(.generic_parameters)?
	if generic_parameters is GenericParameters {
		return generic_parameters
	}
	return none
}

// is_public reports whether the function carries a pub visibility modifier.
pub fn (f &FunctionOrMethodDeclaration) is_public() bool {
	modifiers := f.visibility_modifiers() or { return false }
	return modifiers.is_public()
}

fn (f &FunctionOrMethodDeclaration) get_type() types.Type {
	signature := f.signature() or { return types.unknown_type }
	return signature.get_type()
}

// identifier returns the name node of the function, or none when the declaration is malformed.
pub fn (f FunctionOrMethodDeclaration) identifier() ?PsiElement {
	return f.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the function name, using the stub when the declaration comes from an index.
pub fn (f FunctionOrMethodDeclaration) identifier_text_range() TextRange {
	if stub := f.get_stub() {
		return stub.identifier_text_range
	}

	identifier := f.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// signature returns the signature node of the function, or none when it cannot be found.
pub fn (f FunctionOrMethodDeclaration) signature() ?&Signature {
	signature := f.find_child_by_type_or_stub(.signature)?
	if signature is Signature {
		return signature
	}
	return none
}

// name returns the function name as written in source, without any receiver prefix.
pub fn (f FunctionOrMethodDeclaration) name() string {
	if stub := f.get_stub() {
		return stub.name
	}

	identifier := f.identifier() or { return '' }
	return identifier.get_text()
}

// doc_comment returns the comment block above the declaration, or an empty string when there is none.
pub fn (f FunctionOrMethodDeclaration) doc_comment() string {
	if stub := f.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(f)
}

// is_method reports whether the declaration has a receiver and is therefore a method.
pub fn (f FunctionOrMethodDeclaration) is_method() bool {
	return f.has_child_of_type(.receiver)
}

// receiver_type returns the type of the receiver, or unknown_type for a plain function.
pub fn (f FunctionOrMethodDeclaration) receiver_type() types.Type {
	receiver := f.receiver() or { return types.unknown_type }
	return receiver.get_type()
}

// receiver returns the receiver declaration, or none for a plain function.
pub fn (f FunctionOrMethodDeclaration) receiver() ?&Receiver {
	element := f.find_child_by_type_or_stub(.receiver)?
	if element is Receiver {
		return element
	}
	return none
}

// visibility_modifiers returns the node holding the modifiers, or none when the function has none.
pub fn (f FunctionOrMethodDeclaration) visibility_modifiers() ?&VisibilityModifiers {
	modifiers := f.find_child_by_type_or_stub(.visibility_modifiers)?
	if modifiers is VisibilityModifiers {
		return modifiers
	}
	return none
}

// owner returns the struct or alias the method belongs to, or none when the receiver type is not a named type.
pub fn (f FunctionOrMethodDeclaration) owner() ?PsiElement {
	receiver := f.receiver()?
	typ := receiver.get_type()
	unwrapped := types.unwrap_generic_instantiation_type(types.unwrap_pointer_type(typ))
	if unwrapped is types.StructType {
		return *find_struct(unwrapped.qualified_name())?
	}
	if unwrapped is types.AliasType {
		return *find_alias(unwrapped.qualified_name())?
	}
	return none
}

// fingerprint identifies the overload by name, parameter count and whether it has a result.
pub fn (f FunctionOrMethodDeclaration) fingerprint() string {
	signature := f.signature() or { return '' }
	count_params := signature.parameters().len
	has_return_type := if _ := signature.result() { true } else { false }
	return '${f.name()}:${count_params}:${has_return_type}'
}

// stub is the marker method of StubBasedPsiElement and has no behaviour of its own.
pub fn (_ FunctionOrMethodDeclaration) stub() {}
