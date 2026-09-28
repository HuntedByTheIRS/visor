// workspace_symbols.v answers a search across the workspace: every declaration
// the index holds, matched against a query and ordered so the closest names
// come first.
//
// The candidates come from the index rather than from the open buffers, because
// that is what makes the search reach a file nobody has open. It carries two
// costs, and the lane says so where it is asked: a buffer with unsaved edits is
// searched as the file on disk still reads, and a declaration the index does not
// file cannot be found. Enum members are the second kind today: the index builds
// a stub for one and records no key for it, so a search lists the enum and not
// its members, while the outline reads the parse and lists both.

module features

import engine.psi

// WorkspaceSymbol is one declaration the index holds, in the shape a client can
// jump to: the file it is in, and where its name sits in that file.
//
// The name is carried as a range rather than as an offset because the index
// describes a text this process has not read. A range is a line and a column in
// the file, which is what the reply needs and what the index has.
pub struct WorkspaceSymbol {
pub:
	name string
	kind SymbolKind
	// container is the module the declaration belongs to: the second line a
	// client draws under the name, and how two same-named declarations are told
	// apart.
	container string
	path      string
	range     psi.TextRange
}

// element_path is the file an indexed element was declared in. The index holds
// a path per file, and an element built from a stub knows it.
pub fn element_path(element psi.PsiElement) ?string {
	file := element.containing_file() or { return none }
	if file.path == '' {
		return none
	}
	return file.path
}

// workspace_symbol_of builds the searchable entry for an indexed declaration.
//
// A search lists names a person can jump to, so a declaration with no name, no
// file and no place in it is not an entry. Everything else is: the index holds
// a field and a method beside the type that declares them, and hiding either
// would make the search the wrong size.
pub fn workspace_symbol_of(element psi.PsiElement, container string) ?WorkspaceSymbol {
	base := element
	if element !is psi.PsiNamedElement {
		return none
	}
	named := element as psi.PsiNamedElement
	name := named.name()
	if name == '' {
		return none
	}
	range := named.identifier_text_range()
	if range.line < 0 || range.end_column <= range.column {
		return none
	}
	file := element_path(base) or { return none }
	return WorkspaceSymbol{
		name:      name
		kind:      declaration_kind(base)
		container: container
		path:      file
		range:     range
	}
}

// declaration_kind is the protocol's kind for an indexed declaration. It reads
// the element's own type rather than guessing from the name, so a search result
// is drawn as what it is.
pub fn declaration_kind(element psi.PsiElement) SymbolKind {
	if element is psi.FunctionOrMethodDeclaration {
		if element.is_method() {
			return .method
		}
		return .function
	}
	if element is psi.StaticMethodDeclaration {
		return .method
	}
	if element is psi.StructDeclaration {
		return .struct_
	}
	if element is psi.InterfaceDeclaration {
		return .interface_
	}
	if element is psi.InterfaceMethodDeclaration {
		return .method
	}
	if element is psi.EnumDeclaration {
		return .enum_
	}
	if element is psi.EnumFieldDeclaration {
		return .enum_member
	}
	if element is psi.FieldDeclaration {
		return .field
	}
	if element is psi.ConstantDeclaration || element is psi.ConstantDefinition {
		return .constant
	}
	if element is psi.GlobalVarDefinition {
		return .variable
	}
	if element is psi.TypeAliasDeclaration {
		return .class
	}
	if element is psi.ModuleClause {
		return .module
	}
	return .variable
}

// symbol_identity is what makes two candidates the same declaration. The index
// files a declaration under more than one key, so the same name arrives several
// times, and a search that listed it once per key would look like a workspace
// with duplicates in it.
pub fn symbol_identity(symbol WorkspaceSymbol) string {
	return '${symbol.path}\t${symbol.range.line}\t${symbol.range.column}\t${symbol.name}'
}

// rank_symbols answers a query: the candidates that match, best first, at most
// limit of them.
//
// The order is what a person reads, so it goes exact name, name prefix, name
// that contains the query, then the query's characters in order. Within one
// rank the shorter name comes first, because a short name that matches is a
// stronger answer than a long one that happens to contain it.
pub fn rank_symbols(query string, candidates []WorkspaceSymbol, limit int) []WorkspaceSymbol {
	needle := query.trim_space().to_lower()
	mut matched := []WorkspaceSymbol{}
	for candidate in candidates {
		if symbol_rank(candidate.name, needle) >= 0 {
			matched << candidate
		}
	}
	matched.sort_with_compare(fn [needle] (a &WorkspaceSymbol, b &WorkspaceSymbol) int {
		left_rank := symbol_rank(a.name, needle)
		right_rank := symbol_rank(b.name, needle)
		if left_rank != right_rank {
			return if left_rank < right_rank { -1 } else { 1 }
		}
		if a.name.len != b.name.len {
			return if a.name.len < b.name.len { -1 } else { 1 }
		}
		if a.name != b.name {
			return if a.name < b.name { -1 } else { 1 }
		}
		if a.container != b.container {
			return if a.container < b.container { -1 } else { 1 }
		}
		if a.path != b.path {
			return if a.path < b.path { -1 } else { 1 }
		}
		return 0
	})
	if limit > 0 && matched.len > limit {
		return matched[..limit]
	}
	return matched
}

// symbol_rank is how well a name answers a query, or -1 when it does not. An
// empty query matches every name at the same rank, which is what makes a client
// that asks for nothing get the whole workspace in name order.
pub fn symbol_rank(name string, needle string) int {
	if needle == '' {
		return 4
	}
	lower := name.to_lower()
	if lower == needle {
		return 0
	}
	if lower.starts_with(needle) {
		return 1
	}
	if lower.contains(needle) {
		return 2
	}
	if letters_in_order(lower, needle) {
		return 3
	}
	return -1
}

// letters_in_order reports whether every character of the query appears in the
// name in the same order, which is what makes `wsym` find `workspace_symbol`.
// It is the last resort rather than the first, so a name that answers the query
// in its own letters is never buried under one that only spells it out.
fn letters_in_order(name string, needle string) bool {
	if needle == '' {
		return true
	}
	mut at := 0
	for name_char in name {
		if name_char == needle[at] {
			at++
			if at == needle.len {
				return true
			}
		}
	}
	return false
}
