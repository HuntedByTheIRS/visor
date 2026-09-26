// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

// create_psi builds the PSI element a stub stands for, so a handler that expects an
// AST node also works on a stub. Node types with no element of their own fall back
// to the plain element node.
pub fn (_ &StubbedElementType) create_psi(stub &StubBase) ?PsiElement {
	stub_type := stub.stub_type
	base_psi := new_psi_node_from_stub(stub.id, stub.stub_list)

	if stub_type == .function_declaration || stub_type == .method_declaration {
		return FunctionOrMethodDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .static_method_declaration {
		return StaticMethodDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .static_receiver {
		return StaticReceiver{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .receiver {
		return Receiver{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .signature {
		return Signature{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .parameter_list {
		return ParameterList{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .parameter_declaration {
		return ParameterDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .type_reference_expression {
		return TypeReferenceExpression{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .struct_declaration {
		return StructDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .interface_declaration {
		return InterfaceDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .interface_method_declaration {
		return InterfaceMethodDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .enum_declaration {
		return EnumDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .enum_field_definition {
		return EnumFieldDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .field_declaration {
		return FieldDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .struct_field_scope {
		return StructFieldScope{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .constant_declaration {
		return ConstantDefinition{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .type_alias_declaration {
		return TypeAliasDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .attributes {
		return Attributes{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .attribute {
		return Attribute{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .attribute_expression {
		return AttributeExpression{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .value_attribute {
		return ValueAttribute{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .plain_type {
		return PlainType{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .qualified_type {
		return QualifiedType{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .visibility_modifiers {
		return VisibilityModifiers{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .import_list {
		return ImportList{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .import_declaration {
		return ImportDeclaration{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .import_spec {
		return ImportSpec{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .import_path {
		return ImportPath{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .import_alias {
		return ImportAlias{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .selective_import_list {
		return SelectiveImportList{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .module_clause {
		return ModuleClause{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .reference_expression {
		return ReferenceExpression{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .generic_parameters {
		return GenericParameters{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .generic_parameter {
		return GenericParameter{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .global_variable {
		return GlobalVarDefinition{
			PsiElementImpl: base_psi
		}
	}
	if stub_type == .embedded_definition {
		return EmbeddedDefinition{
			PsiElementImpl: base_psi
		}
	}
	return base_psi
}
