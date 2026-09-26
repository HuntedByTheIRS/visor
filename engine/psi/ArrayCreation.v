// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ArrayCreation {
	PsiElementImpl
	is_fixed bool
}

// expressions returns the elements of the array literal.
pub fn (n ArrayCreation) expressions() []PsiElement {
	children := n.children()
	return children.filter(it.element_type() != .unknown)
}
