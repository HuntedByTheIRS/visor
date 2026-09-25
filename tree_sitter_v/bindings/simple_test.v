module bindings

fn test_simple() {
	mut p := new_parser[NodeType](type_factory)
	// The `language` constant is avoided here on purpose: passing it makes V3
	// emit `(TSLanguage[]){*bindings__language}`, an array compound literal of
	// the incomplete C typedef, and cc rejects the file. Reaching for the C
	// function directly sidesteps that. The test's own assertions are untouched.
	p.set_language(C.tree_sitter_v())

	code := 'fn main() {}'
	tree := p.parse_string(source: code)
	root := tree.root_node()

	println(root)

	fc := root.first_child()?

	if fc.type_name == .function_declaration {
		if name_node := fc.child_by_field_name('name') {
			assert name_node.text(code) == 'main'
			assert name_node.range().start_point.row == 0
			assert name_node.range().start_point.column == 3
			assert name_node.range().end_point.row == 0
			assert name_node.range().end_point.column == 7
		} else {
			assert false, 'name node not found'
		}
	} else {
		assert false, 'function declaration not found'
	}
}
