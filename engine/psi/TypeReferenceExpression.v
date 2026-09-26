// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct TypeReferenceExpression {
	PsiElementImpl
}

fn (_ &TypeReferenceExpression) stub() {}

// is_public reports whether the element is visible outside its module.
pub fn (_ TypeReferenceExpression) is_public() bool {
	return true
}

// identifier returns the name element of the reference.
pub fn (r TypeReferenceExpression) identifier() ?PsiElement {
	return r.first_child()
}

// identifier_text_range returns the span of the identifier, taken from the stub when one exists.
pub fn (r &TypeReferenceExpression) identifier_text_range() TextRange {
	if stub := r.get_stub() {
		return stub.identifier_text_range
	}

	identifier := r.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the type name written here.
pub fn (r TypeReferenceExpression) name() string {
	if stub := r.get_stub() {
		return stub.text
	}

	identifier := r.identifier() or { return '' }
	return identifier.get_text()
}

// qualifier returns the left side of a qualified type, or none for an unqualified name.
pub fn (r TypeReferenceExpression) qualifier() ?PsiElement {
	parent := r.parent()?

	if parent is QualifiedType {
		left := parent.left()?
		if left.is_equal(r) {
			return none
		}

		return left
	}

	return none
}

// reference returns the reference this expression resolves through.
pub fn (r TypeReferenceExpression) reference() PsiReference {
	return new_reference(r.containing_file, r, true)
}

// resolve returns the element the reference points at, or none when it cannot be resolved.
pub fn (r TypeReferenceExpression) resolve() ?PsiElement {
	return r.reference().resolve()
}

// get_type returns the resolved type, or the unknown type when resolution fails.
pub fn (r TypeReferenceExpression) get_type() types.Type {
	element := r.resolve() or { return types.unknown_type }

	if element is PsiTypedElement {
		return element.get_type()
	}

	return types.unknown_type
}
