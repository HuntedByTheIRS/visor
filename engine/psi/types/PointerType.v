// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct PointerType {
pub:
	inner Type
}

// new_pointer_type creates a pointer type aimed at inner.
pub fn new_pointer_type(inner Type) &PointerType {
	return &PointerType{
		inner: inner
	}
}

// name returns the pointer type's name, the inner name with a & in front.
pub fn (s &PointerType) name() string {
	return '&${s.inner.name()}'
}

// qualified_name returns the fully qualified inner name with a & in front.
pub fn (s &PointerType) qualified_name() string {
	return '&${s.inner.qualified_name()}'
}

// readable_name returns the inner name a reader would write, with a & in
// front.
pub fn (s &PointerType) readable_name() string {
	return '&${s.inner.readable_name()}'
}

// module_name returns the module the pointed-at type lives in.
pub fn (s &PointerType) module_name() string {
	return s.inner.module_name()
}

// accept passes the pointer type to the visitor, then descends into the inner
// type.
pub fn (s &PointerType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a pointer to the inner type with name_map
// applied.
pub fn (s &PointerType) substitute_generics(name_map map[string]Type) Type {
	return new_pointer_type(s.inner.substitute_generics(name_map))
}
