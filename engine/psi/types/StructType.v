// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub const string_type = new_struct_type('string', 'builtin')
pub const builtin_array_type = new_struct_type('array', 'builtin')
pub const builtin_map_type = new_struct_type('map', 'builtin')
pub const array_init_type = new_struct_type('ArrayInit', 'stubs')
pub const chan_init_type = new_struct_type('ChanInit', 'stubs')
pub const flag_enum_type = new_enum_type('FlagEnum', 'stubs')
pub const any_type = new_alias_type('Any', 'stubs', unknown_type)

pub struct StructType {
	BaseNamedType
}

// new_struct_type creates a struct type with the given name and module.
pub fn new_struct_type(name string, module_name string) &StructType {
	return &StructType{
		name:        name
		module_name: module_name
	}
}

// accept lets the visitor enter this type; a struct type has no children to visit.
pub fn (s &StructType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type unchanged; a struct type carries no generic parameters of its own.
pub fn (s &StructType) substitute_generics(name_map map[string]Type) Type {
	return s
}
