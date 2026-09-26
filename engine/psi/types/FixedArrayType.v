// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct FixedArrayType {
pub:
	inner Type
	size  int
}

// new_fixed_array_type returns a fixed array type of the given size whose elements have the given inner type.
pub fn new_fixed_array_type(inner Type, size int) &FixedArrayType {
	return &FixedArrayType{
		inner: inner
		size:  size
	}
}

// name returns the fixed array type as written in source, such as `[4]int`.
pub fn (s &FixedArrayType) name() string {
	return '[${s.size}]${s.inner.name()}'
}

// qualified_name returns the fixed array type with the element type fully qualified.
pub fn (s &FixedArrayType) qualified_name() string {
	return '[${s.size}]${s.inner.qualified_name()}'
}

// readable_name returns the fixed array type with the element type named without its module, for messages shown to a user.
pub fn (s &FixedArrayType) readable_name() string {
	return '[${s.size}]${s.inner.readable_name()}'
}

// module_name returns the module of the element type, since a fixed array type has no module of its own.
pub fn (s &FixedArrayType) module_name() string {
	return s.inner.module_name()
}

// accept lets the visitor enter this type and then the element type.
pub fn (s &FixedArrayType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a new fixed array type with the generic parameters replaced according to name_map.
pub fn (s &FixedArrayType) substitute_generics(name_map map[string]Type) Type {
	return new_fixed_array_type(s.inner.substitute_generics(name_map), s.size)
}
