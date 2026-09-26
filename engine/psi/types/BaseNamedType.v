// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

struct BaseNamedType {
pub:
	module_name string
	name        string
}

// name returns the type's name without its module.
pub fn (s &BaseNamedType) name() string {
	return s.name
}

// qualified_name returns the name prefixed by the module the type is declared in.
pub fn (s &BaseNamedType) qualified_name() string {
	if s.module_name == '' {
		return s.name
	}
	return s.module_name + '.' + s.name
}

// readable_name returns the name as it is shown to a user: the last module
// component, and none at all for builtin, stubs and main.
pub fn (s &BaseNamedType) readable_name() string {
	if s.module_name == '' {
		return s.name
	}
	last_module := s.module_name.split('.').last()
	if last_module == 'builtin' || last_module == 'stubs' || last_module == 'main' {
		return s.name
	}
	return last_module + '.' + s.name
}

// module_name returns the module the type is declared in, or an empty string when it
// has none.
pub fn (s &BaseNamedType) module_name() string {
	return s.module_name
}
