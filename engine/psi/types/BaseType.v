// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

pub struct BaseType {
pub:
	module_name string
}

// module_name returns the module the type belongs to.
@[markused]
pub fn (s &BaseType) module_name() string {
	return s.module_name
}
