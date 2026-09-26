// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct ArrayType {
pub:
	inner Type
}

// new_array_type returns an array type whose elements have the given inner type.
pub fn new_array_type(inner Type) &ArrayType {
	return &ArrayType{
		inner: inner
	}
}

// name returns the array type as written in source, such as `[]string`.
pub fn (s &ArrayType) name() string {
	return '[]${s.inner.name()}'
}

// qualified_name returns the array type with the element type fully qualified.
pub fn (s &ArrayType) qualified_name() string {
	return '[]${s.inner.qualified_name()}'
}

// readable_name returns the array type with the element type named without its module, for messages shown to a user.
pub fn (s &ArrayType) readable_name() string {
	return '[]${s.inner.readable_name()}'
}

// module_name returns the module of the element type, since an array type has no module of its own.
pub fn (s &ArrayType) module_name() string {
	return s.inner.module_name()
}

// accept lets the visitor enter this type and then the element type.
pub fn (s &ArrayType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a new array type with the generic parameters replaced according to name_map.
pub fn (s &ArrayType) substitute_generics(name_map map[string]Type) Type {
	return new_array_type(s.inner.substitute_generics(name_map))
}
