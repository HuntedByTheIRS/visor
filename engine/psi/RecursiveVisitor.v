// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct RecursiveVisitorBase {
}

fn (r &RecursiveVisitorBase) visit_element(element PsiElement) {
	if !r.visit_element_impl(element) {
		return
	}
	mut child := element.first_child() or { return }
	for {
		child.accept(r)
		child = child.next_sibling() or { break }
	}
}

fn (_ &RecursiveVisitorBase) visit_element_impl(_ PsiElement) bool {
	return true
}
