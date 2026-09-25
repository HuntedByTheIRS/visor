module engine

import os
import engine.parser
import tree_sitter_v.bindings

// The corpus is a pinned list of production files from the vlib of the V
// compiler that runs the test, named relative to that vlib directory. The
// numbers in CORPUS.md come from this list, and running the file re-measures
// them against whatever `v` is on PATH.
//
// The list was measured against V 0.5.2, commit 1b68924. It is pinned on
// purpose: a missing file or a file that stops parsing fails the test instead
// of quietly shrinking the corpus.
const corpus_files = [
	'builtin/string.v',
	'builtin/array.v',
	'builtin/map.v',
	'builtin/autostr.v',
	'os/os.v',
	'os/process.v',
	'strings/similarity.v',
	'strings/builder.c.v',
	'arrays/arrays.v',
	'maps/maps.v',
	'datatypes/stack.v',
	'datatypes/fsm/fsm.v',
	'datatypes/bloom_filter.v',
	'datatypes/doubly_linked_list.v',
	'math/bits/bits.v',
	'math/big/big.v',
	'time/time.v',
	'flag/flag.v',
	'cli/command.v',
	'encoding/base64/base64.v',
	'encoding/hex/hex.v',
	'crypto/sha256/sha256.v',
	'sync/once.v',
	'sync/cond.v',
	'context/context.v',
	'io/buffered_reader.v',
	'v/token/token.v',
	'v/scanner/scanner.v',
	'v/parser/parser.v',
	'term/term.v',
]

// The measured state of the corpus, not the target. The target is zero ERROR
// nodes and zero MISSING nodes; this grammar does not get there on this corpus
// yet, and CORPUS.md records where the damage sits. The constants ratchet: a
// change that parses less of the corpus fails here, and a change that parses
// more has to lower them and update the report.
const corpus_error_baseline = 34

const corpus_missing_baseline = 11

// NodeTally counts the nodes of a tree and how many of them the grammar could
// not place.
struct NodeTally {
mut:
	errors  int
	missing int
	nodes   int
}

fn tally_seam_nodes(node Node, mut tally NodeTally) {
	tally.nodes++
	if node.kind == 'ERROR' {
		tally.errors++
	}
	for child in node.children {
		tally_seam_nodes(child, mut tally)
	}
}

// tally_binding_nodes counts what the seam cannot see. `Node` carries a kind and
// a span and nothing else, so a token the grammar inserted to recover is
// invisible through `TreeSitterParser` and has to be counted against the
// binding.
fn tally_binding_nodes(node bindings.Node[bindings.NodeType], mut tally NodeTally) {
	tally.nodes++
	if node.type_name == .error {
		tally.errors++
	}
	if node.is_missing() {
		tally.missing++
	}
	for i in 0 .. node.child_count() {
		if child := node.child(i) {
			tally_binding_nodes(child, mut tally)
		}
	}
}

// vlib_root finds the vlib directory that belongs to the `v` on PATH, which is
// the compiler the grammar is pinned against.
fn vlib_root() string {
	v_exe := os.find_abs_path_of_executable('v') or {
		panic('no `v` on PATH, so the corpus cannot be located')
	}
	root := os.join_path(os.dir(os.real_path(v_exe)), 'vlib')
	if !os.is_dir(root) {
		panic('no vlib directory next to ${v_exe}')
	}
	return root
}

// A clean corpus proves nothing if the counter never fires, so the damaged
// buffers run first. The first grammar reports a missing token rather than an
// ERROR node, the second and third are the kind that does turn into one.
fn test_the_counters_react_to_damaged_buffers() {
	mut parse_engine := new_parser_engine()
	defer {
		parse_engine.free()
	}

	damaged := ['fn main() {\n\tx := \n}\n', '@#$%^&*\n', 'if x { }\n}\n']
	for i, source in damaged {
		file := parse_engine.parse_source(source, 'damaged_${i}.v')
		mut tally := NodeTally{}
		tally_seam_nodes(file.root, mut tally)
		println('damaged buffer ${i}: nodes=${tally.nodes} error=${tally.errors}')
		if i > 0 {
			assert tally.errors > 0
		}
	}

	mut binding_parser := parser.Parser.new()
	defer {
		binding_parser.free()
	}
	res := binding_parser.parse_source(parser.Source(damaged[0]))
	mut tally := NodeTally{}
	tally_binding_nodes(res.tree.root_node(), mut tally)
	println('damaged buffer 0 through the binding: nodes=${tally.nodes} error=${tally.errors} missing=${tally.missing}')
	assert tally.missing > 0
}

fn test_the_pinned_corpus_keeps_its_error_count() {
	root := vlib_root()

	mut parse_engine := new_parser_engine()
	defer {
		parse_engine.free()
	}

	mut binding_parser := parser.Parser.new()
	defer {
		binding_parser.free()
	}

	mut seam_total := NodeTally{}
	mut binding_total := NodeTally{}
	mut total_lines := 0
	mut missing_files := []string{cap: 4}
	println('| file | lines | nodes | ERROR | MISSING |')
	println('| --- | --- | --- | --- | --- |')
	for rel in corpus_files {
		path := os.join_path(root, rel)
		if !os.exists(path) {
			missing_files << rel
			println('| ${rel} | | | missing | missing |')
			continue
		}
		source := os.read_file(path)!
		lines := source.split_into_lines().len
		total_lines += lines

		file := parse_engine.parse_source(source, path)
		mut seam_tally := NodeTally{}
		tally_seam_nodes(file.root, mut seam_tally)
		seam_total.errors += seam_tally.errors
		seam_total.nodes += seam_tally.nodes

		res := binding_parser.parse_source(parser.Source(source))
		mut binding_tally := NodeTally{}
		tally_binding_nodes(res.tree.root_node(), mut binding_tally)
		binding_total.errors += binding_tally.errors
		binding_total.missing += binding_tally.missing
		binding_total.nodes += binding_tally.nodes

		assert seam_tally.nodes == binding_tally.nodes
		assert seam_tally.errors == binding_tally.errors

		println('| ${rel} | ${lines} | ${seam_tally.nodes} | ${seam_tally.errors} | ${binding_tally.missing} |')
	}
	println('| ${corpus_files.len} files | ${total_lines} | ${seam_total.nodes} | ${seam_total.errors} | ${binding_total.missing} |')

	assert missing_files.len == 0
	assert seam_total.nodes == binding_total.nodes
	assert seam_total.errors == binding_total.errors
	assert seam_total.errors <= corpus_error_baseline
	assert binding_total.missing <= corpus_missing_baseline
}
