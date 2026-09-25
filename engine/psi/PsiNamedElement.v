// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

pub interface PsiNamedElement {
	parent_of_type(typ bindings.NodeType) ?PsiElement
	identifier_text_range() TextRange
	identifier() ?PsiElement
	name() string
	is_public() bool
}
