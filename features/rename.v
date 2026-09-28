// rename.v answers the two questions a rename asks: which declaration a position
// names, and every place that name appears in the files that can see it.
//
// Nothing here writes anything. The answer is a list of spans per file, and the
// client is what applies them, so a rename that turned out to be wrong is an
// undo in the editor rather than a file this server rewrote.
//
// The walk reads the same text the other engine lanes read: the buffer a client
// has open, the file on disk otherwise. A name is recognised by resolving every
// reference in a file and comparing the declaration it lands on, which is what
// keeps two same-named locals in one file apart.

module features

import engine
import engine.parser
import engine.psi
import os

// TargetScope is how far a name reaches, which is what decides the files a
// rename has to walk.
//
// A local is declared and used in one file. A private declaration is reachable
// from every file of its own module. A public one is reachable from the modules
// that import it as well, and a rename that stopped at its own module would
// leave every caller naming something that no longer exists.
pub enum TargetScope {
	local
	module
	workspace
}

// NameSpan is one occurrence of a name: the bytes it covers in one text.
pub struct NameSpan {
pub:
	start int
	end   int
}

// RenameTarget is the declaration a position names, and what a client is told
// before it asks for the rewrite.
pub struct RenameTarget {
pub:
	name string
	kind SymbolKind
	// path is the file the request was made about, which is where the client's
	// range points. span is where the name sits in that file's text, and for a
	// reference it is the reference rather than the declaration.
	path string
	span NameSpan
	// declaration_path is the file the declaration itself is in. It is the same
	// file unless the position named a reference into another module, and it is
	// what decides which module's files a rename has to walk.
	declaration_path string
	scope            TargetScope
	// element is the declaration itself: what every candidate reference is
	// resolved and compared against. It never reaches the wire.
	element psi.PsiElement
}

// FileSpans is one file's share of a rename: the places to rewrite, and the text
// those places are offsets into.
//
// The text travels with the spans because a client applies an edit at a position
// it counts in code units, and only the text turns a byte offset into one.
pub struct FileSpans {
pub:
	path  string
	text  string
	spans []NameSpan
}

// RenamePlan is what a rename would write, file by file.
pub struct RenamePlan {
pub mut:
	files []FileSpans
	// unreadable names the files the search reached and could not read. A plan
	// that skipped one of them silently would be half a rename, so the caller
	// refuses instead of sending the half it has.
	unreadable []string
}

// Located is a position's name and the declaration behind it.
struct Located {
	element psi.PsiElement
	span    NameSpan
	name    string
}

// rename_target answers what a position names. It is the whole answer a client
// needs before it asks for the rewrite: the name, where it is, and how far it
// reaches.
//
// A position that names nothing declared is refused rather than answered with
// nothing, because a client that drew no range has nothing to rewrite and an
// empty target would read as a success.
pub fn rename_target(file &psi.PsiFile, offset int) !RenameTarget {
	text := file.source_text
	if offset < 0 || offset > text.len {
		return error('there is nothing at this position to rename')
	}
	found := located_at(file, offset)!
	declaration_path := element_path(found.element) or { file.path }
	return RenameTarget{
		name:             found.name
		kind:             declaration_kind(found.element)
		path:             file.path
		span:             found.span
		declaration_path: declaration_path
		scope:            target_scope(found.element)
		element:          found.element
	}
}

// rename_spans answers a rename: every place the target's name appears in every
// file the target's scope reaches.
//
// Each file is read the way the engine reads files, so a buffer with unsaved
// edits is planned against what the person is looking at. A name the index
// cannot place in a module is refused for anything wider than one file: without
// a module there is no file set, and a rename that guessed one would rewrite
// places this build cannot see.
pub fn rename_spans(session &engine.Session, target RenameTarget) !RenamePlan {
	module_fqn := session.module_of(target.declaration_path)
	if target.scope != .local && module_fqn == '' {
		return error('no indexed workspace folder contains ${target.declaration_path}, so a rename across files cannot be planned from here')
	}
	identity := declaration_identity(target.element) or {
		return error('the declaration at this position cannot be identified, so a rename would rewrite the wrong places')
	}
	mut plan := RenamePlan{
		files:      []FileSpans{}
		unreadable: []string{}
	}
	mut seen := map[string]bool{}
	for path in rename_files(session, target, module_fqn) {
		if seen[path] {
			continue
		}
		seen[path] = true
		text := file_text(session, path) or {
			plan.unreadable << path
			continue
		}
		spans := written_spans(session, path, text, target, identity)
		if spans.len == 0 {
			continue
		}
		plan.files << FileSpans{
			path:  path
			text:  text
			spans: spans
		}
	}
	return plan
}

