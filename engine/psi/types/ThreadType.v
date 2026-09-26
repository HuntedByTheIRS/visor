// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct ThreadType {
	inner Type
}

// new_thread_type creates a thread type wrapping the given inner type.
pub fn new_thread_type(inner Type) &ThreadType {
	return &ThreadType{
		inner: inner
	}
}

// name returns the type's name, prefixed with thread.
pub fn (s &ThreadType) name() string {
	return 'thread ${s.inner.name()}'
}

// qualified_name returns the inner type's qualified name, prefixed with thread.
pub fn (s &ThreadType) qualified_name() string {
	return 'thread ${s.inner.qualified_name()}'
}

// readable_name returns the inner type's readable name, prefixed with thread.
pub fn (s &ThreadType) readable_name() string {
	return 'thread ${s.inner.readable_name()}'
}

// module_name returns the module the inner type is defined in.
pub fn (s &ThreadType) module_name() string {
	return s.inner.module_name()
}

// accept visits the inner type with the given visitor.
pub fn (s &ThreadType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a thread type wrapping the inner type with its generic parameters substituted.
pub fn (s &ThreadType) substitute_generics(name_map map[string]Type) Type {
	return new_thread_type(s.inner.substitute_generics(name_map))
}
