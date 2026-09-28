module engine

import engine.index as engine_index
import engine.parser
import engine.psi
import os

// The scratch project these tests index. Two files in one module, so a buffer in
// one of them can call a declaration that lives in the other.
const refresh_dir_name = 'visor-engine-refresh-test'

const refresh_util = 'module main

struct Point {
	x int
}

fn scale(p Point, factor int) Point {
	return Point{ p.x * factor }
}
'

const refresh_main = 'module main

fn main() {
	base := Point{ 2 }
	scaled := scale(base, 3)
	println(scaled)
}
'

// refresh_buffer_text is what a client holds after typing: the file on disk plus
// a function nobody has saved, called by a variable declared below it.
const refresh_buffer_text = 'module main

fn main() {
	base := Point{ 2 }
	scaled := scale(base, 3)
	doubled := twice(4)
	println(scaled)
	println(doubled)
}

fn twice(n int) int {
	return n * 2
}
'

fn write_refresh_project() string {
	dir := os.join_path(os.temp_dir(), refresh_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), refresh_util) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'main.v'), refresh_main) or { panic(err.msg()) }
	return dir
}

// refreshed_probe indexes the scratch project, replaces the main file's stubs
// with the ones the buffer text parses to, and returns what the engine infers
// for each variable in that text.
//
// The path holds refresh_main on disk for the whole of it, so a test that reads
// a type the buffer introduced is reading the buffer and not the file.
fn refreshed_probe(buffer string) map[string]string {
	dir := write_refresh_project()
	path := os.join_path(dir, 'main.v')

	mut manager := IndexingManager.new()
	manager.indexer.set_no_save(true)
	manager.indexer.add_indexing_root(dir, .workspace,
		os.join_path(os.temp_dir(), 'visor-engine-refresh-index'))
	manager.indexer.index(fn (_root engine_index.IndexingRoot, _index int) {})
	manager.setup_stub_indexes()
	manager.refresh_file(path, buffer) or { panic(err.msg()) }

	mut v_parser := parser.Parser.new()
	defer {
		v_parser.free()
	}
	res := v_parser.parse_code(buffer)
	buffer_file := psi.new_psi_file(path, res.tree, buffer)

	mut inferred := map[string]string{}
	collect_var_types(buffer_file.root, mut inferred)
	assert os.read_file(path) or { '' } == refresh_main
	return inferred
}

fn collect_var_types(element psi.PsiElement, mut inferred map[string]string) {
	if element is psi.VarDefinition {
		inferred[element.name()] = element.get_type().readable_name()
	}
	for child in element.children() {
		collect_var_types(child, mut inferred)
	}
}

fn test_a_buffer_answers_for_a_declaration_nobody_saved() {
	// `twice` exists in the buffer and nowhere on disk. A resolved type for
	// `doubled` is only reachable when the buffer's stubs are the ones in the
	// index.
	inferred := refreshed_probe(refresh_buffer_text)
	println('the buffer inferred: ${inferred}')
	assert inferred['doubled'] == 'int'
}

fn test_a_buffer_still_resolves_what_its_neighbour_file_declares() {
	// The refresh replaces one file's stubs. Everything else in the module is
	// still answered from the index, which is what the call into util.v checks.
	inferred := refreshed_probe(refresh_buffer_text)
	assert inferred['scaled'] == 'Point'
	assert inferred['base'] == 'Point'
}

fn test_the_file_on_disk_keeps_the_text_it_had() {
	// The buffer differs from the file, and the probe asserts the file still
	// reads refresh_main. This test states the difference out loud, so a change
	// that made the two texts equal would fail here instead of passing quietly.
	assert refresh_buffer_text != refresh_main
	assert refresh_buffer_text.contains('fn twice')
	assert !refresh_main.contains('fn twice')
}
