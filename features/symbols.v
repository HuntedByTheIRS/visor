// symbols.v is the outline of one buffer: what a file declares, in the order it
// declares it, with the members of a type under the type.
//
// The walk reads the parse the session holds for that buffer, so a file nobody
// has saved is outlined as it stands. Nothing here needs the index: a struct's
// fields and a struct's methods are declarations in the same file, and where a
// member sits is a fact about the text rather than about what the name means.
//
// A method is a child of the type it is declared on rather than a sibling of
// it. That is the one thing the outline knows that the text does not say: V
// writes `fn (p Point) scale()`, and the reader looking for what a Point can do
// wants it under Point. A method whose receiver type this file does not declare
// stays at the top level, named with its receiver.
module features

import engine.psi

// SymbolKind is the protocol's numbering, so a handler can put the value
// straight on the wire. The names are the spec's; `struct_`, `enum_` and
// `interface_` carry the underscore V needs to keep them out of its keyword
// list.
pub enum SymbolKind {
	module      = 2
	class       = 5
	method      = 6
	field       = 8
	enum_       = 10
	interface_  = 11
	function    = 12
	variable    = 13
	constant    = 14
	enum_member = 22
	struct_     = 23
}

// DocSymbol is one entry of an outline. The offsets are bytes into the text the
// file was parsed from; the protocol counts lines and UTF-16 code units, so the
// conversion belongs to the caller that has the text.
pub struct DocSymbol {
pub:
	kind SymbolKind
	name string
	// name_start and name_end cover the name itself, which is what a client
	// selects when the entry is picked.
	name_start int
	name_end   int
	// start and end cover the whole declaration, attributes and body included,
	// which is what a client folds or reveals.
	start int
	end   int
	// detail is what the declaration says after its name when that reads as
	// more information: a signature, a field's type, an enum member's value. A
	// declaration whose tail is a body has none.
	detail string
pub mut:
	children []DocSymbol
}

// document_symbols is the outline of one buffer: every declaration the file
// makes, in the order it makes them, with the members of a type under the type.
//
// A struct, an interface and an enum each carry members, so the walk looks
// inside three shapes rather than one. Everything else is a leaf.
pub fn document_symbols(file &psi.PsiFile) []DocSymbol {
	text := file.source_text
	mut symbols := []DocSymbol{}
	mut containers := map[string]int{}
	for child in file.root.children() {
		base := child
		if child is psi.ModuleClause {
			if symbol := named_symbol(base, .module, text) {
				symbols << symbol
			}
			continue
		}
		if child is psi.StructDeclaration {
			if symbol := named_symbol(base, .struct_, text) {
				containers[symbol.name] = symbols.len
				symbols << with_members(symbol, field_symbols(child.own_fields(), text))
			}
			continue
		}
		if child is psi.InterfaceDeclaration {
			if symbol := named_symbol(base, .interface_, text) {
				containers[symbol.name] = symbols.len
				members := interface_member_symbols(child, text)
				symbols << with_members(symbol, members)
			}
			continue
		}
		if child is psi.EnumDeclaration {
			if symbol := named_symbol(base, .enum_, text) {
				containers[symbol.name] = symbols.len
				symbols << with_members(symbol, field_symbols(child.fields(), text))
			}
			continue
		}
		if child is psi.FunctionOrMethodDeclaration {
			if child.is_method() {
				// Second pass: a method needs the type it belongs to, and the
				// type may be declared below it in the file.
				continue
			}
			if symbol := named_symbol(base, .function, text) {
				symbols << symbol
			}
			continue
		}
		if child is psi.ConstantDeclaration {
			for constant in child.constants() {
				if symbol := named_symbol(constant, .constant, text) {
					symbols << symbol
				}
			}
			continue
		}
		if child is psi.TypeAliasDeclaration {
			if symbol := named_symbol(base, .class, text) {
				symbols << symbol
			}
			continue
		}
		if child.node().type_name == .global_var_declaration {
			for nested in child.children() {
				definition := nested
				if nested is psi.GlobalVarDefinition {
					if symbol := named_symbol(definition, .variable, text) {
						symbols << symbol
					}
				}
			}
		}
	}
	return attach_methods(file.root, text, symbols, containers)
}

// attach_methods hangs each method under the type its receiver names, and keeps
// a method whose type is not declared here at the top level.
//
// The receiver is read out of the text rather than inferred: `Point`, `&Point`,
// `mut Point` and `Point[T]` are four spellings of the same type, and the name
// in the declaration is the part they agree on.
fn attach_methods(root psi.PsiElement, text string, symbols []DocSymbol, containers map[string]int) []DocSymbol {
	mut result := symbols.clone()
	for child in root.children() {
		if child is psi.FunctionOrMethodDeclaration {
			if !child.is_method() {
				continue
			}
			declaration := child
			receiver := receiver_type_name(declaration)
			mut symbol := named_symbol(declaration, .method, text) or { continue }
			if receiver != '' {
				if index := containers[receiver] {
					container := result[index]
					mut members := container.children.clone()
					members << symbol
					result[index] = with_members(container, members)
					continue
				}
				// the receiver's type is declared somewhere this file cannot
				// see, so the method is named with it instead of being dropped.
				symbol = DocSymbol{
					...symbol
					detail: '(${receiver}) ${symbol.detail}'
				}
			}
			result << symbol
		}
	}
	return result
}

// receiver_type_name is the name of the type a method is declared on, without
// the reference marker or the type parameters around it.
fn receiver_type_name(declaration psi.FunctionOrMethodDeclaration) string {
	receiver := declaration.receiver() or { return '' }
	element := receiver.type_element() or { return '' }
	return bare_type_name(element.get_text())
}

