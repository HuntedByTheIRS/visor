module engine

import engine.psi
import os

// The session tests index a scratch module and then ask it about buffers. The
// directory carries its own name so these runs cannot share an index with the
// refresh tests.

const session_dir_name = 'visor-engine-session-test'

const session_util = 'module main

struct Point {
	x int
}

fn scale(p Point, factor int) Point {
	return Point{ p.x * factor }
}

fn label(n int) string {
	return n.str()
}
'

// The file on disk. It has no `twice`, which is how the tests tell a buffer's
// text from the text of the last save.
const session_main = 'module main

fn main() {
	scaled := scale(Point{ 2 }, 3)
	println(scaled)
}
'

// What a client holds after typing a function into that file.
const session_buffer = 'module main

fn main() {
	doubled := twice(4)
	println(doubled)
}

fn twice(n int) int {
	return n * 2
}
'

// A second buffer, calling the function only the first buffer declares.
const session_neighbour = 'module main

fn other() {
	piece := twice(2)
	println(piece)
}
'

fn write_session_project() string {
	dir := os.join_path(os.temp_dir(), session_dir_name)
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'util.v'), session_util) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'main.v'), session_main) or { panic(err.msg()) }
	return dir
}

// indexed_session indexes a fresh copy of the scratch project and returns the
// session with the path of the file the buffer tests edit. The name keeps each
// test's index cache apart from the others'.
fn indexed_session(name string) (&Session, string) {
	dir := write_session_project()
	mut session := new_session()
	session.index_root(dir, os.join_path(os.temp_dir(), 'visor-engine-session-cache-${name}'))
	return session, os.join_path(dir, 'main.v')
}

// var_types_in_buffer reads what the engine infers for every variable in an
// open buffer.
fn var_types_in_buffer(session &Session, path string) map[string]string {
	file := session.file(path) or { panic('the path is not open: ${path}') }
	mut inferred := map[string]string{}
	collect_session_var_types(file.root, mut inferred)
	return inferred
}

fn collect_session_var_types(element psi.PsiElement, mut inferred map[string]string) {
	if element is psi.VarDefinition {
		inferred[element.name()] = element.get_type().readable_name()
	}
	for child in element.children() {
		collect_session_var_types(child, mut inferred)
	}
}

fn test_a_buffer_is_what_the_session_answers_from() {
	mut session, path := indexed_session('buffer')
	session.put_buffer(path, session_buffer)!

	inferred := var_types_in_buffer(session, path)
	println('the buffer inferred: ${inferred}')
	assert inferred['doubled'] == 'int'
	assert os.read_file(path) or { '' } == session_main
}

fn test_a_buffer_answers_a_question_asked_from_another_buffer() {
	mut session, path := indexed_session('neighbour')
	session.put_buffer(path, session_buffer)!
	neighbour := os.join_path(os.dir(path), 'other.v')
	session.put_buffer(neighbour, session_neighbour)!

	assert var_types_in_buffer(session, neighbour)['piece'] == 'int'
}

fn test_closing_a_buffer_hands_the_file_back_to_the_index() {
	mut session, path := indexed_session('close')
	session.put_buffer(path, session_buffer)!
	neighbour := os.join_path(os.dir(path), 'other.v')
	session.put_buffer(neighbour, session_neighbour)!
	assert var_types_in_buffer(session, neighbour)['piece'] == 'int'

	// main.v goes back to the text that is on disk, which declares no `twice`,
	// so the call in the neighbour buffer stops resolving.
	session.close_buffer(path)
	if _ := session.file(path) {
		assert false
	}
	assert var_types_in_buffer(session, neighbour)['piece'] == 'unknown'
}

// Two texts that put a call of the same shape at the same offsets, answered by
// declarations with different types: `twice` in the buffer, `label` in the file
// next to it.
const session_typed_first = 'module main

fn use() {
	value := twice(4)
	println(value)
}

fn twice(n int) int {
	return n * 2
}
'

const session_typed_second = 'module main

fn use() {
	value := label(4)
	println(value)
}
'

fn test_an_edit_answers_about_the_text_that_is_there_now() {
	mut session, path := indexed_session('typed')
	session.put_buffer(path, session_typed_first)!
	assert var_types_in_buffer(session, path)['value'] == 'int'

	// The second text holds a call of the same length in the same place, so an
	// answer kept from the first text is an answer for a call that is gone.
	session.put_buffer(path, session_typed_second)!
	assert var_types_in_buffer(session, path)['value'] == 'string'
}

fn test_a_buffer_outside_every_root_says_so() {
	mut session, _ := indexed_session('outside')
	outside := os.join_path(os.temp_dir(), 'visor-engine-session-outside', 'loose.v')
	session.put_buffer(outside, 'module main

fn main() {
	x := 1
	println(x)
}
') or {
		assert err.msg().contains('no indexed workspace folder')
		return
	}
	assert false
}
