// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct VarDefinition {
	PsiElementImpl
}

// is_public always returns true: a variable definition never carries a visibility modifier.
pub fn (_ &VarDefinition) is_public() bool {
	return true
}

// identifier returns the name node of the variable, or none when it has no name.
pub fn (n &VarDefinition) identifier() ?PsiElement {
	return n.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the variable's name, or an empty range when it has no name.
pub fn (n &VarDefinition) identifier_text_range() TextRange {
	identifier := n.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the variable's name.
pub fn (n &VarDefinition) name() string {
	identifier := n.identifier() or { return '' }
	return identifier.get_text()
}

// declaration returns the var declaration the definition belongs to, or none when it stands alone.
pub fn (n &VarDefinition) declaration() ?&VarDeclaration {
	if parent := n.parent_nth(2) {
		if parent is VarDeclaration {
			return parent
		}
	}
	if parent := n.parent_nth(3) {
		if parent is VarDeclaration {
			return parent
		}
	}
	return none
}

// get_type infers the type of the variable.
pub fn (n &VarDefinition) get_type() types.Type {
	return infer_type(PsiElement(n))
}

// mutability_modifiers returns the modifiers written on the variable, or none when it is declared plain.
pub fn (n &VarDefinition) mutability_modifiers() ?&MutabilityModifiers {
	if mut_expr := n.parent() {
		if mut_expr.node().type_name == .mutable_expression {
			modifiers := mut_expr.find_child_by_type(.mutability_modifiers)?
			if modifiers is MutabilityModifiers {
				return modifiers
			}
		}
	}

	return none
}

// is_mutable reports whether the variable can be assigned to; a for-loop initializer counts as
// mutable even without mut.
pub fn (n &VarDefinition) is_mutable() bool {
	mods := n.mutability_modifiers() or {
		if first_child := n.first_child() {
			if first_child.text_matches('mut') {
				return true
			}
		}

		if grand := n.parent_nth(4) {
			if grand.element_type() == .for_clause {
				// variable inside for loop initializer is mutable by default
				return true
			}
		}
		return false
	}
	return mods.is_mutable()
}
