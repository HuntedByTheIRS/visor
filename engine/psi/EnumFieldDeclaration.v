// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

@[has_globals; translated]
module psi

import engine.parser
import engine.psi.types

__global enum_fields_cache = map[string]int{}

pub struct EnumFieldDeclaration {
	PsiElementImpl
}

// is_public always returns true: enum fields have no visibility of their own.
pub fn (_ &EnumFieldDeclaration) is_public() bool {
	return true
}

// doc_comment returns the comment above the field, with the leading slashes stripped.
pub fn (f &EnumFieldDeclaration) doc_comment() string {
	if stub := f.get_stub() {
		return stub.comment
	}

	if comment := f.find_child_by_type(.line_comment) {
		return comment.get_text().trim_string_left('//').trim(' \t')
	}

	return extract_doc_comment(f)
}

// identifier returns the name node of the field, or none when it has no name.
pub fn (f &EnumFieldDeclaration) identifier() ?PsiElement {
	return f.find_child_by_type(.identifier)
}

// identifier_text_range returns the range of the field's name, or an empty range when it has no name.
pub fn (f EnumFieldDeclaration) identifier_text_range() TextRange {
	if stub := f.get_stub() {
		return stub.identifier_text_range
	}

	identifier := f.identifier() or { return TextRange{} }
	return identifier.text_range()
}

// name returns the field's name.
pub fn (f &EnumFieldDeclaration) name() string {
	if stub := f.get_stub() {
		return stub.name
	}

	identifier := f.identifier() or { return '' }
	return identifier.get_text()
}

// get_type returns the type of the enum the field belongs to, or unknown_type when the field has no owner.
pub fn (f &EnumFieldDeclaration) get_type() types.Type {
	owner := f.owner() or { return types.unknown_type }
	return owner.get_type()
}

// fingerprint is the cache key for the field: its file, start point and owner-qualified name.
pub fn (f &EnumFieldDeclaration) fingerprint() string {
	owner := f.owner() or { return '' }
	file := f.containing_file() or { return '' }
	return '${file.path}:${f.node.start_point()}${owner.name()}.${f.name()}'
}

// value returns the value expression written after the field, or none when the field takes the next value.
pub fn (f &EnumFieldDeclaration) value() ?PsiElement {
	if stub := f.get_stub() {
		if stub.additional.len == 0 {
			return none
		}

		file := f.containing_file() or { return none }
		mut p := parser.Parser.new()
		defer { p.free() }
		res := p.parse_code(stub.additional)
		root := res.tree.root_node()
		first_child := root.first_child()?
		next_first_child := first_child.first_child()?
		synthetic_file := new_psi_file(file.path, res.tree, res.source_text)
		return create_element(next_first_child, synthetic_file)
	}

	return f.find_child_by_name('value')
}

// owner returns the enum the field is declared in, or none when it is not inside one.
pub fn (f &EnumFieldDeclaration) owner() ?&EnumDeclaration {
	if stub := f.get_stub() {
		if parent := stub.parent_of_type(.enum_declaration) {
			if is_valid_stub(parent) {
				if psi := parent.get_psi() {
					if psi is EnumDeclaration {
						return psi
					}
				}
			}
		}
		return none
	}

	// The local cannot be called `psi`: V 0.5.2 rejects a name that repeats a
	// module name in the project.
	enum_declaration := f.parent_of_type(.enum_declaration)?
	if enum_declaration is EnumDeclaration {
		return enum_declaration
	}

	return none
}

// value_presentation renders the value the way a user reads it: zero-padded
// binary for a flag enum, decimal otherwise, with the decimal value on request.
pub fn (f &EnumFieldDeclaration) value_presentation(with_dec_value bool) string {
	owner := f.owner() or { return '' }
	count_fields := owner.fields().len
	is_flag := owner.is_flag()

	value := f.get_value()
	if is_flag {
		mut bin := '0b' + f.add_padding('${value:b}', count_fields)
		if with_dec_value {
			bin += ' (${value})'
		}
		return bin
	}

	return value.str()
}

// get_value returns the field's numeric value, memoized by fingerprint.
pub fn (f &EnumFieldDeclaration) get_value() i64 {
	fingerprint := f.fingerprint()
	if value := enum_fields_cache[fingerprint] {
		return value
	}

	value := f.get_value_impl()
	enum_fields_cache[fingerprint] = value
	return value
}

fn (f &EnumFieldDeclaration) get_value_impl() i64 {
	owner := f.owner() or { return 0 }
	is_flag := owner.is_flag()

	if !is_flag {
		if value := f.value() {
			val := f.calculate_value(value)
			if f.stub_based() {
				if mut file := value.containing_file() {
					file.free()
				}
			}
			if val != none {
				return val
			}
		}
	}

	prev_field := f.prev_sibling_of_type(.enum_field_definition) or {
		return if is_flag { 1 } else { 0 }
	}
	if prev_field is EnumFieldDeclaration {
		prev_value := prev_field.get_value()
		if is_flag {
			return prev_value * 2
		}
		return prev_value + 1
	}
	return 0
}

fn (f &EnumFieldDeclaration) calculate_value(value PsiElement) ?i64 {
	if value is Literal {
		return value.value()
	}

	if value is UnaryExpression {
		if value.operator() == '-' {
			if expr := value.expression() {
				if val := f.calculate_value(expr) {
					return -val
				}
			}
		}
	}

	if value is BinaryExpression {
		operator := value.operator()
		if operator == '<<' {
			left := value.left()?
			right := value.right()?

			left_val := f.calculate_value(left)?
			right_val := f.calculate_value(right)?

			if left_val < 0 {
				// -1 << 1 is prohibited by V
				return none
			}

			return i64(u64(left_val) << right_val)
		}
	}

	return none
}

fn (_ EnumFieldDeclaration) add_padding(value string, size int) string {
	if size == -1 {
		return value
	}

	len := value.len
	if len >= size {
		return value
	}

	return '0'.repeat(size - len) + value
}

// stub is the marker method that lets the field be rebuilt from an index stub.
pub fn (_ EnumFieldDeclaration) stub() {}
