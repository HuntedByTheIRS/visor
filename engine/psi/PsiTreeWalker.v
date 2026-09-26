// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

struct PsiTreeWalker {
mut:
	containing_file ?&PsiFile
	tree_walker     TreeWalker
}

// next returns the next element in the tree, or none at the end.
pub fn (mut tw PsiTreeWalker) next() ?PsiElement {
	value := tw.tree_walker.next()?
	return create_element(value, tw.containing_file)
}

// new_psi_tree_walker starts a walker at the given node.
pub fn new_psi_tree_walker(root_node PsiElement) PsiTreeWalker {
	return PsiTreeWalker{
		tree_walker:     new_tree_walker(root_node.node())
		containing_file: root_node.containing_file()
	}
}

// free releases the walker and the tree walker it wraps.
@[inline]
pub fn (mut tw PsiTreeWalker) free() {
	tw.tree_walker.free()
}
