// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module search

import engine.psi

// super_methods returns interface methods that are implemented by the struct of given method.
pub fn super_methods(method psi.FunctionOrMethodDeclaration) []psi.PsiElement {
	mut result := []psi.PsiElement{}

	method_name := method.name()
	owner := method.owner() or { return [] }
	if owner is psi.StructDeclaration {
		super_interfaces := supers(owner)
		for super_interface in super_interfaces {
			if super_interface is psi.InterfaceDeclaration {
				if iface_method := super_interface.find_method(method_name) {
					result << iface_method
				}
			}
		}
	}

	return result
}
