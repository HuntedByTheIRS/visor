// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct EnumType {
	BaseNamedType
}

// new_enum_type returns an enum type with the given name in the given module.
pub fn new_enum_type(name string, module_name string) &EnumType {
	return &EnumType{
		name:        name
		module_name: module_name
	}
}

// accept hands the type to the visitor; an enum has nothing below it to walk.
pub fn (s &EnumType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type unchanged: an enum has no generics to replace.
pub fn (s &EnumType) substitute_generics(_ map[string]Type) Type {
	return s
}
