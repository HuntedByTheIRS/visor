// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct PrimitiveType {
pub:
	name string
}

// new_primitive_type returns a primitive type with the given name.
pub fn new_primitive_type(name string) &PrimitiveType {
	return &PrimitiveType{
		name: name
	}
}

fn (s &PrimitiveType) name() string {
	return s.name
}

fn (s &PrimitiveType) qualified_name() string {
	return s.name
}

fn (s &PrimitiveType) readable_name() string {
	return s.name
}

// module_name returns `builtin`, since primitive types are declared there.
pub fn (s &PrimitiveType) module_name() string {
	return 'builtin'
}

// is_primitive_type reports whether typ names one of the builtin primitive types.
pub fn is_primitive_type(typ string) bool {
	return typ in ['i8', 'i16', 'i32', 'int', 'i64', 'byte', 'u8', 'u16', 'u32', 'u64', 'f32',
		'f64', 'char', 'bool', 'rune', 'usize', 'isize']
}

// accept lets the visitor enter this type; a primitive type has no element type to visit.
pub fn (s &PrimitiveType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type unchanged, since a primitive type has no generic parameters.
pub fn (s &PrimitiveType) substitute_generics(name_map map[string]Type) Type {
	return s
}
