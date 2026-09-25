// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct SliceExpression {
	PsiElementImpl
}

pub fn (c SliceExpression) expression() ?PsiElement {
	return c.first_child()
}

pub fn (c SliceExpression) resolve() ?PsiElement {
	expr := if selector_expr := c.find_child_by_type(.selector_expression) {
		selector_expr as ReferenceExpressionBase
	} else if ref_expr := c.find_child_by_type(.reference_expression) {
		ref_expr as ReferenceExpressionBase
	} else {
		return none
	}

	if expr is ReferenceExpressionBase {
		resolved := expr.resolve()?
		return resolved
	}

	return none
}
