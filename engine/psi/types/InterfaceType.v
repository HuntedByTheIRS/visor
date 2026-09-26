// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct InterfaceType {
	BaseNamedType
}

// new_interface_type creates an interface type for the declaration named name in module_name.
pub fn new_interface_type(name string, module_name string) &InterfaceType {
	return &InterfaceType{
		name:        name
		module_name: module_name
	}
}

// accept offers the interface type to the visitor; it has no inner type to descend into.
pub fn (s &InterfaceType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the interface type unchanged.
pub fn (s &InterfaceType) substitute_generics(name_map map[string]Type) Type {
	return s
}
