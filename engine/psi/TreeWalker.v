// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

pub struct TreeWalker {
mut:
	already_visited_children bool
	cursor                   bindings.TreeCursor[bindings.NodeType] @[required]
}

// next advances the walker to the next node in depth-first order, or none at the end of the tree.
pub fn (mut tw TreeWalker) next() ?AstNode {
	if !tw.already_visited_children {
		if tw.cursor.to_first_child() {
			tw.already_visited_children = false
		} else if tw.cursor.next() {
			tw.already_visited_children = false
		} else {
			if !tw.cursor.to_parent() {
				return none
			}
			tw.already_visited_children = true
			return tw.next()
		}
	} else {
		if tw.cursor.next() {
			tw.already_visited_children = false
		} else {
			if !tw.cursor.to_parent() {
				return none
			}
			return tw.next()
		}
	}
	node := tw.cursor.current_node()?
	return node
}

// new_tree_walker creates a walker positioned on root_node.
pub fn new_tree_walker(root_node AstNode) TreeWalker {
	return TreeWalker{
		cursor: root_node.tree_cursor()
	}
}

// to_first_child moves the walker to its first child, reporting whether there was one.
@[inline]
pub fn (mut tw TreeWalker) to_first_child() bool {
	return tw.cursor.to_first_child()
}

// to_parent moves the walker to its parent, reporting whether there was one.
@[inline]
pub fn (mut tw TreeWalker) to_parent() bool {
	return tw.cursor.to_parent()
}

// next_sibling moves the walker to its next sibling, reporting whether there was one.
@[inline]
pub fn (mut tw TreeWalker) next_sibling() bool {
	return tw.cursor.next()
}

// current_node returns the node the walker stands on, or none at the end of the tree.
@[inline]
pub fn (tw &TreeWalker) current_node() ?AstNode {
	return tw.cursor.current_node()
}

// free releases the underlying C cursor.
@[inline]
pub fn (mut tw TreeWalker) free() {
	unsafe { C.ts_tree_cursor_delete(&tw.cursor.raw_cursor) }
}
