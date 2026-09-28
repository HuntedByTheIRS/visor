// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module engine

import engine.psi

pub struct IndexingManager {
pub mut:
	indexer    &Indexer = unsafe { nil }
	stub_index psi.StubIndex
}

// IndexingManager.new creates an indexing manager with a fresh indexer.
pub fn IndexingManager.new() &IndexingManager {
	indexer := new_indexer()
	return &IndexingManager{
		indexer: indexer
	}
}

// setup_empty_indexes installs an empty stub index and makes it the global one.
pub fn (mut a IndexingManager) setup_empty_indexes() {
	a.stub_index = psi.new_stubs_index([])
	stubs_index = a.stub_index
}

// setup_stub_indexes builds a stub index from the current roots and makes it the global one.
pub fn (mut a IndexingManager) setup_stub_indexes() {
	mut sinks := a.all_sinks()
	a.stub_index = psi.new_stubs_index(sinks)
	stubs_index = a.stub_index
}

// refresh_file replaces one file's stubs with the ones the content parses to
// and rebuilds the workspace index, so a buffer nobody has saved answers the
// questions a saved file answers. Nothing reaches the disk.
//
// False means no root owns the path, which a caller has to tell apart from a
// refresh that ran: a buffer outside every root is a buffer this index cannot
// describe, and answering from the file that happens to sit at its path would
// describe a different text.
pub fn (mut a IndexingManager) refresh_file(path string, content string) !bool {
	mut refreshed := false
	for mut root in a.indexer.roots {
		if !root.contains(path) {
			continue
		}
		refreshed = root.refresh_stub_file(path, content)!
		break
	}
	if !refreshed {
		return false
	}
	a.setup_stub_indexes()
	return true
}

// update_stub_indexes_from_sinks refreshes the global stub index for the given sinks.
pub fn (mut a IndexingManager) update_stub_indexes_from_sinks(changed_sinks []psi.StubIndexSink) {
	all_sinks := a.all_sinks()
	stubs_index.update_stubs_index(changed_sinks, all_sinks)
}

// update_stub_indexes refreshes the global stub index for the given files, looking each sink up by path.
pub fn (mut a IndexingManager) update_stub_indexes(changed_files []&psi.PsiFile) {
	all_sinks := a.all_sinks()
	mut changed_sinks := []psi.StubIndexSink{cap: changed_files.len}

	for root in a.indexer.roots {
		for file in changed_files {
			file_cache := root.index.per_file.data[file.path] or { continue }
			changed_sinks << file_cache.sink
		}
	}

	stubs_index.update_stubs_index(changed_sinks, all_sinks)
}

fn (mut a IndexingManager) all_sinks() []psi.StubIndexSink {
	mut sinks := []psi.StubIndexSink{cap: a.indexer.roots.len * 30}
	for root in a.indexer.roots {
		sinks << root.index.per_file.get_sinks()
	}
	return sinks
}
