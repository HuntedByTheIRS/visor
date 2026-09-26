// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct BinaryExpression {
	PsiElementImpl
}

// operator returns the operator text of the expression.
pub fn (n BinaryExpression) operator() string {
	operator_element := n.find_child_by_name('operator') or { return '' }
	return operator_element.get_text()
}

// left returns the left operand of the expression, or none.
pub fn (n BinaryExpression) left() ?PsiElement {
	return n.find_child_by_name('left')
}

// right returns the right operand of the expression, or none.
pub fn (n BinaryExpression) right() ?PsiElement {
	return n.find_child_by_name('right')
}
