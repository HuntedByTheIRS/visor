module features

import engine
import engine.psi
import os

// Two files of one module and one file of another, so a rename can be asked
// about a local, about a private declaration two files share, and about a public
// one another module reaches.
const rename_app = "module main

import greeter

struct Point {
	x int
	y int
}

fn (p Point) scaled(k int) int {
	return p.x * k
}

fn count_helper(base int) int {
	return base
}

fn helper(base int) int {
	local_count := base + 1
	return local_count
}

fn first(value int) int {
	total := value + 1
	return total
}

fn second(value int) int {
	total := value + 2
	return total
}

fn main() {
	point := Point{ 1, 2 }
	println(point.scaled(helper(2)))
	println(count_helper(3))
	println(module_helper(4))
	println(greeter.Greeting{ text_body: 'hi' }.body_of())
}
"

const rename_helper = 'module main

pub fn shared(base int) int {
	return base
}

fn module_helper(base int) int {
	return base
}

fn lonely() int {
	return 0
}
'

const rename_greeter = 'module greeter

pub struct Greeting {
pub:
	text_body string
}

pub fn (g Greeting) body_of() string {
	return g.text_body
}
'

// rename_project writes the files and indexes the folder, then opens the first
// file as a buffer, which is what a client has while a person is looking at it.
fn rename_project(name string) &engine.Session {
	dir := os.join_path(os.temp_dir(), 'visor-features-rename-test-${name}')
	os.mkdir_all(os.join_path(dir, 'greeter')) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'app.v'), rename_app) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'helper.v'), rename_helper) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'greeter', 'greeter.v'), rename_greeter) or {
		panic(err.msg())
	}
	mut session := engine.new_session()
	session.index_root(dir, os.join_path(dir, '.cache'))
	session.put_buffer(os.join_path(dir, 'app.v'), rename_app) or { panic(err.msg()) }
	return session
}

// open_rename_buffer is the parse the session holds for one of the project's
// files.
fn open_rename_buffer(mut session engine.Session, name string) &psi.PsiFile {
	for path in session.roots.map(it + '/' + name) {
		if file := session.file(path) {
			return file
		}
	}
	panic('the buffer for ${name} is not open')
}

// offset_of_needle is where a piece of the fixture sits, computed from the text
// rather than written down, so editing the fixture cannot move an expectation.
fn offset_of_needle(text string, needle string, skip int) int {
	mut seen := 0
	mut from := 0
	for from < text.len {
		at := text[from..].index(needle) or { return -1 }
		if seen == skip {
			return from + at
		}
		seen++
		from += at + 1
	}
	return -1
}

// span_bytes is the bytes a span covers, which is what an edit would replace.
fn span_bytes(text string, span NameSpan) string {
	return text[span.start..span.end]
}

// plan_summary is a plan as the files and the names it would rewrite, so a test
// can say what it expects without counting offsets. It is sorted, because the
// order the files are walked in is not part of the answer.
fn plan_summary(plan RenamePlan) []string {
	mut lines := []string{}
	for file in plan.files {
		mut names := []string{}
		for span in file.spans {
			names << span_bytes(file.text, span)
		}
		lines << '${os.base(file.path)}: ${names.join(',')}'
	}
	return lines.sorted()
}

fn test_a_local_is_renamed_inside_its_own_file() {
	mut session := rename_project('local')
	file := open_rename_buffer(mut session, 'app.v')
	offset := offset_of_needle(file.source_text, 'local_count', 0)
	target := rename_target(file, offset) or { panic(err.msg()) }
	assert target.name == 'local_count'
	assert target.kind == .variable
	assert target.scope == .local
	assert target.declaration_path.ends_with('app.v')
	assert span_bytes(file.source_text, target.span) == 'local_count'
	plan := rename_spans(session, target) or { panic(err.msg()) }
	// the declaration and the one place the name is read
	assert plan_summary(plan) == ['app.v: local_count,local_count']
	assert plan.unreadable.len == 0
}

// A private declaration is reachable from every file of its own module, so the
// file the rename was asked in is not the file it has to rewrite.
fn test_a_private_declaration_is_renamed_across_its_module() {
	mut session := rename_project('module')
	file := open_rename_buffer(mut session, 'app.v')
	offset := offset_of_needle(file.source_text, 'module_helper', 0)
	target := rename_target(file, offset) or { panic(err.msg()) }
	assert target.name == 'module_helper'
	assert target.scope == .module
	// the position named a reference, so the declaration is in another file
	assert target.path.ends_with('app.v')
	assert target.declaration_path.ends_with('helper.v')
	plan := rename_spans(session, target) or { panic(err.msg()) }
	assert plan_summary(plan) == ['app.v: module_helper', 'helper.v: module_helper']
}

