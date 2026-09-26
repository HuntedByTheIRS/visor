// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct StructFieldScope {
	PsiElementImpl
}

// is_mutable_public reports whether the field block is declared mut and whether it is declared pub.
pub fn (n StructFieldScope) is_mutable_public() (bool, bool) {
	text := n.get_text()
	return text.contains('mut'), text.contains('pub')
}

fn (_ &StructFieldScope) stub() {}
