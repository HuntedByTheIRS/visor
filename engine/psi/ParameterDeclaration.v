// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct ParameterDeclaration {
	PsiElementImpl
}

fn (p &ParameterDeclaration) stub() {}

// is_public reports whether the element is visible outside its module; always true for a parameter.
pub fn (_ &ParameterDeclaration) is_public() bool {
	return true
}

// get_type returns the declared type of the parameter, or the unknown type when it cannot be inferred.
pub fn (p &ParameterDeclaration) get_type() types.Type {
	return infer_type(PsiElement(p))
}

// identifier returns the name element of the parameter.
pub fn (p &ParameterDeclaration) identifier() ?PsiElement {
	return p.find_child_by_type(.identifier)
}

// identifier_text_range returns the span of the parameter name, taken from the stub when one exists.
pub fn (p &ParameterDeclaration) identifier_text_range() TextRange {
	if stub := p.get_stub() {
		return stub.identifier_text_range
	}

	identifier := p.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the parameter name.
pub fn (p &ParameterDeclaration) name() string {
	if stub := p.get_stub() {
		return stub.name
	}

	identifier := p.identifier() or { return '' }
	return identifier.get_text()
}

// mutability_modifiers returns the mutability modifiers of the parameter, or none.
pub fn (p &ParameterDeclaration) mutability_modifiers() ?&MutabilityModifiers {
	modifiers := p.find_child_by_type_or_stub(.mutability_modifiers)?
	if modifiers is MutabilityModifiers {
		return modifiers
	}
	return none
}

// is_mutable reports whether the parameter is declared with mut.
pub fn (p &ParameterDeclaration) is_mutable() bool {
	mods := p.mutability_modifiers() or { return false }
	return mods.is_mutable()
}
