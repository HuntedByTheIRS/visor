// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

struct BaseNamedType {
pub:
	module_name string
	name        string
}

pub fn (s &BaseNamedType) name() string {
	return s.name
}

pub fn (s &BaseNamedType) qualified_name() string {
	if s.module_name == '' {
		return s.name
	}
	return s.module_name + '.' + s.name
}

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

pub fn (s &BaseNamedType) module_name() string {
	return s.module_name
}
