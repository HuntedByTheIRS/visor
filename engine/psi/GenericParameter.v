// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

@[heap]
pub struct GenericParameter {
	PsiElementImpl
}

// identifier_text_range returns the span of the parameter name, taken from the stub when one exists.
pub fn (n &GenericParameter) identifier_text_range() TextRange {
	if stub := n.get_stub() {
		return stub.identifier_text_range
	}

	identifier := n.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// identifier returns the name element of the parameter.
pub fn (n &GenericParameter) identifier() ?PsiElement {
	return n.find_child_by_type(.identifier)
}

// name returns the parameter name.
pub fn (n &GenericParameter) name() string {
	if stub := n.get_stub() {
		return stub.name
	}

	identifier := n.identifier() or { return '' }
	return identifier.get_text()
}

// is_public reports whether the element is visible outside its module.
pub fn (_ &GenericParameter) is_public() bool {
	return true
}

fn (_ &GenericParameter) stub() {}
