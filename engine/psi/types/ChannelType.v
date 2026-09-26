// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct ChannelType {
pub:
	inner Type
}

// new_channel_type returns a channel type over the given element type.
pub fn new_channel_type(inner Type) &ChannelType {
	return &ChannelType{
		inner: inner
	}
}

// name returns the name of the channel type.
pub fn (s &ChannelType) name() string {
	return 'chan ${s.inner.name()}'
}

// qualified_name returns the channel type with its element type qualified.
pub fn (s &ChannelType) qualified_name() string {
	return 'chan ${s.inner.qualified_name()}'
}

// readable_name returns the channel type as it is written in the source.
pub fn (s &ChannelType) readable_name() string {
	return 'chan ${s.inner.readable_name()}'
}

// module_name returns the module of the element type.
pub fn (s &ChannelType) module_name() string {
	return s.inner.module_name()
}

// accept passes the type and then its element type to the visitor.
pub fn (s &ChannelType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	s.inner.accept(mut visitor)
}

// substitute_generics returns a channel type with the generic parameters replaced.
pub fn (s &ChannelType) substitute_generics(name_map map[string]Type) Type {
	return new_channel_type(s.inner.substitute_generics(name_map))
}
