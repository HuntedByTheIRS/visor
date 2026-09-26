module bindings

// This file contains the bindings for C API of tree-sitter.
// They are intended to be used by wrapper functions in "bindings.v".
//
// See "core/lib/include/tree_sitter/api.h" for function references.

// We directly build "lib.c" rather using the static library.
#flag -I @VMODROOT/tree_sitter_v/bindings/core/lib/include
#flag -I @VMODROOT/tree_sitter_v/bindings/core/lib/src
#flag @VMODROOT/tree_sitter_v/bindings/core/lib/src/lib.c
#include "tree_sitter/api.h"

#flag -I @VMODROOT/tree_sitter_v/bindings
#flag -I @VMODROOT/tree_sitter_v/src
#flag @VMODROOT/tree_sitter_v/src/parser.c
#include "bindings.h"

pub type TSDecodeFunction = fn (string, u32, &int) u32

pub enum TSVInputEncoding {
	utf8
	utf16le
	utf16be
	custom
}

pub type C.TSInputEncoding = TSVInputEncoding

@[typedef]
pub struct C.TSInput {
mut:
	payload  voidptr
	read     fn (payload voidptr, byte_index u32, position C.TSPoint, bytes_read &u32) &char
	encoding C.TSInputEncoding
	decode   TSDecodeFunction
}

@[typedef]
pub struct C.TSLanguage {}

@[typedef]
pub struct C.TSParser {}

fn C.tree_sitter_v() &C.TSLanguage
fn C.ts_parser_new() &C.TSParser
fn C.ts_parser_set_language(parser &C.TSParser, language &C.TSLanguage) bool
fn C.ts_parser_parse_string(parser &C.TSParser, const_old_tree &C.TSTree, str &char, len u32) &C.TSTree
fn C.ts_parser_parse(parser &C.TSParser, const_old_tree &C.TSTree, input C.TSInput) &C.TSTree
fn C.ts_parser_delete(tree &C.TSParser)
fn C.ts_parser_reset(parser &C.TSParser)

@[inline]
fn new_ts_parser() &C.TSParser {
	return C.ts_parser_new()
}

@[inline]
fn (mut p C.TSParser) parse(old_tree &TSTree, input C.TSInput) &TSTree {
	return unsafe { &TSTree(C.ts_parser_parse(p, voidptr(old_tree), input)) }
}

@[inline]
fn (mut p C.TSParser) reset() {
	C.ts_parser_reset(p)
}

@[inline]
fn (mut p C.TSParser) set_language(language &C.TSLanguage) bool {
	return C.ts_parser_set_language(p, language)
}

@[inline]
fn (mut p C.TSParser) parse_string(content string) &TSTree {
	return p.parse_string_with_old_tree(content, &TSTree(unsafe { nil }))
}

@[inline]
fn (mut p C.TSParser) parse_string_with_old_tree(content string, old_tree &TSTree) &TSTree {
	return p.parse_string_with_old_tree_and_len(content, old_tree, u32(content.len))
}

@[inline]
fn (mut p C.TSParser) parse_string_with_old_tree_and_len(content string, old_tree &TSTree, len u32) &TSTree {
	return unsafe { &TSTree(C.ts_parser_parse_string(p, voidptr(old_tree), &char(content.str), len)) }
}

@[inline]
fn (mut p C.TSParser) parse_bytes(content []u8) &TSTree {
	return p.parse_bytes_with_old_tree(content, &TSTree(unsafe { nil }))
}

// byte_array_input_read is the read callback for a parser fed from a byte
// array. The TSPoint argument is part of the C signature and goes unused here.
fn byte_array_input_read(pl voidptr, byte_index u32, _ C.TSPoint, bytes_read &u32) &char {
	payload := unsafe { *(&[]u8(pl)) }
	if byte_index >= u32(payload.len) {
		unsafe {
			*bytes_read = 0
		}
		return c''
	} else {
		unsafe {
			*bytes_read = u32(payload.len) - byte_index
		}
		return unsafe { &char(payload.data) + byte_index }
	}
}

