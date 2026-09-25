// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub interface MutabilityOwner {
	is_mutable() bool
	mutability_modifiers() ?&MutabilityModifiers
}
