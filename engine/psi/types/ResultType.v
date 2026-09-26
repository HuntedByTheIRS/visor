// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct ResultType {
pub:
	inner    Type
	no_inner bool
}

// new_result_type creates a result type around inner, or a bare result when no_inner is set.
pub fn new_result_type(inner Type, no_inner bool) &ResultType {
	return &ResultType{
		inner:    inner
		no_inner: no_inner
	}
}

// name returns the type as it is written in source, with its leading `!`.
pub fn (s &ResultType) name() string {
	if s.no_inner {
		return '!'
	}
	return '!${s.inner.name()}'
}

// qualified_name is name using the inner type's fully qualified name.
pub fn (s &ResultType) qualified_name() string {
	if s.no_inner {
		return '!'
	}
	return '!${s.inner.qualified_name()}'
}

// readable_name is name using the inner type's readable name.
pub fn (s &ResultType) readable_name() string {
	if s.no_inner {
		return '!'
	}
	return '!${s.inner.readable_name()}'
}

// module_name returns the module of the inner type.
pub fn (s &ResultType) module_name() string {
	return s.inner.module_name()
}

// accept offers the result type to the visitor, then descends into the inner type.
pub fn (s &ResultType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a result type with the generics replaced in its inner type.
pub fn (s &ResultType) substitute_generics(name_map map[string]Type) Type {
	return new_result_type(s.inner.substitute_generics(name_map), s.no_inner)
}
