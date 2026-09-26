// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct ImportSpec {
	PsiElementImpl
}

fn (_ &ImportSpec) stub() {}

// is_public always returns true: an import spec has no visibility modifier of its own.
pub fn (_ &ImportSpec) is_public() bool {
	return true
}

fn (n &ImportSpec) identifier_text_range() TextRange {
	identifier := n.identifier() or { return TextRange{} }
	return identifier.text_range()
}

fn (n &ImportSpec) identifier() ?PsiElement {
	last_part := n.last_part()?
	if last_part is ImportName {
		return last_part
	}
	return none
}

fn (n &ImportSpec) name() string {
	return n.import_name()
}

// qualified_name returns the import path as written in source.
pub fn (n &ImportSpec) qualified_name() string {
	path := n.path() or { return '' }
	return path.get_text()
}

// alias returns the alias node of the import, or none when it has none.
pub fn (n ImportSpec) alias() ?PsiElement {
	return n.find_child_by_type_or_stub(.import_alias)
}

// path returns the import path node, or none when the import is malformed.
pub fn (n ImportSpec) path() ?PsiElement {
	return n.find_child_by_type_or_stub(.import_path)
}

// last_part returns the last segment of the import path, the one naming the imported module.
pub fn (n ImportSpec) last_part() ?PsiElement {
	path := n.path()?
	return path.last_child_or_stub()
}

// import_name returns the name the import is bound to: its alias when it has one, otherwise the last path segment.
pub fn (n ImportSpec) import_name() string {
	if alias := n.alias() {
		if identifier := alias.last_child_or_stub() {
			return identifier.get_text()
		}
	}

	if last_part := n.last_part() {
		return last_part.get_text()
	}

	return ''
}

// alias_name returns the name of the import alias, or an empty string when there is none.
pub fn (n ImportSpec) alias_name() string {
	if alias := n.alias() {
		if identifier := alias.last_child() {
			return identifier.get_text()
		}
	}

	return ''
}

// resolve_directory returns the module root directory the import resolves to, or an empty string when it cannot be resolved.
pub fn (n ImportSpec) resolve_directory() string {
	fqn := n.qualified_name()
	if fqn == '' {
		return ''
	}

	return stubs_index.get_module_root(fqn)
}

// selective_list returns the list of selectively imported names, or none for a plain import.
pub fn (n &ImportSpec) selective_list() ?&SelectiveImportList {
	list := n.find_child_by_type_or_stub(.selective_import_list)?
	if list is SelectiveImportList {
		return list
	}
	return none
}
