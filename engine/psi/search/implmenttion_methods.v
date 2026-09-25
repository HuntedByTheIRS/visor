// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module search

import engine.psi

// implementation_methods returns all methods that implement the given interface method.
pub fn implementation_methods(method psi.InterfaceMethodDeclaration) []psi.PsiElement {
	mut result := []psi.PsiElement{}
	owner := method.owner() or { return [] }
	structs := implementations(owner)

	for struct_ in structs {
		if struct_ is psi.StructDeclaration {
			struct_method := psi.find_method(struct_.get_type(), method.name()) or { continue }
			result << struct_method
		}
	}

	return result
}
