// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module types

import strings

pub struct FunctionType {
	BaseType
pub:
	params    []Type
	result    Type
	no_result bool
}

// new_function_type returns a function type built from the given parameters and result.
pub fn new_function_type(module_name string, params []Type, result Type, no_result bool) &FunctionType {
	return &FunctionType{
		params:      params
		result:      result
		no_result:   no_result
		module_name: module_name
	}
}

// name returns the function type in source form, omitting the result when the function has none.
pub fn (s &FunctionType) name() string {
	mut sb := strings.new_builder(20)
	sb.write_string('fn (')
	for index, param in s.params {
		sb.write_string(param.name())
		if index < s.params.len - 1 {
			sb.write_string(', ')
		}
	}
	sb.write_string(')')
	if !s.no_result {
		sb.write_string(' ')
		sb.write_string(s.result.name())
	}

	return sb.str()
}

// qualified_name returns the function type with each parameter and the result type fully qualified.
pub fn (s &FunctionType) qualified_name() string {
	mut sb := strings.new_builder(20)
	sb.write_string('fn (')
	for index, param in s.params {
		sb.write_string(param.qualified_name())
		if index < s.params.len - 1 {
			sb.write_string(', ')
		}
	}
	sb.write_string(')')
	if !s.no_result {
		sb.write_string(' ')
		sb.write_string(s.result.qualified_name())
	}

	return sb.str()
}

// readable_name returns the function type with names stripped of their module, for messages shown to a user.
pub fn (s &FunctionType) readable_name() string {
	mut sb := strings.new_builder(20)
	sb.write_string('fn (')
	for index, param in s.params {
		sb.write_string(param.readable_name())
		if index < s.params.len - 1 {
			sb.write_string(', ')
		}
	}
	sb.write_string(')')
	if !s.no_result {
		sb.write_string(' ')
		sb.write_string(s.result.readable_name())
	}

	return sb.str()
}

// accept lets the visitor enter this type and then each parameter and the result type.
pub fn (s &FunctionType) accept(mut visitor TypeVisitor) {
	if !visitor.enter(s) {
		return
	}

	for param in s.params {
		param.accept(mut visitor)
	}

	s.result.accept(mut visitor)
}

// substitute_generics returns a new function type with the generic parameters replaced according to name_map.
pub fn (s &FunctionType) substitute_generics(name_map map[string]Type) Type {
	params := s.params.map(it.substitute_generics(name_map))
	result := s.result.substitute_generics(name_map)
	return new_function_type(s.module_name, params, result, s.no_result)
}