// bare_type_name strips what a receiver can wrap a type name in: `&Point` is
// Point, `Point[T]` is Point, and a qualified name keeps its last segment.
fn bare_type_name(text string) string {
	mut name := text.trim_space().trim_string_left('&').trim_space()
	at := name.index_u8(`[`)
	if at >= 0 {
		name = name[..at]
	}
	dot := name.last_index_u8(`.`)
	if dot >= 0 {
		name = name[dot + 1..]
	}
	return name.trim_space()
}

// field_symbols turns the members of a container into outline entries.
fn field_symbols(members []psi.PsiElement, text string) []DocSymbol {
	mut symbols := []DocSymbol{cap: members.len}
	for member in members {
		kind := member_kind(member)
		if symbol := named_symbol(member, kind, text) {
			symbols << symbol
		}
	}
	return symbols
}

// interface_member_symbols is an interface's own fields and its methods, in the
// order they are declared.
//
// The two lists are separate in the element layer, so they are put back
// together by offset: an interface writes its fields and its methods in any
// order, and an outline that listed the methods first would not read like the
// file it describes.
fn interface_member_symbols(declaration psi.InterfaceDeclaration, text string) []DocSymbol {
	mut members := []DocSymbol{}
	members << field_symbols(declaration.own_fields(), text)
	for method in declaration.methods() {
		if symbol := named_symbol(method, .method, text) {
			members << symbol
		}
	}
	members.sort_with_compare(fn (a &DocSymbol, b &DocSymbol) int {
		if a.start == b.start {
			return 0
		}
		return if a.start < b.start { -1 } else { 1 }
	})
	return members
}

// member_kind says what a declaration inside a type is: a method if it has a
// signature and no value, an enum member if it is one, and a field otherwise.
//
// The element kinds are what decides. The node kind of a stub-backed element is
// the type of the declaration, so an enum member reads as an enum member rather
// than as the struct field it looks like in the tree.
fn member_kind(element psi.PsiElement) SymbolKind {
	if element is psi.InterfaceMethodDeclaration {
		return .method
	}
	if element is psi.EnumFieldDeclaration {
		return .enum_member
	}
	return .field
}

// named_symbol builds one entry from a declaration: its name and the span of
// that name, the span of the declaration, and whatever it says after the name.
//
// A declaration with no name is not an entry. The tree has nodes like that, and
// an outline is a list of names.
fn named_symbol(element psi.PsiElement, kind SymbolKind, text string) ?DocSymbol {
	base := element
	start := element_start(base)
	mut stop := element_end(base)
	if element !is psi.PsiNamedElement {
		return none
	}
	named := element as psi.PsiNamedElement
	name := named.name()
	if name == '' {
		return none
	}
	name_start, name_end := span_offsets(text, named.identifier_text_range())
	if name_start < 0 || name_end <= name_start {
		return none
	}
	if stop < name_end {
		stop = name_end
	}
	return DocSymbol{
		kind:       kind
		name:       name
		name_start: name_start
		name_end:   name_end
		start:      start
		end:        stop
		detail:     detail_of(text, name_end, stop)
	}
}

// with_members returns a symbol carrying the members found under it.
fn with_members(symbol DocSymbol, members []DocSymbol) DocSymbol {
	mut result := symbol
	result.children = members
	return result
}

// detail_of is what a declaration says after its name, up to the brace that
// opens its body.
//
// A struct, an enum or an interface says nothing before its brace, so their
// detail is empty rather than a restatement of their own body. A signature, a
// field's type and the value of an enum member or a constant are the cases this
// is for.
fn detail_of(text string, name_end int, end int) string {
	if name_end < 0 || end <= name_end || end > text.len {
		return ''
	}
	mut body := text[name_end..end]
	brace := body.index_u8(`{`)
	if brace >= 0 {
		body = body[..brace]
	}
	// a declaration can be indented and wrapped, and the detail is one line
	return collapse_whitespace(body)
}

// collapse_whitespace turns every run of whitespace into a single space and
// trims the ends, so a wrapped signature reads as one line.
fn collapse_whitespace(text string) string {
	mut out := []u8{cap: text.len}
	mut pending_space := false
	for ch in text {
		if ch == ` ` || ch == `\t` || ch == `\n` || ch == `\r` {
			pending_space = out.len > 0
			continue
		}
		if pending_space {
			out << ` `
			pending_space = false
		}
		out << ch
	}
	if out.len > detail_limit {
		return out[..detail_limit].bytestr().trim_space() + '...'
	}
	return out.bytestr()
}

// detail_limit keeps a signature to something an editor draws in one row.
const detail_limit = 80

// span_offsets turns a range from a parse into byte offsets. The parse counts
// lines from zero and columns in bytes, which is what a string index takes once
// the line starts have been walked.
fn span_offsets(text string, range psi.TextRange) (int, int) {
	return offset_of(text, range.line, range.column), offset_of(text, range.end_line, range.end_column)
}

// offset_of is the byte offset of a line and column, both counted from zero.
// A position past the end of a line clamps to the end of that line, so a range
// from a stale parse answers with a span inside the text rather than outside it.
fn offset_of(text string, line int, column int) int {
	mut offset := 0
	for current := 0; current < line; current++ {
		advance := text[offset..].index('\n') or { return text.len }
		offset += advance + 1
		if offset > text.len {
			return text.len
		}
	}
	newline := text[offset..].index('\n') or { text.len - offset }
	reach := if column > newline { newline } else { column }
	return offset + reach
}
