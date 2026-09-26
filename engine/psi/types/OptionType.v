// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct OptionType {
pub:
	inner    Type
	no_inner bool
}

// new_option_type returns an option type over inner, or a bare ? when no_inner is set.
pub fn new_option_type(inner Type, no_inner bool) &OptionType {
	return &OptionType{
		inner:    inner
		no_inner: no_inner
	}
}

// name returns the type as it is written in source, for example ?string.
pub fn (s &OptionType) name() string {
	if s.no_inner {
		return '?'
	}
	return '?${s.inner.name()}'
}

// qualified_name returns the name with its module qualifier, for example ?mod.Type.
pub fn (s &OptionType) qualified_name() string {
	if s.no_inner {
		return '?'
	}
	return '?${s.inner.qualified_name()}'
}

// readable_name returns the name in the form shown to users.
pub fn (s &OptionType) readable_name() string {
	if s.no_inner {
		return '?'
	}
	return '?${s.inner.readable_name()}'
}

// module_name returns the module of the inner type.
pub fn (s &OptionType) module_name() string {
	return s.inner.module_name()
}

// accept hands the type to the visitor and, unless the visitor stops there, walks the inner type.
pub fn (s &OptionType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a copy with the inner type's generics replaced.
pub fn (s &OptionType) substitute_generics(name_map map[string]Type) Type {
	return new_option_type(s.inner.substitute_generics(name_map), s.no_inner)
}
