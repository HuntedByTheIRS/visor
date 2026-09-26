// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct KeyedElement {
	PsiElementImpl
}

// field returns the key of a keyed element, if it was written with one.
pub fn (n KeyedElement) field() ?&FieldName {
	first_child := n.first_child()?
	if first_child is FieldName {
		return first_child
	}
	return none
}

// value returns the value the key holds.
pub fn (n KeyedElement) value() ?PsiElement {
	return n.last_child()
}
