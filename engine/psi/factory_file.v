// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// file_element builds the element for the file's own furniture: its module
// clause, its imports and the tokens that are neither.
fn file_element(node AstNode, base_node PsiElementImpl) ?PsiElement {
	if node.type_name == .module_clause {
		return &ModuleClause{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .source_file {
		return &SourceFile{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .identifier {
		return &Identifier{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .line_comment {
		return &LineComment{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .block_comment {
		return &BlockComment{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .mutability_modifiers {
		return &MutabilityModifiers{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .visibility_modifiers {
		return &VisibilityModifiers{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_spec {
		return &ImportSpec{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_list {
		return &ImportList{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_declaration {
		return &ImportDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_path {
		return &ImportPath{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_name {
		return &ImportName{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .import_alias {
		return &ImportAlias{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .selective_import_list {
		return &SelectiveImportList{
			PsiElementImpl: base_node
		}
	}

	return none
}
