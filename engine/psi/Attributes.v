// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct Attributes {
	PsiElementImpl
}

fn (_ &Attributes) stub() {}

// attributes returns the attribute nodes attached to the element.
pub fn (n Attributes) attributes() []PsiElement {
	return n.find_children_by_type_or_stub(.attribute)
}
