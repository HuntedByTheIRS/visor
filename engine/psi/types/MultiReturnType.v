// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct MultiReturnType {
pub:
	types []Type
}

// new_multi_return_type builds the type of a call returning the given types.
pub fn new_multi_return_type(member_types []Type) &MultiReturnType {
	return &MultiReturnType{
		types: member_types
	}
}

// name returns the member names joined in V's multi-return form.
pub fn (s &MultiReturnType) name() string {
	return '(${s.types.map(it.name()).join(', ')})'
}

// qualified_name returns the members' qualified names joined in multi-return form.
pub fn (s &MultiReturnType) qualified_name() string {
	return '(${s.types.map(it.qualified_name()).join(', ')})'
}

// readable_name returns the members' readable names joined in multi-return form.
pub fn (s &MultiReturnType) readable_name() string {
	return '(${s.types.map(it.readable_name()).join(', ')})'
}

// module_name returns an empty string, since a multi-return type has no module of its own.
pub fn (s &MultiReturnType) module_name() string {
	return ''
}

// accept passes the type to the visitor and then walks each member type.
pub fn (s &MultiReturnType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	for type_ in s.types {
		type_.accept(mut visitor)
	}
}

// substitute_generics returns a multi-return with each member's generic parameters replaced.
pub fn (s &MultiReturnType) substitute_generics(name_map map[string]Type) Type {
	return new_multi_return_type(s.types.map(it.substitute_generics(name_map)))
}
