// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub interface PsiElementVisitor {
	visit_element(element PsiElement)
	visit_element_impl(element PsiElement) bool
}

pub interface MutablePsiElementVisitor {
mut:
	visit_element(element PsiElement)
	visit_element_impl(element PsiElement) bool
}
