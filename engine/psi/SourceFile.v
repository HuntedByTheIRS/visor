// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct SourceFile {
	PsiElementImpl
}

// process_declarations offers the file's variable declarations to the processor, stopping at last_parent or when the processor returns false.
pub fn (b SourceFile) process_declarations(mut processor PsiScopeProcessor, last_parent PsiElement) bool {
	statements := b.find_children_by_type(.simple_statement)
	for statement in statements {
		if statement.is_equal(last_parent) {
			return true
		}

		first_child := statement.first_child() or { continue }

		if first_child is VarDeclaration {
			for var in first_child.vars() {
				if !processor.execute(var) {
					return false
				}
			}
		}
	}
	return true
}
