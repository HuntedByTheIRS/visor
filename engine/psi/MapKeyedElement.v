// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct MapKeyedElement {
	PsiElementImpl
}

// key returns the key expression.
pub fn (n MapKeyedElement) key() ?PsiElement {
	return n.first_child()
}

// value returns the value expression.
pub fn (n MapKeyedElement) value() ?PsiElement {
	return n.last_child()
}