// A name the public keyword puts in reach is used from the modules that import
// it, and a rename that stopped at its own module would leave those callers
// naming something that no longer exists.
fn test_a_public_member_is_renamed_where_it_is_reached_from() {
	mut session := rename_project('public')
	file := open_rename_buffer(mut session, 'app.v')
	offset := offset_of_needle(file.source_text, 'body_of', 0)
	target := rename_target(file, offset) or { panic(err.msg()) }
	assert target.name == 'body_of'
	assert target.kind == .method
	assert target.scope == .workspace
	assert target.declaration_path.ends_with('greeter.v')
	plan := rename_spans(session, target) or { panic(err.msg()) }
	// the method in its own module, and the call in the module that imports it.
	// helper.v imports nothing, so it is not walked.
	assert plan_summary(plan) == ['app.v: body_of', 'greeter.v: body_of']
}

// A field is declared in one file and written from another, and the
// declaration's own name is the place a reference walk does not find: a field
// declares a name without referring to it.
fn test_a_field_is_renamed_where_it_is_declared_and_read() {
	mut session := rename_project('field')
	file := open_rename_buffer(mut session, 'app.v')
	offset := offset_of_needle(file.source_text, 'text_body', 0)
	target := rename_target(file, offset) or { panic(err.msg()) }
	assert target.name == 'text_body'
	assert target.kind == .field
	assert target.scope == .workspace
	plan := rename_spans(session, target) or { panic(err.msg()) }
	// the declaration and the read in greeter.v, and the keyed element in app.v
	assert plan_summary(plan) == ['app.v: text_body', 'greeter.v: text_body,text_body']
}

// Two functions with a parameter of one name are the shape that tells a rename
// apart from a search for a word: only the parameter the position named is
// rewritten, and it is rewritten in the two places it appears.
fn test_one_of_two_same_named_locals_is_renamed() {
	mut session := rename_project('locals')
	file := open_rename_buffer(mut session, 'app.v')
	text := file.source_text
	first_at := offset_of_needle(text, 'fn first(value', 0) + 'fn first('.len
	second_at := offset_of_needle(text, 'fn second(value', 0) + 'fn second('.len
	first_target := rename_target(file, first_at) or { panic(err.msg()) }
	second_target := rename_target(file, second_at) or { panic(err.msg()) }
	assert first_target.name == 'value'
	assert second_target.name == 'value'
	first_plan := rename_spans(session, first_target) or { panic(err.msg()) }
	second_plan := rename_spans(session, second_target) or { panic(err.msg()) }
	assert plan_summary(first_plan) == ['app.v: value,value']
	assert plan_summary(second_plan) == ['app.v: value,value']
	// two spans each, and not the same two: the parameter and the read of one
	// are the parameter and the read of the other in no list
	first_spans := first_plan.files[0].spans
	second_spans := second_plan.files[0].spans
	assert first_spans.len == 2
	assert second_spans.len == 2
	assert first_spans[0].start != second_spans[0].start
	assert first_spans[1].start != second_spans[1].start
}

// A local the position named by its read is renamed at its declaration too, and
// a declaration with no other use is still rewritten where it stands.
fn test_a_name_is_rewritten_at_its_declaration_and_its_reads() {
	mut session := rename_project('reads')
	file := open_rename_buffer(mut session, 'app.v')
	text := file.source_text
	// `total` is declared on each of these lines and read on the next
	read_at := offset_of_needle(text, 'return total', 0) + 'return '.len
	target := rename_target(file, read_at) or { panic(err.msg()) }
	assert target.name == 'total'
	plan := rename_spans(session, target) or { panic(err.msg()) }
	assert plan_summary(plan) == ['app.v: total,total']
	by_declaration := rename_target(file, offset_of_needle(text, 'total := value', 0)) or {
		panic(err.msg())
	}
	assert by_declaration.name == 'total'
	same := rename_spans(session, by_declaration) or { panic(err.msg()) }
	assert plan_summary(same) == ['app.v: total,total']
	assert same.files[0].spans[0].start == plan.files[0].spans[0].start
}

fn test_a_position_that_names_nothing_is_refused_in_words() {
	mut session := rename_project('refusals')
	file := open_rename_buffer(mut session, 'app.v')
	text := file.source_text
	// a module clause names a directory, not a file
	rename_target(file, offset_of_needle(text, 'main', 0)) or {
		assert err.msg().contains('named by the directory')
	}
	// an import names another module
	rename_target(file, offset_of_needle(text, 'greeter', 0)) or {
		assert err.msg().contains('import')
	}
	// a builtin is declared in the compiler, not in the workspace
	rename_target(file, offset_of_needle(text, 'println', 0)) or {
		assert err.msg().contains('not declared in the indexed workspace')
	}
	// a position on no name at all: inside a string literal, and past the end
	// of the buffer
	inside_literal := offset_of_needle(text, "'hi'", 0) + 1
	rename_target(file, inside_literal) or {
		assert err.msg().contains('nothing at this position')
	}
	rename_target(file, text.len) or { assert err.msg().contains('nothing at this position') }
}

fn test_a_proposed_name_is_checked_before_anything_is_planned() {
	assert name_problem('') != ''
	assert name_problem('1st') != ''
	assert name_problem('a-b') != ''
	assert name_problem('fn') != ''
	assert name_problem('ok_name') == ''
	assert name_problem('_private') == ''
}
