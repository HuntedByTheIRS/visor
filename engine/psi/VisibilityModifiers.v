// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct VisibilityModifiers {
	PsiElementImpl
}

pub fn (n VisibilityModifiers) is_public() bool {
	return n.get_text() == 'pub'
}

fn (n &VisibilityModifiers) stub() {}
