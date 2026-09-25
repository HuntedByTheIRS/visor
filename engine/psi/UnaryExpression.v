// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct UnaryExpression {
	PsiElementImpl
}

pub fn (n UnaryExpression) operator() string {
	operator_element := n.find_child_by_name('operator') or { return '' }
	return operator_element.get_text()
}

pub fn (n UnaryExpression) expression() ?PsiElement {
	return n.find_child_by_name('operand')
}
