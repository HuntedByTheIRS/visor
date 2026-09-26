// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct ReferenceExpression {
	PsiElementImpl
}

// is_public reports whether the element is visible outside its module; always true for a reference.
pub fn (r &ReferenceExpression) is_public() bool {
	return true
}

// identifier returns the name element of the reference.
pub fn (r ReferenceExpression) identifier() ?PsiElement {
	return r.first_child()
}

// identifier_text_range returns the span of the identifier, taken from the stub when one exists.
pub fn (r &ReferenceExpression) identifier_text_range() TextRange {
	if stub := r.get_stub() {
		return stub.identifier_text_range
	}

	identifier := r.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the referenced name.
pub fn (r &ReferenceExpression) name() string {
	if stub := r.get_stub() {
		return stub.text
	}

	identifier := r.identifier() or { return '' }
	return identifier.get_text()
}

// qualifier returns the expression the reference is selected from, or none when it is not part of a selector.
pub fn (r ReferenceExpression) qualifier() ?PsiElement {
	parent := r.parent()?

	if parent is SelectorExpression {
		left := parent.left()?
		if left.is_equal(r) {
			return none
		}

		return left
	}

	return none
}

// reference returns the reference this expression resolves through; an attribute value gets an attribute reference.
pub fn (r ReferenceExpression) reference() PsiReference {
	if parent := r.parent() {
		if parent is ValueAttribute {
			return new_attribute_reference(r.containing_file(), r)
		}
	}

	return new_reference(r.containing_file(), r, false)
}

// resolve returns the element the reference points at, or none when it cannot be resolved.
pub fn (r ReferenceExpression) resolve() ?PsiElement {
	return r.reference().resolve()
}

// get_type returns the inferred type of the reference, or the unknown type when inference fails.
pub fn (r ReferenceExpression) get_type() types.Type {
	return infer_type(PsiElement(r))
}
