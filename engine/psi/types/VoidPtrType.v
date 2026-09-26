// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub const voidptr_type = new_voidptr_type()

pub struct VoidPtrType {}

fn new_voidptr_type() &VoidPtrType {
	return &VoidPtrType{}
}

fn (_ &VoidPtrType) name() string {
	return 'voidptr'
}

fn (_ &VoidPtrType) qualified_name() string {
	return 'voidptr'
}

fn (_ &VoidPtrType) readable_name() string {
	return 'voidptr'
}

fn (_ &VoidPtrType) module_name() string {
	return ''
}

// accept offers the type to the visitor; voidptr has nothing nested inside it to visit further.
pub fn (s &VoidPtrType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type unchanged, since voidptr carries no generic parameters.
pub fn (s &VoidPtrType) substitute_generics(name_map map[string]Type) Type {
	return s
}
