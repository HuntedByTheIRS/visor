// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import time
import engine.utils
import engine.loglib
import engine.parser
import tree_sitter_v.bindings

@[heap]
pub struct PsiFile {
pub:
	path      string
	stub_list &StubList = unsafe { nil }
pub mut:
	tree        &bindings.Tree[bindings.NodeType] = unsafe { nil }
	source_text string
	root        PsiElement
}

// new_psi_file wraps a parsed tree and its source text in a file, and
// builds the root element.
pub fn new_psi_file(path string, tree &bindings.Tree[bindings.NodeType], source_text string) &PsiFile {
	// `root` is built after the file exists, so the literal can only carry a nil
	// interface. V 0.5.2 rejects a plain `nil` for an interface field and lets
	// only the cast through; the next line assigns the real element.
	mut file := &PsiFile{
		path:        path
		tree:        unsafe { tree }
		source_text: source_text
		stub_list:   unsafe { nil }
		root:        unsafe { PsiElement(nil) }
	}
	file.root = create_element(AstNode(tree.root_node()), file)
	return file
}

// new_stub_psi_file wraps a stub list, for a file whose tree has not been
// parsed.
pub fn new_stub_psi_file(path string, stub_list &StubList) &PsiFile {
	// Stub-based files have no root element of their own; `PsiFile.root()`
	// falls back to the stub list, so this root stays nil. The cast is the same
	// requirement as in the constructor above.
	return &PsiFile{
		path:        path
		tree:        unsafe { nil }
		source_text: ''
		stub_list:   stub_list
		root:        unsafe { PsiElement(nil) }
	}
}

// is_stub_based reports whether this file works from stubs rather than a
// tree.
@[inline]
pub fn (p &PsiFile) is_stub_based() bool {
	return isnil(p.tree)
}

// is_test_file reports whether the path names a V test file.
@[inline]
pub fn (p &PsiFile) is_test_file() bool {
	return p.path.ends_with('_test.v')
}

// is_shell_script reports whether the path names a V shell script.
@[inline]
pub fn (p &PsiFile) is_shell_script() bool {
	return p.path.ends_with('.vsh')
}

// index_sink returns the stub index sink for this file, if it has one.
@[inline]
pub fn (p &PsiFile) index_sink() ?StubIndexSink {
	return stubs_index.get_sink_for_file(p.path)
}

// reparse releases the old tree and parses new_code in its place.
pub fn (mut f PsiFile) reparse(new_code string, mut p parser.Parser) {
	now := time.now()
	unsafe { f.tree.free() }
	// TODO: for some reason if we pass the old tree then trying to get the text
	// of the node gives the text at the wrong offset.
	res := p.parse_code_with_tree(new_code, unsafe { nil })
	f.tree = res.tree
	f.source_text = res.source_text
	f.root = create_element(AstNode(res.tree.root_node()), f)

	loglib.with_duration(time.since(now)).with_fields({
		'file':   f.path
		'length': f.source_text.len.str()
	}).info('Reparsed file')
}

// path returns the path this file was loaded from.
@[inline]
pub fn (p &PsiFile) path() string {
	return p.path
}

// uri returns the file:// URI for that path.
@[inline]
pub fn (p &PsiFile) uri() string {
	return utils.path_to_uri(p.path)
}

// text returns the source text the file was parsed from.
@[inline]
pub fn (p &PsiFile) text() string {
	return p.source_text
}

// free releases the tree, when this file still holds one.
pub fn (mut p PsiFile) free() {
	if !isnil(p.tree) {
		unsafe { p.tree.free() }
		p.tree = unsafe { nil }
	}
}

// symbol_at returns the byte the range starts at, and 0 when the range
// falls outside the text.
pub fn (p &PsiFile) symbol_at(range TextRange) u8 {
	lines := p.source_text.split_into_lines()
	line := lines[range.line] or { return 0 }
	return line[range.column - 1] or { return 0 }
}

// root returns the root element, which for a stub-based file comes from
// the stub list.
pub fn (p &PsiFile) root() PsiElement {
	if p.is_stub_based() {
		return p.stub_list.root().get_psi() or { return p.root }
	}

	return p.root
}

// find_element_at returns the element covering a byte offset.
@[inline]
pub fn (p &PsiFile) find_element_at(offset u32) ?PsiElement {
	return p.root.find_element_at(offset)
}

// find_element_at_pos is find_element_at for a line and column position.
@[inline]
pub fn (p &PsiFile) find_element_at_pos(pos Position) ?PsiElement {
	offset := utils.compute_offset(p.source_text, pos.line, pos.character)
	return p.root.find_element_at(u32(offset))
}

