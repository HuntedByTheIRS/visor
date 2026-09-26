// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct MatchExpression {
	PsiElementImpl
}

// expression returns the subject of the match.
pub fn (n MatchExpression) expression() ?PsiElement {
	return n.find_child_by_name('condition')
}

// arms returns the match arms in the order they are written, with the else arm last.
pub fn (n MatchExpression) arms() []PsiElement {
	arms := n.find_child_by_type(.match_arms) or { return [] }
	mut arm_list := arms.find_children_by_type(.match_arm)
	arm_list << arms.find_children_by_type(.match_else_arm_clause)
	return arm_list
}

// else_branch returns the else arm, when the match has one.
pub fn (n MatchExpression) else_branch() ?PsiElement {
	return n.find_child_by_name('else_branch')
}
