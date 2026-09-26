// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// written_type_element builds the element for a type as it is written in source.
fn written_type_element(node AstNode, base_node PsiElementImpl) ?PsiElement {
	if node.type_name == .plain_type {
		return &PlainType{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .type_reference_expression {
		return &TypeReferenceExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .qualified_type {
		return &QualifiedType{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .generic_parameters {
		return &GenericParameters{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .generic_parameter {
		return &GenericParameter{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .type_parameters {
		return &GenericTypeArguments{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .field_name {
		return &FieldName{
			PsiElementImpl: base_node
		}
	}

	return none
}
