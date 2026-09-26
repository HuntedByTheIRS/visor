// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct MutabilityModifiers {
	PsiElementImpl
}

// is_mutable reports whether the modifiers contain a mut.
pub fn (n MutabilityModifiers) is_mutable() bool {
	children := n.children()
	return children.any(it.get_text() == 'mut')
}
