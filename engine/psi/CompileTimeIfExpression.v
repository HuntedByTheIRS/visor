// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct CompileTimeIfExpression {
	PsiElementImpl
}

// block returns the branch taken when the compile time condition holds, or none when it cannot be found.
pub fn (n CompileTimeIfExpression) block() ?&Block {
	block := n.find_child_by_type(.block)?
	if block is Block {
		return block
	}
	return none
}

// else_branch returns the last child of the else branch, or none when there is no else branch.
pub fn (n CompileTimeIfExpression) else_branch() ?PsiElement {
	return n.find_child_by_type(.else_branch)?.last_child()
}