// find_reference_at returns the reference at an offset, whether the offset
// lands on the reference or on its identifier.
pub fn (p &PsiFile) find_reference_at(offset u32) ?ReferenceExpressionBase {
	element := p.find_element_at(offset)?
	if element is Identifier {
		parent := element.parent()?
		if parent is ReferenceExpressionBase {
			return parent
		}
	}
	if element is ReferenceExpressionBase {
		return element
	}
	return none
}

// module_fqn returns the qualified name of the module this file belongs
// to.
@[inline]
pub fn (p &PsiFile) module_fqn() string {
	return stubs_index.get_module_qualified_name(p.path)
}

// module_name returns the name in the module clause, none when the file
// has no clause.
pub fn (p &PsiFile) module_name() ?string {
	module_clause := p.root().find_child_by_type_or_stub(.module_clause)?

	if module_clause is ModuleClause {
		return module_clause.name()
	}

	return none
}

// module_clause returns the module clause element.
pub fn (p &PsiFile) module_clause() ?&ModuleClause {
	module_clause := p.root().find_child_by_type_or_stub(.module_clause)?

	if module_clause is ModuleClause {
		return module_clause
	}

	return none
}

// get_imports returns every import spec in the file.
pub fn (p &PsiFile) get_imports() []ImportSpec {
	mut specs := []ImportSpec{}

	if p.is_stub_based() {
		for _, stub in p.stub_list.index_map {
			if stub.stub_type == .import_spec {
				if element := stub.get_psi() {
					if element is ImportSpec {
						specs << element
					}
				}
			}
		}
	} else {
		mut walker := new_psi_tree_walker(p.root())
		defer { walker.free() }

		for {
			child := walker.next() or { break }
			if child is ImportSpec {
				specs << child
			}
		}
	}

	return specs
}

// resolve_import_spec returns the first import spec matching a name.
pub fn (p &PsiFile) resolve_import_spec(name string) ?ImportSpec {
	specs := p.resolve_import_specs(name)
	if specs.len > 0 {
		return specs.first()
	}
	return none
}

// resolve_import_specs returns every import spec matching a name.
pub fn (p &PsiFile) resolve_import_specs(name string) []ImportSpec {
	imports := p.get_imports()
	if imports.len == 0 {
		return []
	}
	mut result := []ImportSpec{cap: 2}
	for imp in imports {
		if imp.import_name() == name {
			result << imp
		}
	}
	return result
}

// process_declarations feeds the file's top-level constants to a scope
// processor and stops when the processor says so; only constants are
// wired up so far.
pub fn (p &PsiFile) process_declarations(mut processor PsiScopeProcessor) bool {
	children := p.root.children()
	for child in children {
		// if child is PsiNamedElement {
		// 	if !processor.execute(child as PsiElement) {
		// 		return false
		// 	}
		// }
		if child is ConstantDeclaration {
			for constant in child.constants() {
				if constant is PsiNamedElement {
					if !processor.execute(constant as PsiElement) {
						return false
					}
				}
			}
		}
	}

	return true
}

// resolve_selective_import_symbol resolves a name that arrives through a
// selective import, none when no import lists that name.
pub fn (p &PsiFile) resolve_selective_import_symbol(name string) ?PsiElement {
	imports := p.get_imports()

	for spec in imports {
		list := spec.selective_list() or { continue }
		symbols := list.symbols()

		for ref in symbols {
			if ref.name() == name {
				if found := p.resolve_symbol_in_import_spec(spec, name) {
					return found
				}
			}
		}
	}

	return none
}

// resolve_symbol_in_import_spec resolves a name inside the module an
// import spec names.
pub fn (p &PsiFile) resolve_symbol_in_import_spec(spec ImportSpec, name string) ?PsiElement {
	import_name := spec.qualified_name()
	real_module_fqn := stubs_index.find_real_module_fqn(import_name)

	if found := p.find_in_module(real_module_fqn, name) {
		return found
	}

	return none
}

fn (p &PsiFile) find_in_module(module_fqn string, name string) ?PsiElement {
	elements := stubs_index.get_all_declarations_from_module(module_fqn, false)
	for element in elements {
		if element is PsiNamedElement {
			if element.name() == name {
				return element as PsiElement
			}
		}
	}

	types := stubs_index.get_all_declarations_from_module(module_fqn, true)
	for type_element in types {
		if type_element is PsiNamedElement {
			if type_element.name() == name {
				return type_element as PsiElement
			}
		}
	}
	return none
}
