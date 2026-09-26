// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// infer_binary_expression_type returns bool for comparisons, and the left
// operand's type for the rest.
pub fn (t &TypeInferer) infer_binary_expression_type(element BinaryExpression) types.Type {
	match element.operator() {
		'&&', '||', '==', '!=', '<', '<=', '>', '>=' {
			return types.new_primitive_type('bool')
		}
		'<<' {
			return types.new_primitive_type('int')
		}
		'>>', '>>>' {
			return types.new_primitive_type('int')
		}
		'+', '-', '|', '^', '&', '*', '/' {
			left := element.left() or { return types.unknown_type }
			if left.node().type_name != .literal {
				return t.infer_type(left)
			}
			right := element.right() or { return types.unknown_type }
			return t.infer_type(right)
		}
		else {
			return types.unknown_type
		}
	}
}

// infer_unary_expression_type returns bool for `!` and the operand's type
// otherwise.
pub fn (t &TypeInferer) infer_unary_expression_type(element UnaryExpression) types.Type {
	operator := element.operator()
	if operator == '!' {
		return types.new_primitive_type('bool')
	}

	expression := element.expression() or { return types.unknown_type }
	expr_type := t.infer_type(expression)

	return match operator {
		'&' { types.Type(types.new_pointer_type(expr_type)) }
		'*' { types.unwrap_pointer_type(expr_type) }
		'<-' { types.unwrap_channel_type(expr_type) }
		else { expr_type }
	}
}

// infer_index_expression_type infers the type of whatever is being
// indexed.
pub fn (t &TypeInferer) infer_index_expression_type(element IndexExpression) types.Type {
	expr := element.expression() or { return types.unknown_type }
	expr_type := t.infer_type(expr)
	return t.infer_index_type(expr_type)
}

// infer_slice_expression_type infers the type a slice of an expression
// yields.
pub fn (t &TypeInferer) infer_slice_expression_type(element SliceExpression) types.Type {
	expr := element.expression() or { return types.unknown_type }
	expr_type := t.infer_type(expr)
	if expr_type is types.FixedArrayType {
		// [3]int -> []int
		return types.new_array_type(expr_type.inner)
	}
	return expr_type
}

// infer_compile_time_if_expression_type infers the type the branch block
// yields.
pub fn (t &TypeInferer) infer_compile_time_if_expression_type(element CompileTimeIfExpression) types.Type {
	block := element.block() or { return types.unknown_type }
	block_type := t.infer_type(PsiElement(block))
	if block_type is types.UnknownType {
		else_branch := element.else_branch() or { return types.unknown_type }
		return t.infer_type(PsiElement(else_branch))
	}
	return block_type
}

// infer_match_expression_type infers the type the match arms yield.
pub fn (t &TypeInferer) infer_match_expression_type(element MatchExpression) types.Type {
	arms := element.arms()
	if arms.len == 0 {
		return types.unknown_type
	}
	first := arms.first()
	block := first.find_child_by_name('block') or { return types.unknown_type }
	return t.infer_type(PsiElement(block))
}

// infer_array_creation_type infers the element type from the first
// expression, unknown when the literal is empty.
pub fn (t &TypeInferer) infer_array_creation_type(element ArrayCreation) types.Type {
	expressions := element.expressions()
	if expressions.len == 0 {
		return types.new_array_type(types.unknown_type)
	}
	first_expr := expressions.first()

	if element.is_fixed {
		return types.new_fixed_array_type(t.infer_type(first_expr), expressions.len)
	}

	return types.new_array_type(t.infer_type(first_expr))
}

// infer_map_init_expression_type infers a map's key and value types from
// its key-value pairs.
pub fn (t &TypeInferer) infer_map_init_expression_type(element MapInitExpression) types.Type {
	file := element.containing_file() or { return types.unknown_type }
	module_fqn := file.module_fqn()
	key_values := element.key_values()
	if key_values.len == 0 {
		return types.new_map_type(module_fqn, types.unknown_type, types.unknown_type)
	}

	first_key_value := key_values.first()
	if first_key_value is MapKeyedElement {
		key := first_key_value.key() or { return types.unknown_type }
		value := first_key_value.value() or { return types.unknown_type }
		key_type := t.infer_type(key)
		value_type := t.infer_type(value)
		return types.new_map_type(module_fqn, key_type, value_type)
	}

	return types.new_map_type(module_fqn, types.unknown_type, types.unknown_type)
}

