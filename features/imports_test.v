module features

import engine
import engine.psi
import os

// These tests are about the standard library side of the index: which modules a
// buffer asks for, and that a call into one of them answers once it is read.
//
// The library is one the test writes, so the mechanism is what is checked and
// not which modules the installed compiler happens to ship.

const imports_dir_name = 'visor-features-imports-test'
const imports_library_name = 'visor-features-imports-library'

const imports_util = 'module main

struct Point {
	x int
	y int
}

fn scale(p Point, factor int) Point {
	return Point{ p.x * factor, p.y * factor }
}
'

const imports_library_module = 'module util

pub fn shout(text string) string {
	return text + "!"
}
'

const imports_buffer = 'module main

import util

fn main() {
	result := util.shout("a")
	println(result)
}
'

// labels_of is the hint labels for a file, in the order the lane sends them.
fn labels_of(file &psi.PsiFile) []string {
	mut labels := []string{}
	for hint in hints_for(file, HintOptions{}) {
		labels << hint.label
	}
	return labels
}

fn test_a_module_the_buffer_imports_is_read_for_its_calls() {
	dir := os.join_path(os.temp_dir(), imports_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), imports_util) or { panic(err.msg()) }
	library := os.join_path(os.temp_dir(), imports_library_name)
	module_dir := os.join_path(library, 'util')
	os.mkdir_all(module_dir) or { panic(err.msg()) }
	os.write_file(os.join_path(module_dir, 'lib.v'), imports_library_module) or {
		panic(err.msg())
	}

	mut session := engine.new_session()
	session.index_root(dir, os.join_path(os.temp_dir(), 'visor-features-imports-cache'))
	path := os.join_path(dir, 'main.v')
	buffer := session.put_buffer(path, imports_buffer) or { panic(err.msg()) }
	// The imports come from the parse, so a module named in a comment is not one.
	assert engine.imported_modules(buffer.file) == ['util']
	added := session.index_imported_modules(library, engine.imported_modules(buffer.file))
	assert added == [module_dir]

	file := session.file(path) or { panic('the buffer is not open: ${path}') }
	labels := labels_of(file)
	assert 'text:' in labels
	assert ': string' in labels
}

// A module that is not there is not an error. The call into it keeps the answer
// it had, which is that nobody knows, and the rest of the buffer still answers.
fn test_a_module_that_is_not_installed_changes_nothing() {
	dir := os.join_path(os.temp_dir(), imports_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), imports_util) or { panic(err.msg()) }
	library := os.join_path(os.temp_dir(), 'visor-features-imports-missing')

	mut session := engine.new_session()
	session.index_root(dir, os.join_path(os.temp_dir(), 'visor-features-imports-cache'))
	path := os.join_path(dir, 'main.v')
	buffer := session.put_buffer(path, imports_buffer) or { panic(err.msg()) }
	added := session.index_imported_modules(library, engine.imported_modules(buffer.file))
	assert added == []

	file := session.file(path) or { panic('the buffer is not open: ${path}') }
	labels := labels_of(file)
	assert labels == []
}

// Indexing the same module twice is the second call's no-op: a buffer that
// imports what another buffer already asked for costs nothing.
fn test_a_module_is_indexed_once_for_the_whole_session() {
	dir := os.join_path(os.temp_dir(), imports_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), imports_util) or { panic(err.msg()) }
	library := os.join_path(os.temp_dir(), imports_library_name)
	module_dir := os.join_path(library, 'util')
	os.mkdir_all(module_dir) or { panic(err.msg()) }
	os.write_file(os.join_path(module_dir, 'lib.v'), imports_library_module) or {
		panic(err.msg())
	}

	mut session := engine.new_session()
	session.index_root(dir, os.join_path(os.temp_dir(), 'visor-features-imports-cache'))
	path := os.join_path(dir, 'main.v')
	session.put_buffer(path, imports_buffer) or { panic(err.msg()) }
	assert session.index_imported_modules(library, ['util']) == [module_dir]
	assert session.index_imported_modules(library, ['util']) == []
}
