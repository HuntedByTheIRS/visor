// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ValueAttribute {
	PsiElementImpl
}

pub fn (n ValueAttribute) value() string {
	return n.get_text()
}

fn (_ &ValueAttribute) stub() {}
