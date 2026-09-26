// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct GenericType {
	BaseNamedType
}

// new_generic_type creates the placeholder type standing for a generic
// parameter called name.
pub fn new_generic_type(name string) &GenericType {
	return &GenericType{
		name: name
	}
}

// accept passes the generic type to the visitor. A generic parameter has no
// types below it, so that is the whole traversal.
pub fn (s &GenericType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type name_map binds this parameter to, or
// the parameter itself when it is unbound.
pub fn (s &GenericType) substitute_generics(name_map map[string]Type) Type {
	return name_map[s.name] or { return s }
}
