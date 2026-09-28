module features

import engine
import engine.psi
import os

// A project of two files with one of every declaration a search can return: a
// public function, a private one, a type with a field, an enum with members, a
// constant, a type alias and a global.
const search_helper = 'module main

pub fn helper() int {
	return 1
}

fn hidden() int {
	return 0
}

pub const limit = 10

__global counter int
'

const search_types = 'module main

pub struct Config {
	pub:
	name string
}

pub enum Mode {
	fast
	slow
}

pub type Pair = []string
'

// search_project writes the two files and indexes the folder, which is what a
// session has after a client opens a workspace.
fn search_project(name string) &engine.Session {
	dir := os.join_path(os.temp_dir(), 'visor-features-search-test-${name}')
	os.mkdir_all(dir) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'helper.v'), search_helper) or { panic(err.msg()) }
	os.write_file(os.join_path(dir, 'types.v'), search_types) or { panic(err.msg()) }
	mut session := engine.new_session()
	session.index_root(dir, os.join_path(dir, '.cache'))
	return session
}

// searchable is the candidate list the lane hands to the ranking: every
// declaration the index holds, each named with the module it belongs to and
// listed once.
fn searchable(mut session engine.Session) []WorkspaceSymbol {
	stubs := session.manager.stub_index
	mut candidates := []WorkspaceSymbol{}
	mut seen := map[string]bool{}
	for element in stubs.get_all_elements_from(.workspace) {
		path := element_path(element) or { continue }
		container := stubs.get_module_qualified_name(path)
		symbol := workspace_symbol_of(element, container) or { continue }
		key := symbol_identity(symbol)
		if seen[key] {
			continue
		}
		seen[key] = true
		candidates << symbol
	}
	return candidates
}

// names_of is a ranked answer as plain names, in the order the lane sends them.
fn names_of(symbols []WorkspaceSymbol) []string {
	mut names := []string{cap: symbols.len}
	for symbol in symbols {
		names << symbol.name
	}
	return names
}

// name_symbol finds one candidate by name.
fn name_symbol(symbols []WorkspaceSymbol, name string) ?WorkspaceSymbol {
	for symbol in symbols {
		if symbol.name == name {
			return symbol
		}
	}
	return none
}

fn test_the_search_covers_every_kind_of_declaration() {
	mut session := search_project('kinds')
	candidates := searchable(mut session)
	assert name_symbol(candidates, 'helper')?.kind == .function
	assert name_symbol(candidates, 'hidden')?.kind == .function
	assert name_symbol(candidates, 'Config')?.kind == .struct_
	assert name_symbol(candidates, 'name')?.kind == .field
	assert name_symbol(candidates, 'Mode')?.kind == .enum_
	assert name_symbol(candidates, 'limit')?.kind == .constant
	assert name_symbol(candidates, 'Pair')?.kind == .class
	assert name_symbol(candidates, 'counter')?.kind == .variable
}

// The search lists what the index holds, and the index holds no enum member: a
// stub is built for one, but no index key records it, so there is nothing for a
// search to find. The outline does list them, because it reads the parse rather
// than the index, and this test is where the two are known to disagree.
fn test_an_enum_member_is_not_in_the_index_to_be_found() {
	mut session := search_project('enum-members')
	candidates := searchable(mut session)
	assert name_symbol(candidates, 'Mode')?.kind == .enum_
	if symbol := name_symbol(candidates, 'fast') {
		assert false, 'the index now holds enum members (${symbol.kind}), so the search can list them'
	}
}

// Every entry says which file it is in and where in that file its name sits, so
// a client can jump without asking again.
fn test_a_candidate_carries_the_file_and_the_place_in_it() {
	mut session := search_project('places')
	candidates := searchable(mut session)
	helper := name_symbol(candidates, 'helper')?
	assert helper.path.ends_with('helper.v')
	assert helper.container == 'main'
	// `pub fn helper` puts the name seven columns in, on the third line, and
	// the answer is a range rather than a position so a client can select it.
	assert helper.range.line == 2
	assert helper.range.column == 7
	assert helper.range.end_column == 13
	config := name_symbol(candidates, 'Config')?
	assert config.path.ends_with('types.v')
	assert config.range.line == 2
	assert config.range.column == 11
}

// The index files one declaration under several keys, so the same name arrives
// more than once. Listing it once per key would read as a workspace with
// duplicates in it.
fn test_one_declaration_is_one_candidate() {
	mut session := search_project('duplicates')
	candidates := searchable(mut session)
	mut seen := map[string]int{}
	for candidate in candidates {
		key := symbol_identity(candidate)
		seen[key]++
	}
	for key, count in seen {
		assert count == 1, 'the same declaration was listed ${count} times: ${key}'
	}
}

fn test_a_query_matches_by_name_before_it_matches_by_letters() {
	assert symbol_rank('greet', 'greet') == 0
	assert symbol_rank('Greeting', 'greet') == 1
	assert symbol_rank('body_of', 'dy') == 2
	assert symbol_rank('workspace_symbol', 'wsym') == 3
	assert symbol_rank('greet', 'zzz') == -1
	// an empty query is not a filter: it is the whole list, at one rank
	assert symbol_rank('anything', '') == 4
}

fn test_the_answer_comes_back_best_first() {
	mut session := search_project('ranks')
	candidates := searchable(mut session)
	// `limit` is the exact name, and nothing else in the fixture starts with
	// those letters, so it is the whole answer to that query
	assert names_of(rank_symbols('limit', candidates, 10)) == ['limit']
	// a prefix beats a name that only contains the query
	ranked := rank_symbols('mode', candidates, 10)
	assert names_of(ranked) == ['Mode']
	// letters in order still find a name that spells them out
	assert names_of(rank_symbols('cfg', candidates, 10)) == ['Config']
	// and a query nothing answers is an empty list, not an error
	assert rank_symbols('nothinghere', candidates, 10).len == 0
}

fn test_the_shorter_name_comes_first_within_a_rank() {
	// built by hand: the fixture's names are not chosen for this question
	candidates := [
		WorkspaceSymbol{
			name:      'greeter_helper'
			kind:      .function
			container: 'main'
			path:      '/w/a.v'
			range:     offset_range(1, 0, 4)
		},
		WorkspaceSymbol{
			name:      'greet'
			kind:      .function
			container: 'main'
			path:      '/w/b.v'
			range:     offset_range(2, 0, 4)
		},
		WorkspaceSymbol{
			name:      'greeting'
			kind:      .function
			container: 'main'
			path:      '/w/c.v'
			range:     offset_range(3, 0, 4)
		},
	]
	assert names_of(rank_symbols('greet', candidates, 10)) == ['greet', 'greeting', 'greeter_helper']
}

// An empty query is a client asking what is here, so the answer is the
// workspace in name order, capped by the limit it was given.
fn test_an_empty_query_lists_the_workspace_up_to_the_limit() {
	mut session := search_project('everything')
	candidates := searchable(mut session)
	all := rank_symbols('', candidates, 100)
	assert all.len == candidates.len
	// name order comes out of the ranking, and only the asked-for prefix is cut
	limited := rank_symbols('', candidates, 3)
	assert limited.len == 3
	assert names_of(limited) == names_of(all)[..3]
	// the shorter name is first, and equal lengths are alphabetical
	assert names_of(limited) == ['Mode', 'Pair', 'main']
}

// offset_range builds a range for a candidate made up in a test rather than read
// out of an index.
fn offset_range(line int, start int, stop int) psi.TextRange {
	return psi.TextRange{
		line:       line
		column:     start
		end_line:   line
		end_column: stop
	}
}