// infer_reference_expression_type infers from what the reference resolves
// to.
pub fn (t &TypeInferer) infer_reference_expression_type(element ReferenceExpression) types.Type {
	if resolved := element.resolve() {
		return t.infer_type(resolved)
	}

	if element.text_matches('it') {
		call := get_it_call(element) or { return types.unknown_type }
		caller_type := call.caller_type()
		if caller_type is types.ArrayType {
			return caller_type.inner
		}
		return types.unknown_type
	}

	return types.unknown_type
}

// infer_if_expression_type infers the if block's type, falling back to the
// else block.
pub fn (t &TypeInferer) infer_if_expression_type(element IfExpression) types.Type {
	block := element.block() or { return types.unknown_type }
	block_type := t.infer_type(PsiElement(block))
	if block_type is types.UnknownType {
		else_branch := element.else_branch() or { return types.unknown_type }
		return t.infer_type(PsiElement(else_branch))
	}
	return block_type
}

// infer_unsafe_expression_type infers the type of the block inside unsafe.
pub fn (t &TypeInferer) infer_unsafe_expression_type(element UnsafeExpression) types.Type {
	block := element.block() or { return types.unknown_type }
	return t.infer_type(PsiElement(block))
}

// infer_selector_expression_type infers from what the selector resolves to,
// and instantiates the generic type when the receiver is one.
pub fn (t &TypeInferer) infer_selector_expression_type(element SelectorExpression) types.Type {
	resolved := element.resolve() or { return types.unknown_type }
	typ := t.infer_type(resolved)
	if types.is_generic(typ) {
		return GenericTypeInferer{}.infer_generic_fetch(resolved, element, typ)
	}
	return typ
}

// infer_range_type infers the element type a range yields.
pub fn (t &TypeInferer) infer_range_type(element Range) types.Type {
	if element.inclusive() {
		left := element.left() or { return types.unknown_type }
		return t.infer_type(left)
	}
	return types.new_array_type(types.new_primitive_type('int'))
}

// infer_literal_type infers a literal's type from its child token.
pub fn (_ &TypeInferer) infer_literal_type(element Literal) types.Type {
	child := element.first_child() or { return types.unknown_type }
	if child.node().type_name == .interpreted_string_literal
		|| child.node().type_name == .raw_string_literal {
		return types.string_type
	}

	if child.node().type_name == .c_string_literal {
		return types.new_pointer_type(types.new_primitive_type('u8'))
	}

	if child.node().type_name == .int_literal {
		return types.new_primitive_type('int')
	}

	if child.node().type_name == .float_literal {
		return types.new_primitive_type('f64')
	}

	if child.node().type_name == .rune_literal {
		return types.new_primitive_type('rune')
	}

	if child.node().type_name == .true_ || child.node().type_name == .false_ {
		return types.new_primitive_type('bool')
	}

	if child.node().type_name == .nil_ {
		return types.new_primitive_type('voidptr')
	}

	if child.node().type_name == .none_ {
		return types.new_primitive_type('none')
	}

	return types.unknown_type
}

// infer_index_type returns the type that indexing a value of this type
// yields.
pub fn (t &TypeInferer) infer_index_type(typ types.Type) types.Type {
	if typ is types.ArrayType {
		return typ.inner
	}
	if typ is types.FixedArrayType {
		return typ.inner
	}
	if typ is types.MapType {
		return typ.value
	}
	if typ is types.StructType {
		if typ.name == 'string' {
			return types.new_primitive_type('u8')
		}

		return types.unknown_type
	}
	if typ is types.PointerType {
		return typ.inner
	}

	return types.unknown_type
}
