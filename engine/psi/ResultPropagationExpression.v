// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct ResultPropagationExpression {
	PsiElementImpl
}

fn (c &ResultPropagationExpression) get_type() types.Type {
	return infer_type(PsiElement(c))
}

pub fn (c ResultPropagationExpression) expression() ?PsiElement {
	return c.first_child()
}
