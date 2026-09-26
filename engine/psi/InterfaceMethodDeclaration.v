// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct InterfaceMethodDeclaration {
	PsiElementImpl
}

// is_public is always true, since methods declared in an interface are public.
pub fn (_ InterfaceMethodDeclaration) is_public() bool {
	return true
}

// identifier returns the method's name identifier, if the declaration has one.
pub fn (m InterfaceMethodDeclaration) identifier() ?PsiElement {
	return m.find_child_by_type(.identifier)
}

// identifier_text_range returns the source range of the method's name.
pub fn (m InterfaceMethodDeclaration) identifier_text_range() TextRange {
	if stub := m.get_stub() {
		return stub.identifier_text_range
	}

	identifier := m.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// signature returns the method's signature, if it has one.
pub fn (m InterfaceMethodDeclaration) signature() ?&Signature {
	signature := m.find_child_by_type_or_stub(.signature)?
	if signature is Signature {
		return signature
	}
	return none
}

// name returns the method's name, or an empty string when it cannot be read.
pub fn (m InterfaceMethodDeclaration) name() string {
	if stub := m.get_stub() {
		return stub.name
	}

	identifier := m.identifier() or { return '' }
	return identifier.get_text()
}

// owner returns the interface the method is declared in, if any.
pub fn (m &InterfaceMethodDeclaration) owner() ?&InterfaceDeclaration {
	parent := m.parent_of_type(.interface_declaration)?
	if parent is InterfaceDeclaration {
		return parent
	}
	return none
}

// scope returns the pub/mut access section the method is declared under, if it has one.
pub fn (m &InterfaceMethodDeclaration) scope() ?&StructFieldScope {
	element := m.sibling_of_type_backward(.struct_field_scope)?
	if element is StructFieldScope {
		return element
	}
	return none
}

// doc_comment returns the documentation comment written above the method.
pub fn (m InterfaceMethodDeclaration) doc_comment() string {
	if stub := m.get_stub() {
		return stub.comment
	}
	return extract_doc_comment(m)
}

// fingerprint identifies the method's signature by name, parameter count and whether it has a result.
pub fn (m InterfaceMethodDeclaration) fingerprint() string {
	signature := m.signature() or { return '' }
	count_params := signature.parameters().len
	has_return_type := if _ := signature.result() { true } else { false }
	return '${m.name()}:${count_params}:${has_return_type}'
}

// stub is a marker method that makes InterfaceMethodDeclaration a StubBasedPsiElement.
pub fn (_ InterfaceMethodDeclaration) stub() {}
