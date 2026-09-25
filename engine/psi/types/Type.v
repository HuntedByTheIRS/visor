// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub interface Type {
	name() string
	qualified_name() string
	readable_name() string
	module_name() string
	substitute_generics(name_map map[string]Type) Type
	accept(mut visitor TypeVisitor)
}
