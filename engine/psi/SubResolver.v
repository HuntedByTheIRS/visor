// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct SubResolver {
pub:
	containing_file ?&PsiFile
	element         ReferenceExpressionBase
	for_types       bool
	for_attributes  bool
}

fn (r &SubResolver) element() PsiElement {
	return r.element as PsiElement
}

// process_resolve_variants resolves through the qualifier when the reference has one, and searches the visible scopes otherwise.
pub fn (r &SubResolver) process_resolve_variants(mut processor PsiScopeProcessor) bool {
	return if qualifier := r.element.qualifier() {
		r.process_qualifier_expression(qualifier, mut processor)
	} else {
		r.process_unqualified_resolve(mut processor)
	}
}

// process_qualifier_expression feeds the members the qualifier exposes to the processor.
pub fn (r &SubResolver) process_qualifier_expression(qualifier PsiElement, mut processor PsiScopeProcessor) bool {
	if qualifier is PsiTypedElement {
		typ := infer_type(qualifier as PsiElement)
		if typ !is types.UnknownType {
			if !r.process_type(typ, mut processor) {
				return false
			}
		}
	}

	if qualifier is ReferenceExpressionBase {
		resolved := qualifier.resolve() or { return true }

		if resolved is ImportSpec {
			import_name := resolved.import_name()
			file := r.containing_file or { return true }
			specs := file.resolve_import_specs(import_name)

			for _, spec in specs {
				target_fqn := spec.qualified_name()
				real_fqn := stubs_index.find_real_module_fqn(target_fqn)
				elements := stubs_index.get_all_declarations_from_module(real_fqn, r.for_types)

				if !r.process_elements(elements, mut processor) {
					return false
				}
			}
			return true
		}

		if resolved is ModuleClause {
			file := r.containing_file or { return true }
			module_name := stubs_index.get_module_qualified_name(file.path)
			current_module_elements := stubs_index.get_all_declarations_from_module(module_name,
				r.for_types)
			for elem in current_module_elements {
				if !processor.execute(elem) {
					return false
				}
			}
		}

		if resolved is StructDeclaration {
			methods := static_methods_list(resolved.get_type())
			if !r.process_elements(methods, mut processor) {
				return false
			}
		}
	}

	return true
}

// process_elements feeds each element to the processor, stopping when it returns false.
pub fn (r &SubResolver) process_elements(elements []PsiElement, mut processor PsiScopeProcessor) bool {
	for element in elements {
		if !processor.execute(element) {
			return false
		}
	}
	return true
}

// process_unqualified_resolve searches every scope visible from an unqualified reference.
pub fn (r &SubResolver) process_unqualified_resolve(mut processor PsiScopeProcessor) bool {
	if r.for_attributes {
		return r.resolve_attribute(mut processor)
	}

	if parent := r.element().parent() {
		if parent is FieldName {
			return r.process_type_initializer_field(mut processor)
		}

		if parent.element_type() == .enum_fetch {
			return r.process_enum_fetch(parent, mut processor)
		}
	}

	if !r.process_block(mut processor) {
		return false
	}
	if !r.process_imported_modules(mut processor) {
		return false
	}
	if !r.process_selective_imports(mut processor) {
		return false
	}
	if !r.process_owner_generic_ts(mut processor) {
		return false
	}
	if !r.process_os_module(mut processor) {
		return false
	}

	builtin_elements := stubs_index.get_all_declarations_from_module('builtin', r.for_types)
	for element in builtin_elements {
		if !processor.execute(element) {
			return false
		}
	}

	if r.for_types {
		stubs_elements := stubs_index.get_all_declarations_from_module('stubs', r.for_types)
		for element in stubs_elements {
			if !processor.execute(element) {
				return false
			}
		}
	}

	module_name := if file := r.containing_file {
		stubs_index.get_module_qualified_name(file.path)
	} else {
		''
	}

	element := r.element()
	if element is PsiNamedElement {
		fqn := if module_name.len != 0 {
			module_name + '.' + element.name()
		} else {
			element.name()
		}

		if !r.for_types {
			if func := r.find_function(stubs_index, fqn) {
				if !processor.execute(func) {
					return false
				}
			}

			if constant := r.find_constant(stubs_index, fqn) {
				if !processor.execute(constant) {
					return false
				}
			}
		}

		if struct_ := r.find_struct(stubs_index, fqn) {
			if !processor.execute(struct_) {
				return false
			}
		}

		if interface_ := r.find_interface(stubs_index, fqn) {
			if !processor.execute(interface_) {
				return false
			}
		}

		if enum_ := r.find_enum(stubs_index, fqn) {
			if !processor.execute(enum_) {
				return false
			}
		}

		if alias := r.find_type_alias(stubs_index, fqn) {
			if !processor.execute(alias) {
				return false
			}
		}

		// global variable cannot have module name
		if global_variable := r.find_global_variable(stubs_index, element.name()) {
			if !processor.execute(global_variable) {
				return false
			}
		}
	}

	mod_decls := stubs_index.get_all_declarations_from_module(module_name, r.for_types)
	if !r.process_elements(mod_decls, mut processor) {
		return false
	}
	if !r.process_module_clause(mut processor) {
		return false
	}

	return true
}