fn (mut p C.TSParser) parse_bytes_with_old_tree(content []u8, old_tree &TSTree) &TSTree {
	return p.parse(old_tree,
		payload:  &content
		read:     byte_array_input_read
		encoding: TSVInputEncoding.utf8
	)
}

@[inline; unsafe]
fn (p &C.TSParser) delete() {
	unsafe {
		C.ts_parser_delete(p)
	}
}

@[typedef]
pub struct C.TSLanguage {}

pub struct C.TSTree {
	included_range_count u32
}

@[export: 'TSTree']
pub struct TSTree {
	included_range_count u32
}

fn C.ts_tree_copy(tree &C.TSTree) &C.TSTree
fn C.ts_tree_root_node(tree &C.TSTree) C.TSNode
fn C.ts_tree_delete(tree &C.TSTree)
fn C.ts_tree_edit(tree &C.TSTree, edit &C.TSInputEdit)
fn C.ts_tree_get_changed_ranges(old_tree &C.TSTree, new_tree &C.TSTree, count &u32) &C.TSRange

@[inline]
fn (tree &TSTree) copy() &TSTree {
	return unsafe { &TSTree(C.ts_tree_copy(voidptr(tree))) }
}

@[inline]
fn (tree &TSTree) root_node() C.TSNode {
	return C.ts_tree_root_node(unsafe { &C.TSTree(tree) })
}

@[inline]
fn (tree &TSTree) edit(input_edit &C.TSInputEdit) {
	C.ts_tree_edit(unsafe { &C.TSTree(tree) }, input_edit)
}

fn (tree &TSTree) get_changed_ranges(new_tree &TSTree) []C.TSRange {
	mut len := u32(0)
	buf := C.ts_tree_get_changed_ranges(unsafe { &C.TSTree(tree) }, unsafe { &C.TSTree(new_tree) },
		&len)
	element_size := int(sizeof(C.TSRange))

	return unsafe {
		array{
			element_size: element_size
			len:          int(len)
			cap:          int(len)
			data:         buf
		}
	}
}

@[unsafe]
fn (tree &TSTree) free() {
	unsafe {
		C.ts_tree_delete(&C.TSTree(tree))
	}
}

@[typedef]
pub struct C.TSInputEdit {
	start_byte    u32
	old_end_byte  u32
	new_end_byte  u32
	start_point   C.TSPoint
	old_end_point C.TSPoint
	new_end_point C.TSPoint
}

@[typedef]
pub struct C.TSPoint {
pub:
	row    u32
	column u32
}

fn (left_point C.TSPoint) eq(right_point C.TSPoint) bool {
	return left_point.row == right_point.row && left_point.column == right_point.column
}

@[typedef]
pub struct C.TSRange {
pub:
	start_point C.TSPoint
	end_point   C.TSPoint
	start_byte  u32
	end_byte    u32
}

fn (left_range C.TSRange) eq(right_range C.TSRange) bool {
	// The two points are fields of a C struct, and V 0.5.2 does not resolve a
	// method on those, so the point comparison is spelled out.
	return left_range.start_point.row == right_range.start_point.row
		&& left_range.start_point.column == right_range.start_point.column
		&& left_range.end_point.row == right_range.end_point.row
		&& left_range.end_point.column == right_range.end_point.column
		&& left_range.start_byte == right_range.start_byte
		&& left_range.end_byte == right_range.end_byte
}

// ts_parser_parse_string parses source under an optional old tree and
// returns the new tree.
pub fn ts_parser_parse_string(parser &C.TSParser, source string, old_tree &TSTree) &TSTree {
	return unsafe { &TSTree(C.ts_parser_parse_string(parser, voidptr(old_tree), &char(source.str), u32(source.len))) }
}
