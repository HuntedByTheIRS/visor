// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub interface PsiReference {
	element() PsiElement
	resolve() ?PsiElement
	multi_resolve() []PsiElement
}
