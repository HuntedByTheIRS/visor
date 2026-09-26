// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub fn infer_type(elem ?PsiElement) types.Type {
	return TypeInferer{}.infer_type(elem)
}

// convert_type turns a plain type element into a type, starting with an
// empty visited map.
pub fn convert_type(plain_type ?PsiElement) types.Type {
	mut visited := map[string]types.Type{}
	return TypeInferer{}.convert_type(plain_type, mut visited)
}

pub struct TypeInferer {}

// infer_wrapped_expression unwraps the value an or-block, a `?` or a `!`
// expression yields. The three element types each spell their own expression()
// accessor, so the branch that names them calls this with the lookup result
// instead of a common interface.
fn (t &TypeInferer) infer_wrapped_expression(expression ?PsiElement) types.Type {
	expr := expression or { return types.unknown_type }
	expr_type := t.infer_type(expr)
	return types.unwrap_result_or_option_type(expr_type)
}

// infer_type returns the type of an element, reading through the cache
// first.
pub fn (t &TypeInferer) infer_type(elem ?PsiElement) types.Type {
	element := elem or { return types.unknown_type }

	if from_cache := type_cache.get(element) {
		return from_cache
	}

	typ := t.infer_type_impl(elem)
	type_cache.put(element, typ)
	return typ
}

// infer_type_impl does the inference work; the caching is in infer_type.
pub fn (t &TypeInferer) infer_type_impl(elem ?PsiElement) types.Type {
	element := elem or { return types.unknown_type }

	mut visited := map[string]types.Type{}

	match element.node().type_name {
		.in_expression, .is_expression, .select_expression {
			return types.new_primitive_type('bool')
		}
		.inc_expression, .dec_expression {
			return t.infer_type(element.first_child())
		}
		.as_type_cast_expression {
			return t.infer_type(element.last_child())
		}
		.spawn_expression, .go_expression {
			return types.new_thread_type(t.infer_type(element.last_child()))
		}
		.parenthesized_expression {
			expr := element.find_child_by_name('expression') or { return types.unknown_type }
			return t.infer_type(expr)
		}
		.receive_expression {
			operand := element.find_child_by_name('operand') or { return types.unknown_type }
			return types.unwrap_channel_type(t.infer_type(operand))
		}
		else {}
	}

	match element {
		BinaryExpression {
			return t.infer_binary_expression_type(element)
		}
		UnaryExpression {
			return t.infer_unary_expression_type(element)
		}
		OrBlockExpression {
			return t.infer_wrapped_expression(element.expression())
		}
		ResultPropagationExpression {
			return t.infer_wrapped_expression(element.expression())
		}
		OptionPropagationExpression {
			return t.infer_wrapped_expression(element.expression())
		}
		IndexExpression {
			return t.infer_index_expression_type(element)
		}
		SliceExpression {
			return t.infer_slice_expression_type(element)
		}
		Range {
			return t.infer_range_type(element)
		}
		SelectorExpression {
			return t.infer_selector_expression_type(element)
		}
		ReferenceExpression {
			return t.infer_reference_expression_type(element)
		}
		TypeInitializer {
			return t.infer_type_initializer_type(element, mut visited)
		}
		UnsafeExpression {
			return t.infer_unsafe_expression_type(element)
		}
		IfExpression {
			return t.infer_if_expression_type(element)
		}
		CompileTimeIfExpression {
			return t.infer_compile_time_if_expression_type(element)
		}
		MatchExpression {
			return t.infer_match_expression_type(element)
		}
		ArrayCreation {
			return t.infer_array_creation_type(element)
		}
		MapInitExpression {
			return t.infer_map_init_expression_type(element)
		}
		CallExpression {
			return t.infer_call_expression_type(element, mut visited)
		}
		Literal {
			return t.infer_literal_type(element)
		}
		Signature {
			return t.process_signature(element)
		}
		VarDefinition {
			return t.infer_var_definition_type(element)
		}
		FieldDeclaration {
			return t.infer_from_plain_type(element)
		}
		Receiver {
			return t.infer_from_plain_type(element)
		}
		ParameterDeclaration {
			return t.infer_parameter_declaration_type(element)
		}
		Block {
			return t.infer_block_type(element)
		}
		FunctionLiteral, FunctionOrMethodDeclaration, StaticMethodDeclaration,
		InterfaceMethodDeclaration {
			signature := element.signature() or { return types.unknown_type }
			return t.process_signature(signature)
		}
		EnumDeclaration {
			return element.get_type()
		}
		EnumFieldDeclaration {
			return element.get_type()
		}
		ConstantDefinition {
			return element.get_type()
		}
		TypeReferenceExpression {
			return t.infer_type_reference_type(element, mut visited)
		}
		GlobalVarDefinition {
			return t.infer_global_var_definition_type(element, mut visited)
		}
		EmbeddedDefinition {
			return t.infer_embedded_definition_type(element, mut visited)
		}
		else {
			return types.unknown_type
		}
	}
}

