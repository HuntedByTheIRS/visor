// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct IfExpression {
	PsiElementImpl
}

// var_definition returns the variable bound by `if x := expr`, or none when the condition binds none.
pub fn (n IfExpression) var_definition() ?&VarDefinition {
	decl := n.find_child_by_type(.var_declaration)?
	list := decl.first_child()?
	expr := list.first_child()?
	if expr is VarDefinition {
		return expr
	}
	if expr is MutExpression {
		var := expr.last_child()?
		if var is VarDefinition {
			return var
		}
	}
	return none
}

// block returns the block the condition guards.
pub fn (n IfExpression) block() ?&Block {
	block := n.find_child_by_type(.block)?
	// Spelled as a statement: an if-expression with a `none` branch infers
	// `?Block` instead of the `?&Block` this returns.
	if block is Block {
		return block
	}
	return none
}

// else_branch returns what follows else, or none when the if has no else.
pub fn (n IfExpression) else_branch() ?PsiElement {
	return n.find_child_by_type(.else_branch)?.last_child()
}
