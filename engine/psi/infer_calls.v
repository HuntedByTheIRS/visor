// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// infer_call_expression_type handles a call whose callee is a function
// literal.
pub fn (t &TypeInferer) infer_call_expression_type(element CallExpression, mut visited map[string]types.Type) types.Type {
	if grand := element.expression() {
		if grand is FunctionLiteral {
			signature := grand.signature() or { return types.unknown_type }
			return t.convert_type(signature.result(), mut visited)
		}
	}
	return t.infer_call_expr_type(element)
}

// process_signature builds the type a signature produces, out of its
// parameters.
pub fn (t &TypeInferer) process_signature(signature Signature) types.Type {
	params := signature.parameters()
	// Written as a loop: V 0.5.2 gives the map result the type of the closure
	// instead of the type the closure returns, which the C generator then uses
	// as the element size.
	mut param_types := []types.Type{cap: params.len}
	for param in params {
		// TODO: support fn (int, string) without names
		if param is PsiTypedElement {
			param_types << param.get_type()
		} else {
			param_types << types.unknown_type
		}
	}
	result := signature.result()
	mut visited := map[string]types.Type{}
	result_type := t.convert_type(result, mut visited)
	module_fqn := if file := signature.containing_file() {
		file.module_fqn()
	} else {
		''
	}
	return types.new_function_type(module_fqn, param_types, result_type, result == none)
}

// infer_call_expr_type infers a call's result type, and handles
// json.decode first.
pub fn (t &TypeInferer) infer_call_expr_type(element CallExpression) types.Type {
	if element.is_json_decode() {
		return types.new_result_type(element.get_json_decode_type(), false)
	}

	// The compile-time builtins are the compiler's own: `$env`, `$tmpl` and
	// `$embed_file` resolve to nothing in the index, so without this a `:=` on one
	// of them infers nothing and the label that would read `string` is not drawn.
	if comptime := comptime_call_type(element) {
		return comptime
	}

	if resolved := element.resolve() {
		expr_type := t.infer_type(resolved)
		if expr_type is types.FunctionType {
			result_type := expr_type.result
			if types.is_generic(result_type) {
				if resolved is GenericParametersOwner {
					return GenericTypeInferer{}.infer_generic_call(element, resolved, result_type)
				}
			}

			if resolved is FunctionOrMethodDeclaration {
				if !resolved.is_method() {
					return result_type
				}

				if typ := t.process_map_array_method_call(resolved, expr_type, element) {
					return typ
				}
			}

			return result_type
		}
	}

	// most probably type cast expression: PsiElement(node)
	// try to resolve as type
	expr := element.ref_expression() or { return types.unknown_type }
	ref := new_reference(element.containing_file, expr, true)
	if resolved := ref.resolve() {
		if resolved is PsiTypedElement {
			return resolved.get_type()
		}
	}

	return types.unknown_type
}

// process_map_array_method_call infers the result of a call to a map or
// array built-in method.
pub fn (t &TypeInferer) process_map_array_method_call(element FunctionOrMethodDeclaration, element_type types.FunctionType,
	expr CallExpression) ?types.Type {
	receiver_type := types.unwrap_pointer_type(element.receiver_type())

	if types.is_builtin_array_type(receiver_type) {
		if typ := t.process_array_method_call(element, element_type, expr) {
			return typ
		}
	}

	if types.is_builtin_map_type(receiver_type) {
		if typ := t.process_map_method_call(element, expr) {
			return typ
		}
	}

	return none
}

// process_array_method_call infers the result an array method returns.
pub fn (_ &TypeInferer) process_array_method_call(element FunctionOrMethodDeclaration, element_type types.FunctionType,
	expr CallExpression) ?types.Type {
	return_type := element_type.result

	if return_type is types.VoidPtrType {
		caller_type := expr.caller_type()
		if caller_type is types.ArrayType {
			return caller_type.inner
		}
	}

	if types.is_builtin_array_type(return_type) {
		if element.name() == 'map' {
			method_arguments := expr.arguments()
			first_arg := method_arguments[0] or { return none }
			first_arg_type := infer_type(first_arg)

			// map(fn (int) <type> { ... }) -> array<type>
			if first_arg_type is types.FunctionType {
				return *types.new_array_type(first_arg_type.result)
			}

			// map(it > 10) -> array<bool>
			return *types.new_array_type(first_arg_type)
		}

		return expr.caller_type()
	}

	return none
}

// process_map_method_call infers the result of a call on a map, none when
// the method is not one it knows.
pub fn (_ &TypeInferer) process_map_method_call(element FunctionOrMethodDeclaration, expr CallExpression) ?types.Type {
	caller_type := types.unwrap_alias_type(expr.caller_type())

	if caller_type is types.MapType {
		match element.name() {
			'keys' { return *types.new_array_type(caller_type.key) }
			'values' { return *types.new_array_type(caller_type.value) }
			'clone', 'move' { return caller_type }
			else { return none }
		}
	}

	return none
}
