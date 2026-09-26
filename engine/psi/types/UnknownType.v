// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub const unknown_type = new_unknown_type()

pub struct UnknownType {}

// new_unknown_type creates a new unknown type.
// Use `unknown_type` constant instead.
fn new_unknown_type() &UnknownType {
	return &UnknownType{}
}

fn (_ &UnknownType) name() string {
	return 'unknown'
}

fn (_ &UnknownType) qualified_name() string {
	return 'unknown'
}

fn (_ &UnknownType) readable_name() string {
	return 'unknown'
}

fn (_ &UnknownType) module_name() string {
	return ''
}

// accept offers the type to the visitor; an unknown type has nothing nested inside it to visit further.
pub fn (s &UnknownType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}
}

// substitute_generics returns the type unchanged, since an unknown type carries no generic parameters.
pub fn (s &UnknownType) substitute_generics(name_map map[string]Type) Type {
	return s
}
