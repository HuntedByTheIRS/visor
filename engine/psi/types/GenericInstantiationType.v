// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct GenericInstantiationType {
pub:
	inner          Type
	specialization []Type
}

// new_generic_instantiation_type builds the type of inner specialized with the given
// type arguments.
pub fn new_generic_instantiation_type(inner Type, specialization []Type) &GenericInstantiationType {
	return &GenericInstantiationType{
		inner:          inner
		specialization: specialization
	}
}

// name renders the instantiation as inner[arg, ...].
pub fn (s &GenericInstantiationType) name() string {
	return '${s.inner.name()}[${s.specialization.map(it.name()).join(', ')}]'
}

// qualified_name renders the instantiation with qualified names on the inner type
// and the arguments.
pub fn (s &GenericInstantiationType) qualified_name() string {
	return '${s.inner.qualified_name()}[${s.specialization.map(it.qualified_name()).join(', ')}]'
}

// readable_name renders the instantiation with the names an editor shows.
pub fn (s &GenericInstantiationType) readable_name() string {
	return '${s.inner.readable_name()}[${s.specialization.map(it.readable_name()).join(', ')}]'
}

// module_name returns the module of the inner type.
pub fn (s &GenericInstantiationType) module_name() string {
	return s.inner.module_name()
}

// accept walks the inner type and then every specialization.
pub fn (s &GenericInstantiationType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)

	for specialization in s.specialization {
		specialization.accept(mut visitor)
	}
}

// substitute_generics returns the instantiation with name_map applied to the inner
// type and to the arguments.
pub fn (s &GenericInstantiationType) substitute_generics(name_map map[string]Type) Type {
	inner := s.inner.substitute_generics(name_map)
	specialization := s.specialization.map(it.substitute_generics(name_map))
	return new_generic_instantiation_type(inner, specialization)
}
