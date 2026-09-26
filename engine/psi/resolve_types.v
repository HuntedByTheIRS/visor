// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// process_type feeds the members reachable through typ to the processor.
pub fn (r &SubResolver) process_type(typ types.Type, mut processor PsiScopeProcessor) bool {
	if typ is types.StructType {
		if struct_ := r.find_struct(stubs_index, typ.qualified_name()) {
			is_method_ref := if grand := r.element().parent_nth(2) {
				grand is CallExpression
			} else {
				false
			}

			// If it is a call, then most likely it is a method call, but it
			// could be a function call that is stored in a structure field.
			if is_method_ref {
				if !r.process_methods(typ, mut processor) {
					return false
				}
				if !r.process_elements(struct_.fields(), mut processor) {
					return false
				}
			} else {
				if !r.process_elements(struct_.fields(), mut processor) {
					return false
				}
				if !r.process_methods(typ, mut processor) {
					return false
				}
			}

			for def in struct_.embedded_definitions() {
				if !processor.execute(def) {
					return false
				}
			}
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.InterfaceType {
		if interface_ := r.find_interface(stubs_index, typ.qualified_name()) {
			if !r.process_methods(typ, mut processor) {
				return false
			}
			if !r.process_elements(interface_.fields(), mut processor) {
				return false
			}
			if !r.process_elements(interface_.methods(), mut processor) {
				return false
			}

			for def in interface_.embedded_definitions() {
				if !processor.execute(def) {
					return false
				}
			}
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.EnumType {
		enum_ := r.find_enum(stubs_index, typ.qualified_name()) or { return true }
		if !r.process_elements(enum_.fields(), mut processor) {
			return false
		}

		if !r.process_methods(typ, mut processor) {
			return false
		}

		if enum_.is_flag() {
			if !r.process_type(types.flag_enum_type, mut processor) {
				return false
			}
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.ArrayType {
		if !r.process_methods(typ, mut processor) {
			return false
		}

		if !r.process_type(types.builtin_array_type, mut processor) {
			return false
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.MapType {
		if !r.process_methods(typ, mut processor) {
			return false
		}

		if !r.process_type(types.builtin_map_type, mut processor) {
			return false
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.PointerType {
		if !r.process_type(typ.inner, mut processor) {
			return false
		}
		if !r.process_any_type(mut processor) {
			return false
		}
		return true
	}

	if typ is types.OptionType {
		if !r.process_type(typ.inner, mut processor) {
			return false
		}
		if !r.process_any_type(mut processor) {
			return false
		}
		return true
	}

	if typ is types.ResultType {
		if !r.process_type(typ.inner, mut processor) {
			return false
		}
		if !r.process_any_type(mut processor) {
			return false
		}
		return true
	}

	if typ is types.AliasType {
		if !r.process_methods(typ, mut processor) {
			return false
		}

		if !r.process_type(typ.inner, mut processor) {
			return false
		}

		if !r.process_any_type(mut processor) {
			return false
		}

		return true
	}

	if typ is types.GenericInstantiationType {
		if !r.process_type(typ.inner, mut processor) {
			return false
		}
		if !r.process_any_type(mut processor) {
			return false
		}
		return true
	}

	if !r.process_methods(typ, mut processor) {
		return false
	}

	if !r.process_any_type(mut processor) {
		return false
	}

	return true
}

// process_any_type feeds the methods every type shares to the processor.
pub fn (r &SubResolver) process_any_type(mut processor PsiScopeProcessor) bool {
	return r.process_methods(types.any_type, mut processor)
}

// process_methods feeds the methods defined on typ to the processor.
pub fn (r &SubResolver) process_methods(typ types.Type, mut processor PsiScopeProcessor) bool {
	return r.process_elements(methods_list(typ), mut processor)
}

// process_enum_fetch resolves the fetch against the enum type the context expects.
pub fn (r &SubResolver) process_enum_fetch(parent PsiElement, mut processor PsiScopeProcessor) bool {
	context_type := TypeInferer{}.infer_context_type(parent)
	return r.process_type(context_type, mut processor)
}

// process_type_initializer_field feeds the fields of the initialised type to the processor.
pub fn (r &SubResolver) process_type_initializer_field(mut processor PsiScopeProcessor) bool {
	if init_expr := r.element().parent_of_type(.type_initializer) {
		if init_expr is PsiTypedElement {
			typ :=
				types.unwrap_generic_instantiation_type(types.unwrap_pointer_type(infer_type(init_expr as PsiElement)))
			if typ is types.StructType {
				if !r.process_struct_type_fields(typ, mut processor) {
					return false
				}
			}
			if typ is types.ArrayType {
				if !r.process_struct_type_fields(types.array_init_type, mut processor) {
					return false
				}
			}
			if typ is types.ChannelType {
				if !r.process_struct_type_fields(types.chan_init_type, mut processor) {
					return false
				}
			}
		}
	}

	if call_expr := r.element().parent_of_type(.call_expression) {
		if call_expr is CallExpression {
			resolved := call_expr.resolve() or { return true }
			if resolved is SignatureOwner {
				signature := resolved.signature() or { return true }
				parameters := signature.parameters()
				if parameters.len == 0 {
					return true
				}

				last_parameter := parameters.last()
				param_type := infer_type(last_parameter)
				if param_type is types.StructType {
					if !r.process_struct_type_fields(param_type, mut processor) {
						return false
					}
				}
			}
		}
	}

	return true
}

// process_struct_type_fields feeds the fields of struct_type to the processor.
pub fn (r &SubResolver) process_struct_type_fields(struct_type types.StructType, mut processor PsiScopeProcessor) bool {
	if struct_ := r.find_struct(stubs_index, struct_type.qualified_name()) {
		fields := struct_.fields()
		for field in fields {
			if !processor.execute(field) {
				return false
			}
		}
	}
	return true
}
