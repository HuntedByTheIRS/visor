module features

import engine.parser
import engine.psi

// The buffer holds one of every declaration the outline knows about, including
// a method whose receiver type is declared in another file.
const symbols_fixture = 'module main

import os

struct Point {
	x int
	y int
}

enum Color {
	red = 1
	green
}

interface Shape {
	kind string
	area() f64
}

type Numbers = map[string]int

const (
	start = 1
	stop  = 10
)

__global (
	seen int
)

pub fn (p Point) scale(factor int) Point {
	return Point{p.x * factor, p.y * factor}
}

fn (p &Point) offset() int {
	return p.x
}

pub fn free_function() int {
	return 1
}

fn (l Logger) write(line string) {
	println(line)
}
'

// outline_entries is the outline flattened one level, with the members of a
// type indented under it: what a reader sees in an editor's outline panel.
fn outline_entries(symbols []DocSymbol) []string {
	mut lines := []string{}
	for symbol in symbols {
		lines << symbol.name
		for child in symbol.children {
			lines << '  ${child.name}'
		}
	}
	return lines
}

// symbols_of parses a buffer and returns its outline. No folder is indexed:
// nothing in the lane needs one.
fn symbols_of(text string) []DocSymbol {
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	parsed := p.parse_code(text)
	file := psi.new_psi_file('/tmp/visor-features-symbols-fixture.v', parsed.tree,
		parsed.source_text)
	return document_symbols(file)
}

// find_symbol looks an entry up by name, at the top level or under a type.
fn find_symbol(symbols []DocSymbol, name string) ?DocSymbol {
	for symbol in symbols {
		if symbol.name == name {
			return symbol
		}
		for child in symbol.children {
			if child.name == name {
				return child
			}
		}
	}
	return none
}

// offset_of_needle is where a piece of the fixture sits, computed from the text
// rather than written down, so editing the fixture cannot move a spuriously
// passing expectation.
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

fn test_the_outline_reads_like_the_file() {
	symbols := symbols_of(symbols_fixture)
	entries := outline_entries(symbols)
	println('the outline drew: ${entries}')
	assert entries == [
		'main',
		'Point',
		'  x',
		'  y',
		'  scale',
		'  offset',
		'Color',
		'  red',
		'  green',
		'Shape',
		'  kind',
		'  area',
		'Numbers',
		'start',
		'stop',
		'seen',
		'free_function',
		'write',
	]
}

fn test_a_declaration_carries_the_kind_the_protocol_draws() {
	symbols := symbols_of(symbols_fixture)
	assert find_symbol(symbols, 'main')?.kind == .module
	assert find_symbol(symbols, 'Point')?.kind == .struct_
	assert find_symbol(symbols, 'Color')?.kind == .enum_
	assert find_symbol(symbols, 'Shape')?.kind == .interface_
	assert find_symbol(symbols, 'Numbers')?.kind == .class
	assert find_symbol(symbols, 'start')?.kind == .constant
	assert find_symbol(symbols, 'seen')?.kind == .variable
	assert find_symbol(symbols, 'free_function')?.kind == .function
	// a method is a method whether it hangs under its type or not
	assert find_symbol(symbols, 'scale')?.kind == .method
	assert find_symbol(symbols, 'write')?.kind == .method
	assert find_symbol(symbols, 'x')?.kind == .field
	assert find_symbol(symbols, 'red')?.kind == .enum_member
	assert find_symbol(symbols, 'area')?.kind == .method
}

// A method belongs to the type it is declared on, whichever way the receiver is
// written. The reference marker and the mut keyword are not part of the name.
fn test_a_method_hangs_under_the_type_its_receiver_names() {
	symbols := symbols_of(symbols_fixture)
	point := find_symbol(symbols, 'Point')?
	mut members := []string{cap: point.children.len}
	for child in point.children {
		assert child.kind == .field || child.kind == .method
		members << child.name
	}
	assert members == ['x', 'y', 'scale', 'offset']
	// and it sits under nothing else
	for symbol in symbols {
		if symbol.name == 'write' {
			assert symbol.children.len == 0
		}
	}
}

// A method whose type is declared somewhere else still gets an entry, named
// with the receiver it belongs to. Dropping it would hide a declaration the
// file makes.
fn test_a_method_for_an_unknown_receiver_stays_at_the_top_level() {
	symbols := symbols_of(symbols_fixture)
	write := find_symbol(symbols, 'write')?
	assert write.detail.starts_with('(Logger)')
}

fn test_the_names_are_where_the_text_says_they_are() {
	symbols := symbols_of(symbols_fixture)
	point := find_symbol(symbols, 'Point')?
	want := offset_of_needle(symbols_fixture, 'struct Point', 0) + 'struct '.len
	assert point.name_start == want
	assert point.name_end == want + 'Point'.len

	// the whole declaration covers the body, and the name does not
	assert point.start == offset_of_needle(symbols_fixture, 'struct Point', 0)
	assert point.end > point.name_end

	// a method name is the name, not the whole declaration
	scale := find_symbol(symbols, 'scale')?
	scale_at := offset_of_needle(symbols_fixture, 'fn (p Point) scale', 0) + 'fn (p Point) '.len
	assert scale.name_start == scale_at
	assert scale.name_end == scale_at + 'scale'.len
	assert scale.start < scale.name_start
}

fn test_the_detail_is_what_the_declaration_says_after_its_name() {
	symbols := symbols_of(symbols_fixture)
	assert find_symbol(symbols, 'scale')?.detail == '(factor int) Point'
	assert find_symbol(symbols, 'x')?.detail == 'int'
	assert find_symbol(symbols, 'red')?.detail == '= 1'
	assert find_symbol(symbols, 'Numbers')?.detail == '= map[string]int'
	assert find_symbol(symbols, 'stop')?.detail == '= 10'
	// a struct says nothing before its brace, so its detail is not its body
	assert find_symbol(symbols, 'Point')?.detail == ''
	assert find_symbol(symbols, 'Color')?.detail == ''
	// and the module clause has nothing after its name at all
	assert find_symbol(symbols, 'main')?.detail == ''
}

// An empty file is an empty outline rather than an error: there is nothing to
// say about a buffer with no declarations in it.
fn test_a_buffer_with_nothing_in_it_has_no_entries() {
	assert symbols_of('').len == 0
	assert symbols_of('module main\n').len == 1
}
