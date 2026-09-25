// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module engine

import engine.parser
import tree_sitter_v.bindings

// Position is a zero based line and column, the way tree-sitter reports a
// point. A language server converts it to whatever the client expects.
pub struct Position {
pub:
	row    u32
	column u32
}

// Node is one node of a parse tree, without the grammar binding behind it.
// A node carries its kind, its byte span and its place in the file, and the
// nodes below it.
pub struct Node {
pub:
	kind       string
	start_byte u32
	end_byte   u32
	start      Position
	end        Position
	children   []Node
}

// ParsedFile is one file as a parser engine saw it: the text it was given and
// the tree over that text.
pub struct ParsedFile {
pub:
	path string
	text string
	root Node
}

// ParserEngine is the seam between the feature handlers and the parser. It
// answers two questions and no more: what does this file parse into, and which
// node covers this byte offset. Another implementation (a different grammar
// binding, a recorded tree, a stub) can sit behind this interface without a
// call site changing, so nothing here mentions tree-sitter types.
pub interface ParserEngine {
	parse_file(path string) !ParsedFile
	parse_source(text string, path string) ParsedFile
	node_at(file ParsedFile, offset u32) ?Node
}

// node_at_position returns the deepest node that covers offset. A node covers
// an offset when the offset is inside its byte span, and the end of the span
// itself belongs to the next node.
pub fn node_at_position(node Node, offset u32) ?Node {
	if offset < node.start_byte || offset >= node.end_byte {
		return none
	}
	for child in node.children {
		if found := node_at_position(child, offset) {
			return found
		}
	}
	return node
}

// TreeSitterParser parses V through the vendored tree-sitter grammar.
pub struct TreeSitterParser {
mut:
	v_parser &parser.Parser = unsafe { nil }
}

pub fn new_parser_engine() &TreeSitterParser {
	return &TreeSitterParser{
		v_parser: parser.Parser.new()
	}
}

pub fn (mut p TreeSitterParser) parse_file(path string) !ParsedFile {
	res := p.v_parser.parse_file(path)!
	return ParsedFile{
		path: path
		text: res.source_text
		root: node_from_binding(res.tree.root_node())
	}
}

pub fn (p &TreeSitterParser) parse_source(text string, path string) ParsedFile {
	// The binding parser is reached through a pointer, so this copy still
	// writes to the one parser this engine owns.
	mut v_parser := p.v_parser
	res := v_parser.parse_source(parser.Source(text))
	return ParsedFile{
		path: path
		text: res.source_text
		root: node_from_binding(res.tree.root_node())
	}
}

pub fn (p &TreeSitterParser) node_at(file ParsedFile, offset u32) ?Node {
	return node_at_position(file.root, offset)
}

pub fn (mut p TreeSitterParser) free() {
	p.v_parser.free()
}

// node_from_binding copies a tree-sitter node into the plain data the handlers
// get, so that a parsed file stays readable after the tree is freed.
fn node_from_binding(node bindings.Node[bindings.NodeType]) Node {
	mut children := []Node{}
	for i in 0 .. node.child_count() {
		if child := node.child(i) {
			children << node_from_binding(child)
		}
	}
	return Node{
		kind:       node.type_name.str()
		start_byte: node.start_byte()
		end_byte:   node.end_byte()
		start:      position_from_binding(node.start_point())
		end:        position_from_binding(node.end_point())
		children:   children
	}
}

fn position_from_binding(point bindings.TSPoint) Position {
	return Position{
		row:    point.row
		column: point.column
	}
}
