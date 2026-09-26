// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import tree_sitter_v.bindings

// create_stub builds the stub of one element, carrying the name, the ranges and the
// doc comment the index and the PSI layer need. An element with no stub type of its
// own returns none.
pub fn (s &StubbedElementType) create_stub(element PsiElement, parent_stub &StubBase, module_fqn string) ?&StubBase {
	if element is FunctionOrMethodDeclaration {
		text_range := element.text_range()
		identifier_text_range := element.identifier_text_range()
		comment := element.doc_comment()

		mut receiver_type := s.get_receiver_type(element)
		if receiver_type != '' {
			if module_fqn != '' {
				receiver_type = module_fqn + '.' + receiver_type
			}
		}

		is_method := receiver_type != ''
		stub_type := if is_method {
			StubType.method_declaration
		} else {
			StubType.function_declaration
		}

		fingerprint := if is_method {
			element.fingerprint()
		} else {
			''
		}

		return new_stub_base(parent_stub, stub_type, element.name(), identifier_text_range,
			text_range,
			comment:    comment
			receiver:   receiver_type
			additional: fingerprint
		)
	}

	if element is StaticMethodDeclaration {
		text_range := element.text_range()
		identifier_text_range := element.identifier_text_range()
		comment := element.doc_comment()

		mut receiver_type := s.get_receiver_type(element)
		if receiver_type != '' {
			if module_fqn != '' {
				receiver_type = module_fqn + '.' + receiver_type
			}
		}

		return new_stub_base(parent_stub, .static_method_declaration, element.name(),
			identifier_text_range, text_range,
			comment:  comment
			receiver: receiver_type
		)
	}

	if element is StructDeclaration {
		text_range := element.text_range()
		identifier_text_range := element.identifier_text_range()
		comment := element.doc_comment()
		name := if element.is_attribute() {
			element.name() + 'Attribute'
		} else {
			element.name()
		}
		return new_stub_base(parent_stub, .struct_declaration, name, identifier_text_range,
			text_range,
			comment: comment
		)
	}

	if element is InterfaceDeclaration {
		return declaration_stub(element, parent_stub, .interface_declaration)
	}

	if element is InterfaceMethodDeclaration {
		return declaration_stub(element, parent_stub, .interface_method_declaration,
			additional: element.fingerprint()
		)
	}

	if element is StaticReceiver {
		return declaration_stub(element, parent_stub, .static_receiver, include_text: true)
	}

	if element is Receiver {
		return declaration_stub(element, parent_stub, .receiver, include_text: true)
	}

	if element is Signature {
		return text_based_stub(element, parent_stub, .signature)
	}

	if element is ParameterList {
		return text_based_stub(element, parent_stub, .parameter_list)
	}

	if element is ParameterDeclaration {
		return declaration_stub(element, parent_stub, .parameter_declaration, include_text: true)
	}

	if element is EnumDeclaration {
		return declaration_stub(element, parent_stub, .enum_declaration)
	}

	if element is EnumFieldDeclaration {
		if expression := element.last_child() {
			text := expression.get_text()
			return declaration_stub(element, parent_stub, .enum_field_definition, additional: text)
		}
		return declaration_stub(element, parent_stub, .enum_field_definition)
	}

	if element is FieldDeclaration {
		return declaration_stub(element, parent_stub, .field_declaration)
	}

	if element is ConstantDefinition {
		if expression := element.last_child() {
			text := expression.get_text()
			return declaration_stub(element, parent_stub, .constant_declaration, additional: text)
		}
		return declaration_stub(element, parent_stub, .constant_declaration)
	}

	if element is TypeAliasDeclaration {
		return declaration_stub(element, parent_stub, .type_alias_declaration)
	}

	if element is StructFieldScope {
		return text_based_stub(element, parent_stub, .struct_field_scope)
	}

	if element is Attributes {
		text_range := element.text_range()
		return new_stub_base(parent_stub, .attributes, '', text_range, text_range)
	}

	if element is Attribute {
		return text_based_stub(element, parent_stub, .attribute)
	}

	if element is AttributeExpression {
		return text_based_stub(element, parent_stub, .attribute_expression)
	}

	if element is ValueAttribute {
		return text_based_stub(element, parent_stub, .value_attribute)
	}

	if element is VisibilityModifiers {
		return text_based_stub(element, parent_stub, .visibility_modifiers)
	}

	if element is ModuleClause {
		return declaration_stub(element, parent_stub, .module_clause)
	}

	node_type := element.node().type_name
	if node_is_type(node_type) {
		stub_type := node_type_to_stub_type(node_type)
		return text_based_stub(element, parent_stub, stub_type)
	}

	if element is ImportSpec {
		return declaration_stub(element, parent_stub, .import_spec, include_text: true)
	}

	if node_type in [
		.import_list,
		.import_declaration,
		.import_path,
		.import_name,
		.import_alias,
		.selective_import_list,
	] {
		stub_type := node_type_to_stub_type(node_type)
		return text_based_stub(element, parent_stub, stub_type,
			include_text: node_type !in [
				.import_list,
				.import_declaration,
				.selective_import_list,
			]
		)
	}

	if element is ReferenceExpression {
		return text_based_stub(element, parent_stub, .reference_expression)
	}

	if element is GenericParameters {
		return text_based_stub(element, parent_stub, .generic_parameters)
	}

	if element is GenericParameter {
		return declaration_stub(element, parent_stub, .generic_parameter)
	}

	if element is GlobalVarDefinition {
		return declaration_stub(element, parent_stub, .global_variable)
	}

	if element is EmbeddedDefinition {
		return declaration_stub(element, parent_stub, .embedded_definition)
	}

	return none
}

@[params]
struct StubParams {
pub:
	include_text bool
	additional   string
}

// declaration_stub builds the stub of a named declaration, taking the name, the
// ranges and the doc comment from the element itself.
@[inline]
pub fn declaration_stub(element PsiNamedElement, parent_stub &StubElement, stub_type StubType, params StubParams) ?&StubBase {
	text_range := (element as PsiElement).text_range()
	identifier_text_range := element.identifier_text_range()
	return new_stub_base(parent_stub, stub_type, element.name(), identifier_text_range, text_range,
		comment:    if element is PsiDocCommentOwner { element.doc_comment() } else { '' }
		text:       if params.include_text { (element as PsiElement).get_text() } else { '' }
		additional: params.additional
	)
}

@[params]
struct TestStubParams {
pub:
	include_text bool = true
}

// text_based_stub builds the stub of an element that has no name of its own, so the
// text range is all it carries.
@[inline]
pub fn text_based_stub(element PsiElement, parent_stub &StubElement, stub_type StubType, params TestStubParams) ?&StubBase {
	text_range := element.text_range()
	return new_stub_base(parent_stub, stub_type, '', text_range, text_range,
		text: if params.include_text { element.get_text() } else { '' }
	)
}

// node_is_type reports whether a tree-sitter node type names a type.
@[inline]
pub fn node_is_type(type_name bindings.NodeType) bool {
	return type_name in [
		.plain_type,
		.type_reference_expression,
		.qualified_type,
		.pointer_type,
		.wrong_pointer_type,
		.array_type,
		.fixed_array_type,
		.function_type,
		.generic_type,
		.map_type,
		.channel_type,
		.shared_type,
		.thread_type,
		.multi_return_type,
		.option_type,
		.result_type,
		.type_parameters,
	]
}
