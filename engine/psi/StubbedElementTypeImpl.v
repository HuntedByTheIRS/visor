// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.utils
import tree_sitter_v.bindings

pub enum StubType as u8 {
	root
	function_declaration
	method_declaration
	static_method_declaration
	static_receiver
	receiver
	signature
	parameter_list
	parameter_declaration
	struct_declaration
	interface_declaration
	interface_method_declaration
	enum_declaration
	field_declaration
	struct_field_scope
	enum_field_definition
	constant_declaration
	type_alias_declaration
	attributes
	attribute
	attribute_expression
	value_attribute
	// types
	plain_type
	type_reference_expression
	qualified_type
	pointer_type
	wrong_pointer_type
	array_type
	fixed_array_type
	function_type
	generic_type
	map_type
	channel_type
	shared_type
	thread_type
	multi_return_type
	option_type
	result_type
	type_parameters
	//
	visibility_modifiers
	import_list
	import_declaration
	import_spec
	import_path
	import_name
	import_alias
	selective_import_list
	module_clause
	reference_expression
	generic_parameters
	generic_parameter
	global_variable
	embedded_definition
}

// node_type_to_stub_type maps a tree-sitter node type onto the stub type built from
// it. A node type with no stub of its own maps to root.
pub fn node_type_to_stub_type(typ bindings.NodeType) StubType {
	return match typ {
		.function_declaration { .function_declaration }
		.receiver { .receiver }
		.static_method_declaration { .static_method_declaration }
		.static_receiver { .static_receiver }
		.signature { .signature }
		.parameter_list { .parameter_list }
		.parameter_declaration { .parameter_declaration }
		.struct_declaration { .struct_declaration }
		.interface_declaration { .interface_declaration }
		.interface_method_definition { .interface_method_declaration }
		.struct_field_declaration { .field_declaration }
		.const_definition { .constant_declaration }
		.type_declaration { .type_alias_declaration }
		.enum_declaration { .enum_declaration }
		.enum_field_definition { .enum_field_definition }
		.struct_field_scope { .struct_field_scope }
		.attributes { .attributes }
		.attribute { .attribute }
		.attribute_expression { .attribute_expression }
		.value_attribute { .value_attribute }
		// types
		.plain_type { .plain_type }
		.type_reference_expression { .type_reference_expression }
		.qualified_type { .qualified_type }
		.pointer_type { .pointer_type }
		.wrong_pointer_type { .wrong_pointer_type }
		.array_type { .array_type }
		.fixed_array_type { .fixed_array_type }
		.function_type { .function_type }
		.generic_type { .generic_type }
		.map_type { .map_type }
		.channel_type { .channel_type }
		.shared_type { .shared_type }
		.thread_type { .thread_type }
		.multi_return_type { .multi_return_type }
		.option_type { .option_type }
		.result_type { .result_type }
		.type_parameters { .type_parameters }
		// types end
		.visibility_modifiers { .visibility_modifiers }
		.import_list { .import_list }
		.import_declaration { .import_declaration }
		.import_spec { .import_spec }
		.import_path { .import_path }
		.import_name { .import_name }
		.import_alias { .import_alias }
		.selective_import_list { .selective_import_list }
		.module_clause { .module_clause }
		.reference_expression { .reference_expression }
		.generic_parameters { .generic_parameters }
		.generic_parameter { .generic_parameter }
		.global_var_definition { .global_variable }
		.embedded_definition { .embedded_definition }
		else { .root }
	}
}

pub struct StubbedElementType {}

// index_stub records the occurrences a stub contributes to the index. Stubs from a
// _test.v file and functions named test_* are skipped, since neither is reachable
// from another file.
pub fn (_ &StubbedElementType) index_stub(stub &StubBase, mut sink IndexSink) {
	if stub.stub_list.path.ends_with('_test.v') {
		return
	}

	if stub.stub_type == .module_clause {
		sink.occurrence(.modules_fingerprint, stub.name())
		return
	}

	if stub.stub_type == .function_declaration {
		name := stub.name()
		if name.starts_with('test_') {
			return
		}

		sink.occurrence(.functions, name)
	}

	if stub.stub_type == .method_declaration {
		receiver := stub.receiver()
		sink.occurrence(.methods, receiver)
		sink.occurrence(.methods_fingerprint, stub.additional)
	}

	if stub.stub_type == .static_method_declaration {
		receiver := stub.receiver()
		sink.occurrence(.static_methods, receiver)
	}

	if stub.stub_type == .struct_declaration {
		name := stub.name()
		if name.ends_with('Attribute') {
			// convert DeprecatedAfter to deprecated_after
			clear_name := utils.pascal_case_to_snake_case(name.trim_string_right('Attribute'))
			sink.occurrence(.attributes, clear_name)
			return
		}

		sink.occurrence(.structs, name)
	}

	if stub.stub_type == .interface_declaration {
		sink.occurrence(.interfaces, stub.name())
	}

	if stub.stub_type == .interface_method_declaration {
		sink.occurrence(.interface_methods_fingerprint, stub.additional)
	}

	if stub.stub_type == .enum_declaration {
		sink.occurrence(.enums, stub.name())
	}

	if stub.stub_type == .constant_declaration {
		sink.occurrence(.constants, stub.name())
	}

	if stub.stub_type == .type_alias_declaration {
		sink.occurrence(.type_aliases, stub.name())
	}

	if stub.stub_type == .global_variable {
		sink.occurrence(.global_variables, stub.name())
	}

	if stub.stub_type == .field_declaration {
		if parent := stub.parent_stub() {
			if parent.stub_type() == .struct_declaration {
				sink.occurrence(.fields_fingerprint, stub.name)
			} else if parent.stub_type() == .interface_declaration {
				sink.occurrence(.interface_fields_fingerprint, stub.name)
			}
		}
	}
}

// get_receiver_type returns the receiver type of a method, with a leading & and any
// generic arguments dropped. An element that is not a method returns an empty string.
pub fn (_ &StubbedElementType) get_receiver_type(element PsiNamedElement) string {
	typ := if element is FunctionOrMethodDeclaration {
		receiver := element.receiver() or { return '' }
		receiver.type_element() or { return '' }
	} else if element is StaticMethodDeclaration {
		receiver := element.receiver() or { return '' }
		PsiElement(receiver.PsiElementImpl)
	} else {
		return ''
	}

	text := typ.get_text().trim_string_left('&')

	if text.contains('[') && !text.contains('map[') && !text.starts_with('[') {
		// Foo[T] -> Foo
		return text.all_before('[')
	}

	return text
}
