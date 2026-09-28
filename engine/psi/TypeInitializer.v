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
//
// Both spellings of a struct literal have to arrive here. `Point{ x: 1 }` parses
// as an element list of keyed elements, and `Point{ 1, 2 }` parses as a short
// element list, so a reader that only looked for the first found nothing for
// the positional form, which is the one that has no names written in it.
pub fn (n &TypeInitializer) element_list() []PsiElement {
	body := n.find_child_by_name('body') or { return [] }
	if list := body.find_child_by_type(.element_list) {
		return list.named_children()
	}
	if short := body.find_child_by_type(.short_element_list) {
		return short.named_children()
	}
	return []
}
