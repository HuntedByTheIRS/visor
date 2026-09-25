// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub interface ReferenceExpressionBase {
	get_text() string
	text_range() TextRange
	name() string
	qualifier() ?PsiElement
	reference() PsiReference
	resolve() ?PsiElement
}
