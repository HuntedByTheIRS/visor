// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct VarDeclaration {
	PsiElementImpl
}

// The filter and map that upstream chained here lose the element type: the
// mapped array no longer answers is_equal. The loop builds the same list and
// keeps the type.
fn (v VarDeclaration) index_of(def VarDefinition) int {
	first_child := v.first_child() or { return -1 }
	mut definitions := []PsiElement{}
	for child in first_child.children() {
		if child is VarDefinition {
			definitions << child
		} else if child is MutExpression {
			last := child.last_child() or { PsiElement(child) }
			definitions << last
		}
	}

	for i, definition in definitions {
		if definition.is_equal(def) {
			return i
		}
	}
	return -1
}

fn (v VarDeclaration) initializer_of(def VarDefinition) ?PsiElement {
	index := v.index_of(def)
	if index == -1 {
		return none
	}

	expressions := v.expressions()
	if expressions.len == 1 && expressions.first() is CallExpression {
		return expressions.first()
	}

	if index >= expressions.len {
		return none
	}

	return expressions[index]
}

// vars returns the variable definitions declared here, including those wrapped in a mut expression.
pub fn (v VarDeclaration) vars() []PsiElement {
	first_child := v.first_child() or { return [] }
	mut vars := []PsiElement{}
	for child in first_child.children() {
		if child is VarDefinition {
			vars << child
		} else if child is MutExpression {
			vars << (child.last_child() or { PsiElement(child) })
		}
	}
	return vars
}

fn (v VarDeclaration) expressions() []PsiElement {
	last_child := v.last_child() or { return [] }
	return last_child.children()
}
