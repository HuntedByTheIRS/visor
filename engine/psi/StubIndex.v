// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

@[has_globals; translated]
module psi

import time
import engine.loglib

__global stubs_index = StubIndex{}

const count_index_keys = 15 // StubIndexKey

const count_stub_index_location_keys = 5 // StubIndexLocationKind

// StubIndexLocationKind describes the type of index.
// same as `IndexingRootKind`
pub enum StubIndexLocationKind {
	standard_library
	modules
	stubs
	workspace
}

pub struct StubIndex {
pub mut:
	sinks []StubIndexSink
	// module_to_files describes how to map the full name of a module to a list
	// of files that this module contains.
	module_to_files map[string][]StubIndexSink
	// file_to_module describes the mapping of a file path to the full name
	// of the module that this file belongs to.
	file_to_module map[string]string
	// data defines the index data that allows you to get the description of the element
	// in 2 accesses to the array elements and one lookup by key.
	data [count_stub_index_location_keys][count_index_keys]map[string]StubResult
	// all_elements_by_modules contains all top-level elements in the module.
	all_elements_by_modules [count_stub_index_location_keys]map[string][]PsiElement
	// types_by_modules contains all top-level types in the module.
	types_by_modules [count_stub_index_location_keys]map[string][]PsiElement
}

// new_stubs_index builds an index over sinks and fills it from them.
pub fn new_stubs_index(sinks []StubIndexSink) &StubIndex {
	mut index := &StubIndex{
		sinks:           sinks
		module_to_files: map[string][]StubIndexSink{}
	}

	// The fixed arrays of maps and the lookup array are built here instead of in
	// the literal, because V 0.5.2 miscompiles a fixed array of maps written as
	// `unsafe { [n]map[...]{} }` inside a struct literal. It emits
	// `memcpy(field, {new_map(...), ...}, sizeof(field))`: a bare brace list where
	// C needs an expression, so cc rejects the file with "expected expression
	// before '{'" and a memcpy arity error. Dropping `unsafe` fixes the C but
	// warns about the late initialisation, so the arrays are filled by hand.
	for i in 0 .. count_stub_index_location_keys {
		index.all_elements_by_modules[i] = map[string][]PsiElement{}
		index.types_by_modules[i] = map[string][]PsiElement{}
		for j in 0 .. count_index_keys {
			index.data[i][j] = map[string]StubResult{}
		}
	}

	watch := time.new_stopwatch(auto_start: true)
	for sink in sinks {
		index.update_index_from_sink(sink)
	}

	loglib.with_duration(watch.elapsed()).log_one(.info, 'Build stubs index')
	return index
}

struct StubResult {
mut:
	stubs []&StubBase
	psis  []PsiElement
}