// name_problem is why a proposed name cannot be used, or an empty string when it
// can. It is asked before anything is planned: a client that would rewrite a file
// into something that no longer parses is worth refusing in words.
pub fn name_problem(name string) string {
	if name == '' {
		return 'a name cannot be empty'
	}
	if !is_name_letter(name[0]) {
		return '`${name}` cannot be a name: a name starts with a letter or an underscore'
	}
	for at := 1; at < name.len; at++ {
		ch := name[at]
		if !is_name_letter(ch) && !(ch >= `0` && ch <= `9`) {
			return '`${name}` cannot be a name: a name holds letters, digits and underscores'
		}
	}
	if name in keywords {
		return '`${name}` is a keyword, so it cannot be a name'
	}
	return ''
}

// rename_files is the set of files a rename has to walk: the declaring file, the
// files of its module, and, for a name the public keyword puts in reach, the
// files of the modules that import it.
//
// V has no re-export, so the modules that import it are the whole of the reach a
// public name has: a file that names it does so through an import of its module.
fn rename_files(session &engine.Session, target RenameTarget, module_fqn string) []string {
	mut files := [target.declaration_path]
	if target.scope == .local {
		return files
	}
	for path in session.module_files(module_fqn) {
		files << path
	}
	if target.scope == .workspace {
		for path in session.importer_files(module_fqn) {
			files << path
		}
	}
	return files
}

// file_text is the text a file is planned against: the buffer when the session
// holds one, the file on disk otherwise.
fn file_text(session &engine.Session, path string) ?string {
	if file := session.file(path) {
		return file.source_text
	}
	return os.read_file(path) or { none }
}

// written_spans is every place one file has to be rewritten, in order and
// without repeats.
//
// A name is declared once and referred to as often as the file likes, and a
// reference is what a walk finds. The declaration's own name is added by hand
// where the walk would miss it: a struct, a field and a constant declare a name
// without referring to it.
fn written_spans(session &engine.Session, path string, text string, target RenameTarget, identity string) []NameSpan {
	mut additions := []NameSpan{}
	if path == target.declaration_path {
		if span := element_name_span(target.element, text) {
			additions << span
		}
	}
	if file := session.file(path) {
		return ordered_spans(collect_spans(file.root, text, target.name, identity, additions))
	}
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	parsed := p.parse_code(text)
	file := psi.new_psi_file(path, parsed.tree, text)
	spans := ordered_spans(collect_spans(file.root, text, target.name, identity, additions))
	file.free()
	return spans
}

// collect_spans walks one parsed file and keeps every reference that resolves to
// the target.
//
// Resolving is what makes the answer exact. A file can hold two declarations
// with one name, and only the declaration a reference lands on says which of
// them this rename is about.
fn collect_spans(root psi.PsiElement, text string, name string, identity string, additions []NameSpan) []NameSpan {
	mut spans := additions.clone()
	mut walker := psi.new_psi_tree_walker(root)
	defer {
		walker.free()
	}
	for {
		node := walker.next() or { break }
		if span := reference_span(node, text, name, identity) {
			spans << span
		}
	}
	return spans
}

// reference_span is the span of one reference, or none when it is not a
// reference, not this name, or not this declaration.
fn reference_span(node psi.PsiElement, text string, name string, identity string) ?NameSpan {
	base := node
	if node !is psi.ReferenceExpressionBase {
		return none
	}
	reference := node as psi.ReferenceExpressionBase
	if !base.text_matches(name) {
		return none
	}
	resolved := reference.resolve() or { return none }
	if declaration_identity(resolved) or { '' } != identity {
		return none
	}
	return span_of_range(text, reference.text_range())
}

// located_at is the declaration a position names, and the name in the text the
// request came from.
//
// A position on a reference is answered with the declaration the reference
// resolves to, so the range the client is shown is the reference under the
// cursor rather than the declaration's own name in whatever file it lives in.
fn located_at(file &psi.PsiFile, offset int) !Located {
	text := file.source_text
	if reference := file.find_reference_at(u32(offset)) {
		resolved := reference.resolve() or {
			return error('the name at this position is not declared in the indexed workspace, so rewriting it would change names this build cannot see')
		}
		wide := resolved
		refusal := rename_refusal(wide)
		if refusal != '' {
			return error(refusal)
		}
		name := element_name(wide)
		if name == '' {
			return error('nothing at this position names something this build can rename')
		}
		return Located{
			element: wide
			span:    span_of_range(text, reference.text_range())
			name:    name
		}
	}
	mut node := file.find_element_at(u32(offset)) or {
		return error('there is nothing at this position to rename')
	}
	// A declaration's name is a leaf a few levels under the declaration itself,
	// so the walk up is short. Eight is past every shape a name can hide in and
	// stops a position in open code from reaching the file's own element.
	for _ in 0 .. 8 {
		wide := node
		refusal := rename_refusal(wide)
		if refusal != '' {
			return error(refusal)
		}
		if declaration := named_declaration(wide) {
			if span := element_name_span(declaration, text) {
				return Located{
					element: declaration
					span:    span
					name:    element_name(declaration)
				}
			}
		}
		parent := node.parent() or { break }
		node = parent
	}
	return error('there is nothing at this position to rename')
}

