// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// create_element builds the element for a tree-sitter node, asking each family in
// turn. A node type with no element of its own falls back to the plain element,
// which is what every punctuation token gets.
pub fn create_element(node AstNode, containing_file ?&PsiFile) PsiElement {
	base_node := new_psi_node(containing_file, node)

	if element := declaration_element(node, containing_file, base_node) {
		return element
	}
	if element := expression_element(node, base_node) {
		return element
	}
	if element := written_type_element(node, base_node) {
		return element
	}
	if element := file_element(node, base_node) {
		return element
	}

	return &PsiElementImpl{
		node:            node
		containing_file: containing_file
	}
}

// node_to_var_definition builds the variable definition a node introduces, or nil when the node defines no variable.
@[inline]
pub fn node_to_var_definition(node AstNode, containing_file ?&PsiFile, base_node ?PsiElementImpl) &VarDefinition {
	if node.type_name == .var_definition {
		return &VarDefinition{
			PsiElementImpl: base_node or { new_psi_node(containing_file, node) }
		}
	}

	if node.type_name == .reference_expression {
		parent := node.parent() or { return unsafe { nil } }
		if parent.type_name != .expression_list && parent.type_name != .mutable_expression {
			return unsafe { nil }
		}

		grand := parent.parent() or { return unsafe { nil } }

		if grand.type_name == .var_declaration {
			var_list := grand.child_by_field_name('var_list') or { return unsafe { nil } }
			if var_list.is_parent_of(node) {
				return &VarDefinition{
					PsiElementImpl: base_node or { new_psi_node(containing_file, node) }
				}
			}
		}
		if grand_grand := grand.parent() {
			if grand_grand.type_name == .var_declaration && parent.type_name == .mutable_expression {
				return &VarDefinition{
					PsiElementImpl: base_node or { new_psi_node(containing_file, node) }
				}
			}
		}
	}

	return unsafe { nil }
}
