// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct InterfaceType {
	BaseNamedType
}

pub fn new_interface_type(name string, module_name string) &InterfaceType {
	return &InterfaceType{
		name:        name
		module_name: module_name
	}
}

pub fn (s &InterfaceType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

pub fn (s &InterfaceType) substitute_generics(name_map map[string]Type) Type {
	return s
}
