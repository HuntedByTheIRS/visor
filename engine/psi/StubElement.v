// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// StubElement describes the interface of any stub.
pub interface StubElement {
	id() StubId
	name() string
	text() string
	receiver() string
	stub_type() StubType
	text_range() TextRange
	parent_stub() ?&StubElement
	first_child() ?&StubElement
	children_stubs() []StubElement
	get_child_by_type(typ StubType) ?StubElement
	has_child_of_type(typ StubType) bool
	get_children_by_type(typ StubType) []StubElement
	prev_sibling() ?&StubElement
	parent_of_type(typ StubType) ?StubElement
	get_psi() ?PsiElement
}

// get_psi turns each stub in the list into its PSI element, skipping the
// stubs that do not resolve.
pub fn (elements []StubElement) get_psi() []PsiElement {
	mut result := []PsiElement{cap: elements.len}
	for element in elements {
		result << element.get_psi() or { continue }
	}
	return result
}

// is_valid_stub reports whether a stub is usable; for a stub base that
// means its index list is set.
pub fn is_valid_stub(s StubElement) bool {
	if s is StubBase {
		// `&s` because V deprecates handing a struct value to a voidptr
		// parameter; the smartcast below yields a value, not a pointer.
		return !isnil(&s) && !isnil(s.stub_list)
	}
	return !isnil(s)
}
