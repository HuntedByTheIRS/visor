// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub fn unwrap_pointer_type(typ Type) Type {
	if typ is PointerType {
		return typ.inner
	}
	return typ
}

// unwrap_alias_type returns the aliased type when typ is an alias, and typ otherwise.
pub fn unwrap_alias_type(typ Type) Type {
	if typ is AliasType {
		return typ.inner
	}
	return typ
}

// unwrap_channel_type returns the channel's element type when typ is a channel, and typ otherwise.
pub fn unwrap_channel_type(typ Type) Type {
	if typ is ChannelType {
		return typ.inner
	}
	return typ
}

// unwrap_result_or_option_type returns the inner type when typ is a result or an option, and typ otherwise.
pub fn unwrap_result_or_option_type(typ Type) Type {
	if typ is ResultType {
		return typ.inner
	}
	if typ is OptionType {
		return typ.inner
	}
	return typ
}

// unwrap_result_or_option_type_if unwraps only when condition is true, so a caller can unwrap based on how the expression is used.
pub fn unwrap_result_or_option_type_if(typ Type, condition bool) Type {
	if condition {
		return unwrap_result_or_option_type(typ)
	}
	return typ
}

// unwrap_generic_instantiation_type returns the instantiated type when typ is a generic instantiation, and typ otherwise.
pub fn unwrap_generic_instantiation_type(typ Type) Type {
	if typ is GenericInstantiationType {
		return typ.inner
	}
	return typ
}

// is_builtin_array_type reports whether typ is the builtin array struct.
pub fn is_builtin_array_type(typ Type) bool {
	if typ is StructType {
		return typ.qualified_name() == builtin_array_type.qualified_name()
	}
	return false
}

// is_builtin_map_type reports whether typ is the builtin map struct.
pub fn is_builtin_map_type(typ Type) bool {
	if typ is StructType {
		return typ.qualified_name() == builtin_map_type.qualified_name()
	}
	return false
}

struct IsGenericVisitor {
mut:
	is_generic bool
}

fn (mut v IsGenericVisitor) enter(typ Type) bool {
	if typ is GenericType {
		v.is_generic = true
		return false
	}
	return true
}

// is_generic reports whether typ is a generic type or contains one anywhere inside it.
pub fn is_generic(typ Type) bool {
	if typ is GenericType {
		return true
	}

	mut v := IsGenericVisitor{}
	typ.accept(mut v)
	return v.is_generic
}
