// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// expression_element builds the element for an expression or a statement.
fn expression_element(node AstNode, base_node PsiElementImpl) ?PsiElement {
	if node.type_name == .argument {
		return &Argument{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .index_expression {
		return &IndexExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .selector_expression {
		return &SelectorExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .call_expression {
		return &CallExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .reference_expression {
		return &ReferenceExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .type_initializer {
		return &TypeInitializer{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .for_statement {
		return &ForStatement{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .block {
		return &Block{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .mutable_expression {
		return &MutExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .literal {
		return &Literal{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .range {
		return &Range{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .interpreted_string_literal {
		return &StringLiteral{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .unsafe_expression {
		return &UnsafeExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .array_creation {
		return &ArrayCreation{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .fixed_array_creation {
		return &ArrayCreation{
			PsiElementImpl: base_node
			is_fixed:       true
		}
	}

	if node.type_name == .map_init_expression {
		return &MapInitExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .map_keyed_element {
		return &MapKeyedElement{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .function_literal {
		return &FunctionLiteral{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .if_expression {
		return &IfExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .compile_time_if_expression {
		return &CompileTimeIfExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .match_expression {
		return &MatchExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .keyed_element {
		return &KeyedElement{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .slice_expression {
		return &SliceExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .or_block_expression {
		return &OrBlockExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .option_propagation_expression {
		return &OptionPropagationExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .result_propagation_expression {
		return &ResultPropagationExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .unary_expression {
		return &UnaryExpression{
			PsiElementImpl: base_node
		}
	}

	if node.type_name == .binary_expression {
		return &BinaryExpression{
			PsiElementImpl: base_node
		}
	}

	return none
}
