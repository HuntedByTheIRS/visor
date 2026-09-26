// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// infer_var_definition_type infers a var's type, and covers the definitions
// a range clause introduces.
pub fn (t &TypeInferer) infer_var_definition_type(element VarDefinition) types.Type {
	grand := element.parent_nth(2) or { return types.unknown_type }
	if grand.node().type_name == .range_clause {
		return t.process_range_clause(element, grand)
	}

	decl := element.declaration() or { return types.unknown_type }
	if init := decl.initializer_of(element) {
		typ := t.infer_type(init)
		if decl_parent := decl.parent() {
			if decl_parent is IfExpression {
				return types.unwrap_result_or_option_type(typ)
			}
		}

		if typ is types.MultiReturnType {
			parent := element.parent() or { return types.unknown_type }

			mut define_index := 0
			for index, def in parent.find_children_by_type(.reference_expression) {
				if def.is_equal(element) {
					define_index = index
					break
				}
			}

			inner_types := typ.types
			return inner_types[define_index] or { return types.unknown_type }
		}

		return typ
	}
	return types.unknown_type
}

// infer_parameter_declaration_type infers a parameter's type, wrapping a
// variadic parameter in an array.
pub fn (t &TypeInferer) infer_parameter_declaration_type(element ParameterDeclaration) types.Type {
	type_ := t.infer_from_plain_type(element)
	if _ := element.find_child_by_name('variadic') {
		return types.new_array_type(type_)
	}
	return type_
}

// infer_block_type infers the type of a block's last expression.
pub fn (t &TypeInferer) infer_block_type(element Block) types.Type {
	last_expression := element.last_expression() or { return types.unknown_type }
	return t.infer_type(last_expression)
}

// infer_global_var_definition_type converts the type a global var
// declares.
pub fn (t &TypeInferer) infer_global_var_definition_type(element GlobalVarDefinition, mut visited map[string]types.Type) types.Type {
	type_element := element.find_child_by_type_or_stub(.plain_type) or { return types.unknown_type }
	return t.convert_type(type_element, mut visited)
}

// infer_embedded_definition_type converts the struct an embedded field
// names.
pub fn (t &TypeInferer) infer_embedded_definition_type(element EmbeddedDefinition, mut visited map[string]types.Type) types.Type {
	if qualified_type := element.find_child_by_type_or_stub(.qualified_type) {
		return t.convert_type_inner(qualified_type, mut visited)
	}
	if generic_type := element.find_child_by_type_or_stub(.generic_type) {
		return t.convert_type_inner(generic_type, mut visited)
	}
	if ref_expression := element.find_child_by_type_or_stub(.type_reference_expression) {
		if ref_expression is TypeReferenceExpression {
			return t.infer_type_reference_type(ref_expression, mut visited)
		}
	}
	return types.unknown_type
}

// process_range_clause infers the element type of a range clause, from the
// expression on the right.
pub fn (t &TypeInferer) process_range_clause(element PsiElement, range PsiElement) types.Type {
	right := range.find_child_by_name('right') or { return types.unknown_type }
	right_type := types.unwrap_alias_type(t.infer_type(right))
	var_definition_list := range.find_child_by_name('left') or { return types.unknown_type }
	var_definitions := var_definition_list.find_children_by_type(.var_definition)

	if var_definitions.len == 1 {
		if right_type is types.ArrayType {
			return right_type.inner
		}
		if right_type is types.FixedArrayType {
			return right_type.inner
		}
		if right_type is types.MapType {
			return right_type.value
		}
		if right_type is types.StructType {
			if right_type.name() == 'string' {
				return types.new_primitive_type('u8')
			}

			return t.infer_iterator_struct(right_type)
		}
	}

	mut define_index := 0
	for index, def in var_definitions {
		if def.is_equal(element) {
			define_index = index
			break
		}
	}

	if define_index == 0 {
		if right_type is types.MapType {
			return right_type.key
		}
		return types.new_primitive_type('int')
	}

	if define_index == 1 {
		if right_type is types.ArrayType {
			return right_type.inner
		}
		if right_type is types.FixedArrayType {
			return right_type.inner
		}
		if right_type is types.MapType {
			return right_type.value
		}
		if right_type is types.StructType {
			if right_type.name() == 'string' {
				return types.new_primitive_type('u8')
			}

			return t.infer_iterator_struct(right_type)
		}

		return types.unknown_type
	}

	return types.unknown_type
}

// infer_iterator_struct infers the type an iterator struct's next method
// yields.
pub fn (_ &TypeInferer) infer_iterator_struct(typ types.Type) types.Type {
	method := find_method(typ, 'next') or { return types.unknown_type }
	if method is FunctionOrMethodDeclaration {
		signature := method.signature() or { return types.unknown_type }
		func_type := signature.get_type()
		if func_type is types.FunctionType {
			return types.unwrap_result_or_option_type(func_type.result)
		}
	}

	return types.unknown_type
}
