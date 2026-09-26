// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct MapInitExpression {
	PsiElementImpl
}

// key_values returns the keyed elements of the map literal, in source order.
pub fn (n MapInitExpression) key_values() []PsiElement {
	return n.find_children_by_type(.map_keyed_element)
}
