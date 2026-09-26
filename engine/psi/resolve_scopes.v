// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

// walk_up walks the parents of element, feeding each scope's declarations to the processor.
pub fn (r &SubResolver) walk_up(element PsiElement, mut processor PsiScopeProcessor) bool {
	mut run := element
	mut last_parent := element
	for {
		if mut run is ForStatement {
			vars := run.var_definitions()
			for v in vars {
				if !processor.execute(v) {
					return false
				}
			}
		}

		if mut run is IfExpression {
			if def := run.var_definition() {
				if !processor.execute(def) {
					return false
				}
			}
		}

		if mut run is Block {
			if !run.process_declarations(mut processor, last_parent) {
				return false
			}

			if !r.process_parameters(run, mut processor) {
				return false
			}

			if !r.process_receiver(run, mut processor) {
				return false
			}
		}

		if mut run is SourceFile {
			if !run.process_declarations(mut processor, last_parent) {
				return false
			}
		}

		if mut run is GenericParametersOwner {
			if parameters := run.generic_parameters() {
				params := parameters.parameters()
				for param in params {
					if !processor.execute(param) {
						return false
					}
				}
			}
		}

		last_parent = run
		run = run.parent() or { break }
	}
	return true
}

// process_parameters feeds the parameters of the enclosing function to the processor.
pub fn (_ &SubResolver) process_parameters(b Block, mut processor PsiScopeProcessor) bool {
	parent := b.parent() or { return true }

	if parent is SignatureOwner {
		signature := parent.signature() or { return true }

		params := signature.parameters()
		for param in params {
			if !processor.execute(param) {
				return false
			}
		}
	}

	return true
}

// process_receiver feeds the receiver of the enclosing method to the processor.
pub fn (_ &SubResolver) process_receiver(b Block, mut processor PsiScopeProcessor) bool {
	parent := b.parent() or { return true }

	if parent is FunctionOrMethodDeclaration {
		receiver := parent.receiver() or { return true }
		if !processor.execute(receiver) {
			return false
		}
	}

	return true
}

// process_block searches the scopes enclosing the reference, starting from its own block.
pub fn (r &SubResolver) process_block(mut processor PsiScopeProcessor) bool {
	// if r.containing_file.is_stub_based() {
	// 	return true
	// }

	// mut delegate := ResolveProcessor{
	// 	...processor
	// }
	// if delegate.result.len == 0 {
	// 	return true
	// }
	//
	// for result in delegate.result {
	// 	processor.result << result
	// }

	return r.walk_up(r.element as PsiElement, mut processor)
}

// process_module_clause feeds the file's module clause to the processor.
pub fn (r &SubResolver) process_module_clause(mut processor PsiScopeProcessor) bool {
	file := r.containing_file or { return true }
	mod := file.module_clause() or { return true }
	return processor.execute(mod)
}

// process_imported_modules feeds the import spec the reference names to the processor.
pub fn (r &SubResolver) process_imported_modules(mut processor PsiScopeProcessor) bool {
	file := r.containing_file or { return true }
	search_name := r.element().get_text()
	import_spec := file.resolve_import_spec(search_name) or { return true }

	if !processor.execute(import_spec) {
		return false
	}

	return true
}

// process_selective_imports resolves the reference against the symbols a selective import brings in.
pub fn (r &SubResolver) process_selective_imports(mut processor PsiScopeProcessor) bool {
	element := r.element as PsiElement
	name := r.element.name()
	file := r.containing_file or { return true }

	if parent_list := element.parent_of_type(.selective_import_list) {
		if spec := parent_list.parent_of_type(.import_spec) {
			if spec is ImportSpec {
				if found := file.resolve_symbol_in_import_spec(spec, name) {
					return processor.execute(found)
				}
				return true
			}
		}
	}

	if resolved := file.resolve_selective_import_symbol(name) {
		if !processor.execute(resolved) {
			return false
		}
	}
	return true
}

// process_os_module feeds the os module to the processor, since a shell script has it imported implicitly.
pub fn (r &SubResolver) process_os_module(mut processor PsiScopeProcessor) bool {
	file := r.containing_file or { return true }

	if !file.is_shell_script() {
		return true
	}

	// In shell scripts OS module is imported implicitly, so we need to process it elements.
	os_elements := stubs_index.get_all_declarations_from_module('os', r.for_types)
	return r.process_elements(os_elements, mut processor)
}

// process_owner_generic_ts feeds the generic parameters of the receiver's type to the processor.
pub fn (r &SubResolver) process_owner_generic_ts(mut processor PsiScopeProcessor) bool {
	element := r.element()
	if element.text_length() != 1 {
		// for now V only support single char generic parameters
		return true
	}

	method := element.parent_of_type(.function_declaration) or { return true }
	if method is FunctionOrMethodDeclaration {
		receiver := method.receiver() or { return true }

		if receiver.is_parent_of(element) {
			return true
		}

		receiver_type := types.unwrap_alias_type(types.unwrap_pointer_type(receiver.get_type()))
		if receiver_type is types.GenericInstantiationType {
			inner := receiver_type.inner
			inner_name := inner.qualified_name()
			elements := stubs_index.get_any_elements_by_name(inner_name)
			if elements.len == 0 {
				return true
			}

			for resolved in elements {
				if resolved is GenericParametersOwner {
					params := resolved.generic_parameters() or { continue }
					parameters := params.parameters()
					for param in parameters {
						if !processor.execute(param) {
							return false
						}
					}
				}
			}
		}
	}

	return true
}
