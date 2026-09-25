// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

pub fn (node AstNode) parent_of_type(typ bindings.NodeType) ?AstNode {
	mut res := node
	for {
		res = res.parent()?
		if res.type_name == typ {
			return res
		}
	}

	return none
}