// infer_context_type infers the type the surrounding expression expects
// here.
pub fn (t &TypeInferer) infer_context_type(elem ?PsiElement) types.Type {
	element := elem or { return types.unknown_type }
	parent := element.parent() or { return types.unknown_type }

	if parent.element_type() == .binary_expression {
		right := parent.last_child_or_stub() or { return types.unknown_type }
		if right.is_equal(element) {
			left := parent.first_child_or_stub() or { return types.unknown_type }
			return t.infer_type(left)
		}
	}

	if parent.element_type() == .expression_list {
		grand := parent.parent() or { return types.unknown_type }
		if grand.element_type() == .assignment_statement {
			// TODO: support multiple assignments
			right_list := grand.last_child_or_stub() or { return types.unknown_type }
			right := right_list.first_child_or_stub() or { return types.unknown_type }
			if right.is_equal(element) {
				left_list := grand.first_child_or_stub() or { return types.unknown_type }
				left := left_list.first_child_or_stub() or { return types.unknown_type }
				return t.infer_type(left)
			}
		}
	}

	if parent.element_type() == .match_expression_list {
		match_expr := parent.parent_of_type(.match_expression) or { return types.unknown_type }
		if match_expr is MatchExpression {
			return t.infer_type(match_expr.expression())
		}
	}

	if parent is KeyedElement {
		field := parent.field() or { return types.unknown_type }
		ref := field.reference_expression() or { return types.unknown_type }
		resolved := ref.resolve() or { return types.unknown_type }
		return t.infer_from_plain_type(resolved)
	}

	if parent.element_type() == .argument {
		call_expression := parent.parent_nth(2) or { return types.unknown_type }
		if call_expression is CallExpression {
			called := call_expression.resolve() or { return types.unknown_type }

			if called is FunctionOrMethodDeclaration {
				if called.is_method()
					&& called.receiver_type().qualified_name() == types.flag_enum_type.qualified_name() {
					// when color.has(.red)
					return call_expression.caller_type()
				}
			}

			typ := t.infer_type(called)

			if typ is types.FunctionType {
				index := call_expression.parameter_index_on_offset(parent.node().start_byte())
				param_type := typ.params[index] or { return types.unknown_type }
				return param_type
			}
		}
	}

	if parent.element_type() == .expression_list {
		grand := parent.parent() or { return types.unknown_type }
		if grand.element_type() == .return_statement {
			return t.enclosing_function_return_type(grand)
		}
	}

	if parent.element_type() == .simple_statement {
		if_expr := parent.parent_nth(2) or { return types.unknown_type }
		if if_expr is IfExpression {
			return_stmt := if_expr.parent_nth(2) or { return types.unknown_type }
			if return_stmt.element_type() == .return_statement {
				return t.enclosing_function_return_type(return_stmt)
			}
		}

		match_expr := if_expr.parent_nth(2) or { return types.unknown_type }
		if match_expr is MatchExpression {
			return_stmt := match_expr.parent_nth(2) or { return types.unknown_type }
			if return_stmt.element_type() == .return_statement {
				return t.enclosing_function_return_type(return_stmt)
			}
		}
	}

	if parent is FieldDeclaration {
		return parent.get_type()
	}

	if parent is ArrayCreation {
		expressions := parent.expressions()
		first := expressions[0] or { return types.unknown_type }

		if first.element_type() != .enum_fetch {
			return t.infer_type(first)
		}

		bin_expr := parent.parent() or { return types.unknown_type }
		if bin_expr.element_type() in [.binary_expression, .in_expression] {
			left := bin_expr.first_child_or_stub() or { return types.unknown_type }
			if left.is_parent_of(parent) {
				return types.unknown_type
			}

			return t.infer_type(left)
		}

		return types.unknown_type
	}

	return types.unknown_type
}

fn (_ &TypeInferer) enclosing_function_return_type(elem PsiElement) types.Type {
	function := elem.parent_of_any_type(.function_declaration, .function_literal) or {
		return types.unknown_type
	}
	if function is SignatureOwner {
		signature := function.signature() or { return types.unknown_type }
		typ := signature.get_type()
		if typ is types.FunctionType {
			return typ.result
		}
	}
	return types.unknown_type
}
