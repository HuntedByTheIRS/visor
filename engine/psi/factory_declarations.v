// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// declaration_element builds the element for a declaration: the name it
// introduces, the header around it and its attributes. The variable probe comes
// first, since a reference expression inside a var declaration is the definition
// and not a reference.
fn declaration_element(node AstNode, containing_file ?&PsiFile, base_node PsiElementImpl) ?PsiElement {
	var := node_to_var_definition(node, containing_file, base_node)
	if !isnil(var) {
		return var
	}

	if node.type_name == .function_declaration {
		return &FunctionOrMethodDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .static_method_declaration {
		return &StaticMethodDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .receiver {
		return &Receiver{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .static_receiver {
		return &StaticReceiver{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .struct_declaration {
		return &StructDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .interface_declaration {
		return &InterfaceDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .interface_method_definition {
		return &InterfaceMethodDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .enum_declaration {
		return &EnumDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .enum_field_definition {
		return &EnumFieldDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .struct_field_declaration {
		return &FieldDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .struct_field_scope {
		return &StructFieldScope{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .const_declaration {
		return &ConstantDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .const_definition {
		return &ConstantDefinition{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .var_declaration {
		return &VarDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .global_var_definition {
		return &GlobalVarDefinition{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .embedded_definition {
		return &EmbeddedDefinition{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .type_declaration {
		return &TypeAliasDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .signature {
		return &Signature{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .parameter_list {
		return &ParameterList{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .parameter_declaration {
		return &ParameterDeclaration{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .attributes {
		return &Attributes{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .attribute {
		return &Attribute{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .attribute_expression {
		return &AttributeExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .value_attribute {
		return &ValueAttribute{
			PsiElementImpl: base_node
		}
	}

	return none
}
