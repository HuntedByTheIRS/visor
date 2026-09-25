// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct KeyedElement {
	PsiElementImpl
}

pub fn (n KeyedElement) field() ?&FieldName {
	first_child := n.first_child()?
	if first_child is FieldName {
		return first_child
	}
	return none
}

pub fn (n KeyedElement) value() ?PsiElement {
	return n.last_child()
}
