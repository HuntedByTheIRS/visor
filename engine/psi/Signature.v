// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct Signature {
	PsiElementImpl
}

pub fn (s &Signature) get_type() types.Type {
	return infer_type(PsiElement(s))
}

pub fn (n Signature) parameters() []PsiElement {
	mut parameters := []PsiElement{}
	if list := n.find_child_by_type_or_stub(.parameter_list) {
		parameters << list.find_children_by_type_or_stub(.parameter_declaration)
	}
	if list_type := n.find_child_by_type_or_stub(.type_parameter_list) {
		parameters << list_type.find_children_by_type_or_stub(.type_parameter_declaration)
	}
	return parameters
}

pub fn (n Signature) result() ?PsiElement {
	last := n.last_child_or_stub()?
	if last is PlainType {
		return last
	}
	return none
}

fn (_ &Signature) stub() {}
