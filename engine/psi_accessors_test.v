module engine

import engine.parser
import engine.psi

// These lock the accessor contracts a caller relies on: what an attribute key
// comes out as, and what parent_nth counts from.

// attribute_keys parses one snippet and reports the attribute keys the accessors
// see on the struct in it. Attribute.keys() is the path AttributeExpression.value()
// feeds, and the path @[heap] and @[attribute] are read through.
fn attribute_keys(code string) []string {
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	res := p.parse_code(code)
	file := psi.new_psi_file('psi_accessors_test.v', res.tree, res.source_text)
	mut keys := []string{}
	for child in file.root.children() {
		if child is psi.StructDeclaration {
			for attr in child.attributes() {
				if attr is psi.Attribute {
					keys << attr.keys()
				}
			}
		}
	}
	return keys
}

fn test_a_bare_attribute_yields_the_name_it_carries() {
	assert attribute_keys('@[heap]\npub struct A {}\n') == ['heap']
	assert attribute_keys('@[noinit]\npub struct A {}\n') == ['noinit']
}

fn test_attributes_carrying_no_name_are_dropped() {
	// keys() drops the empty ones, so a caller asking whether a struct is
	// marked @[heap] cannot be fooled by a key/value or a literal form.
	assert attribute_keys("@[json: 'name']\npub struct A {}\n") == []
	assert attribute_keys("@['literal']\npub struct A {}\n") == []
	assert attribute_keys('pub struct A {}\n') == []
}

fn test_is_heap_reads_the_bare_attribute() {
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	res := p.parse_code('@[heap]\npub struct A {}\n')
	file := psi.new_psi_file('psi_accessors_test.v', res.tree, res.source_text)
	for child in file.root.children() {
		if child is psi.StructDeclaration {
			assert child.is_heap()
			return
		}
	}
	assert false
}

fn test_parent_nth_counts_from_the_element_itself() {
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	res := p.parse_code('pub struct A {\n	field int\n}\n')
	file := psi.new_psi_file('psi_accessors_test.v', res.tree, res.source_text)
	for child in file.root.children() {
		if child is psi.StructDeclaration {
			inner := child.first_child() or { break }
			parent := inner.parent() or { break }
			// 0 is the element and 1 is its parent, which is the counting
			// VarDefinition and TypeInferer use when they ask for a grandparent
			// at 2.
			assert inner.parent_nth(0)?.get_text() == inner.get_text()
			assert inner.parent_nth(1)?.get_text() == parent.get_text()
			return
		}
	}
	assert false
}

// init_elements reports the text of every element a struct literal initializes,
// in source order, whichever list the parser used for it.
fn init_elements(code string) []string {
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	res := p.parse_code(code)
	file := psi.new_psi_file('psi_accessors_test.v', res.tree, res.source_text)
	mut elements := []string{}
	collect_init_elements(file.root, mut elements)
	return elements
}

fn collect_init_elements(element psi.PsiElement, mut elements []string) {
	if element is psi.TypeInitializer {
		for item in element.element_list() {
			elements << item.get_text().trim_space()
		}
	}
	for child in element.children() {
		collect_init_elements(child, mut elements)
	}
}

fn test_a_struct_literal_reports_its_elements_in_both_spellings() {
	// The positional form is the one a field-name hint is for: its names are
	// not in the text, so a reader that only walked the keyed list had nothing
	// to attach a hint to.
	assert init_elements('fn f() {\n	p := Point{ 1, 2 }\n}\n') == ['1', '2']
	assert init_elements('fn f() {\n	p := Point{ x: 1, y: 2 }\n}\n') == ['x: 1', 'y: 2']
	assert init_elements('fn f() {\n	p := Point{}\n}\n') == []
}
