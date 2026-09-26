// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ImportDeclaration {
	PsiElementImpl
}

// spec returns the import specification of the declaration, if it has one.
pub fn (n &ImportDeclaration) spec() ?&ImportSpec {
	spec := n.find_child_by_type(.import_spec)?
	if spec is ImportSpec {
		return spec
	}
	return none
}

fn (n &ImportDeclaration) stub() {}
