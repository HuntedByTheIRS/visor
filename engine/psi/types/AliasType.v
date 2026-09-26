// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct AliasType {
	BaseNamedType
pub:
	inner Type
}

// new_alias_type builds an alias whose underlying type is inner.
pub fn new_alias_type(name string, module_name string, inner Type) &AliasType {
	return &AliasType{
		name:        name
		module_name: module_name
		inner:       inner
	}
}

// accept passes the alias to the visitor and then walks its inner type.
pub fn (s &AliasType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns an alias with the generics of its inner type replaced.
pub fn (s &AliasType) substitute_generics(name_map map[string]Type) Type {
	return new_alias_type(s.name, s.module_name, s.inner.substitute_generics(name_map))
}
