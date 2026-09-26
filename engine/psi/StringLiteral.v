// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct StringLiteral {
	PsiElementImpl
}

// content returns the literal's text with the surrounding quotes removed.
pub fn (n StringLiteral) content() string {
	text := n.get_text()
	return text[1..text.len - 1]
}
