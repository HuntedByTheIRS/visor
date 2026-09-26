// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct FunctionLiteral {
	PsiElementImpl
}

// signature returns the literal's signature, or none when it has none.
pub fn (f FunctionLiteral) signature() ?&Signature {
	signature := f.find_child_by_type_or_stub(.signature)?
	if signature is Signature {
		return signature
	}
	return none
}
