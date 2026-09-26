// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct IndexExpression {
	PsiElementImpl
}

fn (c &IndexExpression) get_type() types.Type {
	return infer_type(PsiElement(c))
}

// expression returns the expression being indexed.
pub fn (c IndexExpression) expression() ?PsiElement {
	return c.first_child()
}
