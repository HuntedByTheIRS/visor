// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct SelectiveImportList {
	PsiElementImpl
}

// symbols returns the reference expressions named in the selective import.
pub fn (n &SelectiveImportList) symbols() []ReferenceExpression {
	children := n.find_children_by_type_or_stub(.reference_expression)
	mut res := []ReferenceExpression{cap: children.len}
	for child in children {
		if child is ReferenceExpression {
			res << child
		}
	}
	return res
}

fn (n &SelectiveImportList) stub() {}
