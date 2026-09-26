// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct MapType {
	BaseType
pub:
	key   Type
	value Type
}

// new_map_type returns a map type with the given key and value types.
pub fn new_map_type(module_name string, key Type, value Type) &MapType {
	return &MapType{
		key:         key
		value:       value
		module_name: module_name
	}
}

// name returns the name of the map type.
pub fn (s &MapType) name() string {
	return 'map[${s.key.name()}]${s.value.name()}'
}

// qualified_name returns the map type with its value type qualified.
pub fn (s &MapType) qualified_name() string {
	return 'map[${s.key.name()}]${s.value.qualified_name()}'
}

// readable_name returns the map type as it is written in the source.
pub fn (s &MapType) readable_name() string {
	return 'map[${s.key.name()}]${s.value.readable_name()}'
}

// accept passes the type and then its key and value types to the visitor.
pub fn (s &MapType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.key.accept(mut visitor)
	s.value.accept(mut visitor)
}

// substitute_generics returns a map type with the generic parameters replaced.
pub fn (s &MapType) substitute_generics(name_map map[string]Type) Type {
	return new_map_type(s.module_name, s.key.substitute_generics(name_map),
		s.value.substitute_generics(name_map))
}
