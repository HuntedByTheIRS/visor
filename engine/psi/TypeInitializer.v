// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct TypeInitializer {
	PsiElementImpl
}

// get_type returns the type being initialized, or unknown_type when it cannot be inferred.
pub fn (n &TypeInitializer) get_type() types.Type {
	return infer_type(PsiElement(n))
}

// element_list returns the initialized fields or elements in source order.
pub fn (n &TypeInitializer) element_list() []PsiElement {
	body := n.find_child_by_name('body') or { return [] }
	element_list := body.find_child_by_type(.element_list) or { return [] }
	return element_list.named_children()
}
