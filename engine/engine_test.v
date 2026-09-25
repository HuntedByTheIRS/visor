module engine

import os
import engine.psi
import engine.parser

// fixture_path is a real V file, small enough to read in a test and complete
// enough to hold a struct, a method and a call.
const fixture_path = '${@VMODROOT}/engine/testdata/counter.v'

fn test_parse_source_reports_the_tree() {
	mut parse_engine := new_parser_engine()
	defer {
		parse_engine.free()
	}

	source := os.read_file(fixture_path)!
	file := parse_engine.parse_source(source, fixture_path)

	assert file.root.kind == 'source_file'
	assert file.root.start_byte == 0
	assert file.text == source
	mut kinds := []string{cap: file.root.children.len}
	for child in file.root.children {
		kinds << child.kind
	}
	println('root children: ${kinds.join(', ')}')
}

fn test_node_at_finds_a_node_at_an_offset() {
	mut parse_engine := new_parser_engine()
	defer {
		parse_engine.free()
	}

	source := os.read_file(fixture_path)!
	file := parse_engine.parse_source(source, fixture_path)

	index := source.index('increment') or { panic('the fixture does not name increment') }
	offset := u32(index)
	found := parse_engine.node_at(file, offset)
	node := found or { panic('no node covers the offset of increment') }
	println('node at increment: ${node.kind} ${node.start} ${node.end}')
	assert node.start_byte <= offset
	assert node.end_byte > offset
	assert node.kind.len > 0
}

fn test_psi_file_resolves_a_symbol() {
	mut v_parser := parser.Parser.new()
	defer {
		v_parser.free()
	}

	res := v_parser.parse_file(fixture_path)!
	mut psi_file := psi.new_psi_file(fixture_path, res.tree, res.source_text)
	defer {
		psi_file.free()
	}

	index := res.source_text.index('increment') or { panic('the fixture does not name increment') }
	offset := u32(index)
	found := psi_file.find_element_at(offset)
	element := found or { panic('no psi element at the offset') }
	mut current := element
	for {
		if mut current is psi.PsiNamedElement {
			println('named element: ${current.name()}')
			assert current.name() == 'increment'
			break
		}
		current = current.parent() or { panic('reached the root without a named element') }
	}
}

fn test_stub_index_holds_the_declaration() {
	mut v_parser := parser.Parser.new()
	defer {
		v_parser.free()
	}

	res := v_parser.parse_file(fixture_path)!
	mut psi_file := psi.new_psi_file(fixture_path, res.tree, res.source_text)
	defer {
		psi_file.free()
	}

	sink := psi_file.index_sink() or { panic('the file has no stub sink') }
	stub_index := psi.new_stubs_index([sink])
	elements := stub_index.get_elements_by_name(.methods, 'increment')
	println('indexed methods named increment: ${elements.len}')
	assert elements.len == 1
	element := elements[0]
	if element is psi.PsiNamedElement {
		assert element.name() == 'increment'
	} else {
		panic('the indexed element is not a named element')
	}
}
