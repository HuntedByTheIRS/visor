// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ConstantDeclaration {
	PsiElementImpl
}

pub fn (n ConstantDeclaration) constants() []PsiElement {
	return n.find_children_by_type(.const_definition)
}
