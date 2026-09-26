// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct Range {
	PsiElementImpl
}

// left returns the expression on the left of the range operator.
pub fn (n Range) left() ?PsiElement {
	return n.first_child()
}

// right returns the expression on the right of the range operator.
pub fn (n Range) right() ?PsiElement {
	return n.last_child()
}

// inclusive reports whether the range is written with `...`, which includes its upper bound.
pub fn (n Range) inclusive() bool {
	op := n.operator() or { return false }
	return op.get_text() == '...'
}

// operator returns the element separating the two range bounds.
pub fn (n Range) operator() ?PsiElement {
	left := n.left()?
	return left.next_sibling()
}