// rename_refusal is why a declaration cannot be renamed, or an empty string for
// one that can.
//
// A module clause names a directory and an import names a module or a symbol in
// one: rewriting either would leave the files where they are and the code
// naming something that moved, so both are refused rather than half-done.
fn rename_refusal(element psi.PsiElement) string {
	if element is psi.ModuleClause {
		return 'a module is named by the directory it is in, so renaming the clause here would rename no file'
	}
	if element is psi.ImportSpec || element is psi.ImportName || element is psi.ImportPath
		|| element is psi.ImportAlias {
		return 'an import names a module or a symbol in one, and renaming it here would not move anything'
	}
	return ''
}

// named_declaration is the element itself when it introduces a name, which is
// the shape a rename is about.
fn named_declaration(element psi.PsiElement) ?psi.PsiElement {
	base := element
	if element !is psi.PsiNamedElement {
		return none
	}
	named := element as psi.PsiNamedElement
	if named.name() == '' {
		return none
	}
	return base
}

// element_name is the name an element introduces, or an empty string for one
// that introduces none.
fn element_name(element psi.PsiElement) string {
	if element is psi.PsiNamedElement {
		return element.name()
	}
	return ''
}

// element_name_span is where an element's own name sits in an text.
fn element_name_span(element psi.PsiElement, text string) ?NameSpan {
	if element !is psi.PsiNamedElement {
		return none
	}
	named := element as psi.PsiNamedElement
	span := span_of_range(text, named.identifier_text_range())
	if span.end <= span.start {
		return none
	}
	return span
}

// declaration_identity is what makes two elements the same declaration: the file
// it was declared in and the place in that file.
//
// Neither the text nor the element's own kind is part of it. An element the index
// built for a file this process has not read carries no text at all, and the kind
// an element reports is read off the node it was built from, which a stub and a
// parse spell differently for the same declaration. Two names cannot start at one
// place in one file, so the path and the place are what identify a declaration.
fn declaration_identity(element psi.PsiElement) ?string {
	path := element_path(element) or { return none }
	if element !is psi.PsiNamedElement {
		return none
	}
	named := element as psi.PsiNamedElement
	range := named.identifier_text_range()
	if range.end_column <= range.column {
		return none
	}
	return '${path}\t${range.line}\t${range.column}'
}

// target_scope is how far a name reaches.
fn target_scope(element psi.PsiElement) TargetScope {
	if element is psi.VarDefinition || element is psi.ParameterDeclaration || element is psi.Receiver
		|| element is psi.StaticReceiver || element is psi.GenericParameter {
		return .local
	}
	if is_public_declaration(element) {
		return .workspace
	}
	return .module
}

// is_public_declaration reports whether a declaration carries a public modifier.
// A member of a type whose own visibility is what decides is left out of it: an
// enum member and an interface method are written without the keyword and are
// still reachable through their type.
fn is_public_declaration(element psi.PsiElement) bool {
	if element is psi.FunctionOrMethodDeclaration {
		return element.is_public()
	}
	if element is psi.StaticMethodDeclaration {
		return element.is_public()
	}
	if element is psi.StructDeclaration {
		return element.is_public()
	}
	if element is psi.EnumDeclaration {
		return element.is_public()
	}
	if element is psi.InterfaceDeclaration {
		return element.is_public()
	}
	if element is psi.TypeAliasDeclaration {
		return element.is_public()
	}
	if element is psi.ConstantDefinition {
		return element.is_public()
	}
	if element is psi.GlobalVarDefinition {
		return element.is_public()
	}
	if element is psi.FieldDeclaration {
		return element.is_public()
	}
	return element is psi.EnumFieldDeclaration || element is psi.InterfaceMethodDeclaration
}

// ordered_spans is spans sorted by where they start, with the repeats dropped
// and the empty ones gone.
//
// A client applies the edits of one file in one go, and two edits over the same
// bytes are a rewrite it cannot do: a span that arrived twice has to be one.
fn ordered_spans(spans []NameSpan) []NameSpan {
	mut sorted := spans.clone()
	sorted.sort_with_compare(fn (a &NameSpan, b &NameSpan) int {
		if a.start != b.start {
			return if a.start < b.start { -1 } else { 1 }
		}
		if a.end == b.end {
			return 0
		}
		return if a.end < b.end { -1 } else { 1 }
	})
	mut out := []NameSpan{}
	for span in sorted {
		if span.end <= span.start {
			continue
		}
		if out.len > 0 && out[out.len - 1].start == span.start && out[out.len - 1].end == span.end {
			continue
		}
		out << span
	}
	return out
}

// span_of_range is an engine range as byte offsets in a text.
fn span_of_range(text string, range psi.TextRange) NameSpan {
	start, stop := span_offsets(text, range)
	return NameSpan{
		start: start
		end:   stop
	}
}

// is_name_letter reports whether a byte can start or continue a V name.
fn is_name_letter(ch u8) bool {
	if ch >= `a` && ch <= `z` {
		return true
	}
	if ch >= `A` && ch <= `Z` {
		return true
	}
	return ch == `_`
}
