// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct FieldName {
	PsiElementImpl
}

// reference_expression returns the reference this field name is built from, or none when it is a plain name.
pub fn (n FieldName) reference_expression() ?&ReferenceExpression {
	first_child := n.first_child()?
	if first_child is ReferenceExpression {
		return first_child
	}
	return none
}
