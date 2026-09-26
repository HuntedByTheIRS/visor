// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// find_function returns the function or method named name, or none.
pub fn (_ &SubResolver) find_function(stub_index StubIndex, name string) ?&FunctionOrMethodDeclaration {
	found := stub_index.get_elements_by_name(.functions, name)
	if found.len != 0 {
		first := found.first()
		if first is FunctionOrMethodDeclaration {
			return first
		}
	}
	return none
}

// find_struct returns the struct named name, or none.
pub fn (_ &SubResolver) find_struct(stub_index StubIndex, name string) ?&StructDeclaration {
	found := stub_index.get_elements_by_name(.structs, name)
	if found.len != 0 {
		first := found.first()
		if first is StructDeclaration {
			return first
		}
	}
	return none
}

// find_interface returns the interface named name, or none.
pub fn (_ &SubResolver) find_interface(stub_index StubIndex, name string) ?&InterfaceDeclaration {
	found := stub_index.get_elements_by_name(.interfaces, name)
	if found.len != 0 {
		first := found.first()
		if first is InterfaceDeclaration {
			return first
		}
	}
	return none
}

// find_enum returns the enum named name, or none.
pub fn (_ &SubResolver) find_enum(stub_index StubIndex, name string) ?&EnumDeclaration {
	found := stub_index.get_elements_by_name(.enums, name)
	if found.len != 0 {
		first := found.first()
		if first is EnumDeclaration {
			return first
		}
	}
	return none
}

// find_constant returns the constant named name, or none.
pub fn (_ &SubResolver) find_constant(stub_index StubIndex, name string) ?&ConstantDefinition {
	found := stub_index.get_elements_by_name(.constants, name)
	if found.len != 0 {
		first := found.first()
		if first is ConstantDefinition {
			return first
		}
	}
	return none
}

// find_type_alias returns the type alias named name, or none.
pub fn (_ &SubResolver) find_type_alias(stub_index StubIndex, name string) ?&TypeAliasDeclaration {
	found := stub_index.get_elements_by_name(.type_aliases, name)
	if found.len != 0 {
		first := found.first()
		if first is TypeAliasDeclaration {
			return first
		}
	}
	return none
}

// find_global_variable returns the global variable named name, or none.
pub fn (_ &SubResolver) find_global_variable(stub_index StubIndex, name string) ?&GlobalVarDefinition {
	found := stub_index.get_elements_by_name(.global_variables, name)
	if found.len != 0 {
		first := found.first()
		if first is GlobalVarDefinition {
			return first
		}
	}
	return none
}

// find_attribute returns the struct that backs the attribute named name, or none.
pub fn (_ &SubResolver) find_attribute(stub_index StubIndex, name string) ?&StructDeclaration {
	found := stub_index.get_elements_by_name(.attributes, name)
	if found.len != 0 {
		first := found.first()
		if first is StructDeclaration {
			return first
		}
	}
	return none
}

// resolve_attribute resolves the reference against the registered attributes.
pub fn (r &SubResolver) resolve_attribute(mut processor PsiScopeProcessor) bool {
	element := r.element()
	if element is PsiNamedElement {
		if attr := r.find_attribute(stubs_index, element.name()) {
			if !processor.execute(attr) {
				return false
			}
		}
	}

	return true
}

// find_element returns the first element with the given fully qualified name, or none.
pub fn find_element(fqn string) ?PsiElement {
	found := stubs_index.get_any_elements_by_name(fqn)
	if found.len != 0 {
		return found.first()
	}
	return none
}

// find_interface returns the interface with the given fully qualified name, or none.
pub fn find_interface(fqn string) ?&InterfaceDeclaration {
	found := stubs_index.get_elements_by_name(.interfaces, fqn)
	if found.len != 0 {
		first := found.first()
		if first is InterfaceDeclaration {
			return first
		}
	}
	return none
}

// find_struct returns the struct with the given fully qualified name, or none.
pub fn find_struct(fqn string) ?&StructDeclaration {
	found := stubs_index.get_elements_by_name(.structs, fqn)
	if found.len != 0 {
		first := found.first()
		if first is StructDeclaration {
			return first
		}
	}
	return none
}

// find_alias returns the type alias with the given fully qualified name, or none.
pub fn find_alias(fqn string) ?&TypeAliasDeclaration {
	found := stubs_index.get_elements_by_name(.type_aliases, fqn)
	if found.len != 0 {
		first := found.first()
		if first is TypeAliasDeclaration {
			return first
		}
	}
	return none
}
