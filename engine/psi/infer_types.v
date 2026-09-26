// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// infer_type_initializer_type converts the type an initializer names.
pub fn (t &TypeInferer) infer_type_initializer_type(element TypeInitializer, mut visited map[string]types.Type) types.Type {
	type_element := element.find_child_by_type(.plain_type) or { return types.unknown_type }
	return t.convert_type(type_element, mut visited)
}

// convert_type converts a plain type element, with the visited map stopping
// the walk on recursive types.
pub fn (t &TypeInferer) convert_type(plain_type ?PsiElement, mut visited map[string]types.Type) types.Type {
	typ := plain_type or { return types.unknown_type }
	if typ !is PlainType {
		return types.unknown_type
	}

	type_text := typ.get_text()

	if type_text in visited {
		return visited[type_text]
	}

	mut child := typ.first_child_or_stub() or { return types.unknown_type }
	for child.element_type() == .unknown {
		child = child.next_sibling_or_stub() or { return types.unknown_type }
	}

	type_inner := t.convert_type_inner(child, mut visited)
	visited[type_text] = type_inner
	return type_inner
}

// convert_type_inner converts a type element that is already known to be
// one, recursing into its parts.
pub fn (t &TypeInferer) convert_type_inner(element PsiElement, mut visited map[string]types.Type) types.Type {
	if element.element_type() == .pointer_type {
		inner := element.last_child_or_stub()
		return types.new_pointer_type(t.convert_type(inner, mut visited))
	}

	if element.element_type() == .array_type {
		inner := element.last_child_or_stub()
		return types.new_array_type(t.convert_type(inner, mut visited))
	}

	if element.element_type() == .fixed_array_type {
		// TODO: parse size
		inner := element.last_child_or_stub()
		return types.new_array_type(t.convert_type(inner, mut visited))
	}

	if element.element_type() == .thread_type {
		inner := element.last_child_or_stub()
		return types.new_thread_type(t.convert_type(inner, mut visited))
	}

	if element.element_type() == .channel_type {
		inner := element.last_child_or_stub()
		return types.new_channel_type(t.convert_type(inner, mut visited))
	}

	if element.element_type() == .option_type {
		inner := element.last_child_or_stub()
		return types.new_option_type(t.convert_type(inner, mut visited), inner == none)
	}

	if element.element_type() == .result_type {
		inner := element.last_child_or_stub()
		return types.new_result_type(t.convert_type(inner, mut visited), inner == none)
	}

	if element.element_type() == .multi_return_type {
		inner_type_elements := element.find_children_by_type_or_stub(.plain_type)
		inner_types := inner_type_elements.map(t.convert_type(it, mut visited))
		return types.new_multi_return_type(inner_types)
	}

	if element.element_type() == .map_type {
		file := element.containing_file() or { return types.unknown_type }
		module_fqn := file.module_fqn()
		types_inner := element.find_children_by_type_or_stub(.plain_type)
		if types_inner.len != 2 {
			return types.new_map_type(module_fqn, types.unknown_type, types.unknown_type)
		}

		key := types_inner[0]
		value := types_inner[1]
		return types.new_map_type(module_fqn, t.convert_type(key, mut visited), t.convert_type(value, mut
			visited))
	}

	if element.element_type() == .function_type {
		signature := element.find_child_by_type_or_stub(.signature) or { return types.unknown_type }
		if signature is Signature {
			return t.process_signature(signature)
		}

		return types.unknown_type
	}

	if element.element_type() == .generic_type {
		inner_type := if inner := element.find_child_by_type_or_stub(.type_reference_expression) {
			if inner is TypeReferenceExpression {
				t.infer_type_reference_type(inner, mut visited)
			} else {
				return types.unknown_type
			}
		} else if inner_qualified := element.find_child_by_type_or_stub(.qualified_type) {
			t.convert_type_inner(inner_qualified, mut visited)
		} else {
			return types.unknown_type
		}

		type_parameters := element.find_child_by_type_or_stub(.type_parameters) or {
			return inner_type
		}
		type_parameters_list := type_parameters.find_children_by_type_or_stub(.plain_type)

		return types.new_generic_instantiation_type(inner_type, type_parameters_list.map(t.convert_type(it, mut
			visited)))
	}

	if element is QualifiedType {
		if ref := element.right() {
			if ref is TypeReferenceExpression {
				return t.infer_type_reference_type(ref, mut visited)
			}
		}
	}

	if element is TypeReferenceExpression {
		return t.infer_type_reference_type(element, mut visited)
	}

	return types.unknown_type
}

fn (t &TypeInferer) infer_type_reference_type(element TypeReferenceExpression, mut visited map[string]types.Type) types.Type {
	text := element.get_text()
	if types.is_primitive_type(text) {
		// fast path
		return types.new_primitive_type(text)
	}

	if text == 'string' {
		return types.string_type
	}

	if text == 'voidptr' {
		return types.voidptr_type
	}

	if text == 'array' {
		return types.builtin_array_type
	}

	if text == 'map' {
		return types.builtin_map_type
	}

	resolved := element.resolve() or { return types.unknown_type }
	if resolved is StructDeclaration {
		return resolved.get_type()
	}

	if resolved is InterfaceDeclaration {
		return resolved.get_type()
	}

	if resolved is EnumDeclaration {
		return resolved.get_type()
	}

	if resolved is TypeAliasDeclaration {
		name := resolved.name()
		visited[name] = types.unknown_type
		types_list := resolved.types()
		if types_list.len == 0 {
			return types.unknown_type
		}
		first := types_list.first()
		alias_type := types.new_alias_type(name, resolved.module_name(), t.convert_type(first, mut
			visited))
		visited[name] = alias_type
		return alias_type
	}

	if resolved is GenericParameter {
		return types.new_generic_type(element.name())
	}

	return types.unknown_type
}

fn (t &TypeInferer) infer_from_plain_type(element PsiElement) types.Type {
	plain_typ := element.find_child_by_type_or_stub(.plain_type) or { return types.unknown_type }
	mut visited := map[string]types.Type{}
	return t.convert_type(plain_typ, mut visited)
}
