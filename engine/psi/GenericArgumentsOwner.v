// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub interface GenericArgumentsOwner {
	type_arguments() ?&GenericTypeArguments
}
