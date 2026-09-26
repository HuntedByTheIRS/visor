// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ForStatement {
	PsiElementImpl
}

// var_definitions returns the variables a for statement binds, from a range clause or
// from a C-style for clause.
pub fn (n ForStatement) var_definitions() []PsiElement {
	if range_clause := n.find_child_by_type(.range_clause) {
		var_definition_list := range_clause.find_child_by_type(.var_definition_list) or {
			return []
		}
		return var_definition_list.find_children_by_type(.var_definition)
	}

	if for_clause := n.find_child_by_type(.for_clause) {
		initializer := for_clause.first_child() or { return [] }
		if initializer.element_type() == .simple_statement {
			decl := initializer.first_child() or { return [] }
			list := decl.first_child() or { return [] }
			definition := list.first_child() or { return [] }
			return [definition]
		}
	}

	return []
}
