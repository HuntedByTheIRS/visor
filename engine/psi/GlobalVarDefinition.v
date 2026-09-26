// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct GlobalVarDefinition {
	PsiElementImpl
}

fn (_ &GlobalVarDefinition) stub() {}

// is_public reports whether the variable is visible outside its module; globals always are, so this returns true.
pub fn (_ &GlobalVarDefinition) is_public() bool {
	return true
}

// identifier returns the name node of the global, or none when the declaration is malformed.
pub fn (n &GlobalVarDefinition) identifier() ?PsiElement {
	if node := n.find_child_by_name('name') {
		return node
	}
	return n.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the variable name, using the stub when the declaration comes from an index.
pub fn (n &GlobalVarDefinition) identifier_text_range() TextRange {
	if stub := n.get_stub() {
		return stub.identifier_text_range
	}

	identifier := n.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the global variable name as written in source.
pub fn (n &GlobalVarDefinition) name() string {
	if stub := n.get_stub() {
		return stub.name
	}

	identifier := n.identifier() or { return '' }
	return identifier.get_text()
}

// get_type returns the declared type of the global, or unknown_type when it cannot be inferred.
pub fn (n &GlobalVarDefinition) get_type() types.Type {
	return infer_type(PsiElement(n))
}
