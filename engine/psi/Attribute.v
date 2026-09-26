// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct Attribute {
	PsiElementImpl
}

fn (_ &Attribute) stub() {}

// expressions returns the attribute expressions of this attribute, from its stub when it has one.
pub fn (n Attribute) expressions() []PsiElement {
	if stub := n.get_stub() {
		return stub.get_children_by_type(.attribute_expression).get_psi()
	}

	return n.find_children_by_type(.attribute_expression)
}

// keys returns the value of each attribute expression, dropping the ones that carry no value.
pub fn (n Attribute) keys() []string {
	expressions := n.expressions()
	if expressions.len == 0 {
		return []
	}

	return expressions.map(fn (expr PsiElement) string {
		if expr is AttributeExpression {
			return expr.value()
		}

		return ''
	}).filter(it != '')
}
