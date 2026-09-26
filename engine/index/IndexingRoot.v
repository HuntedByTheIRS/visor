// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module index

import time
import os
import engine.loglib
import crypto.md5

// BuiltIndexStatus describes the status of the built index.
pub enum BuiltIndexStatus {
	from_cache   // index was loaded from cache
	from_scratch // index was built from scratch
}

// IndexingRootKind describes the type of root that is being indexed.
// Same as `StubIndexKind`.
pub enum IndexingRootKind as u8 {
	standard_library
	modules
	stubs
	workspace
}

// readable_name returns a human-readable name for the root kind.
pub fn (k IndexingRootKind) readable_name() string {
	return match k {
		.standard_library { 'Standard Library' }
		.modules { 'Modules' }
		.stubs { 'Stubs' }
		.workspace { 'Workspace' }
	}
}

// IndexingRoot encapsulates the logic of indexing/reindexing a particular root of the file system.
//
// Separation into separate roots is necessary in order to process the standard library and user code separately.
@[noinit]
pub struct IndexingRoot {
pub:
	root string           // root that is indexed
	kind IndexingRootKind // type of root that is indexed
pub mut:
	cache_dir  string    // path to the directory where the index is stored
	updated_at time.Time // when the index was last updated
	index      Index     // index itself
	cache_file string    // path to the file where the index is stored
	need_save  bool      // whether the index needs to be saved
	no_save    bool      // for tests
}

// new_indexing_root creates a new indexing root with the given root and kind.
pub fn new_indexing_root(root string, kind IndexingRootKind, cache_dir string) &IndexingRoot {
	cache_file := 'v_analyzer_index_${md5.hexhash(root)}'
	return &IndexingRoot{
		root:       root
		kind:       kind
		cache_dir:  cache_dir
		cache_file: cache_file
	}
}

fn (mut i IndexingRoot) cache_file() string {
	return os.join_path(i.cache_dir, i.cache_file)
}

// load_index reads the index from its cache file, returning an error when the cache is missing, unreadable, or written by another version.
pub fn (mut i IndexingRoot) load_index() ! {
	now := time.now()
	if !os.exists(i.cache_file()) {
		loglib.with_fields({
			'root': i.root
		}).info('Index not found, start indexing')
		return IndexNotFoundError{}
	}

	data := os.read_bytes(i.cache_file()) or {
		loglib.with_fields({
			'file':  i.cache_file()
			'error': err.str()
		}).error('Failed to read index')
		return IndexNotFoundError{}
	}
	i.index.decode(data) or {
		if err is IndexVersionMismatchError {
			loglib.info('Index version mismatch')
		} else {
			loglib.with_fields({
				'file':  i.cache_file()
				'error': err.str()
			}).error('Error load index')
		}
		return NeedReindexedError{}
	}
	loglib.info('Loaded index in ${time.since(now)}')
}

// save_index writes the index to its cache file unless saving is not needed or has been turned off.
pub fn (mut i IndexingRoot) save_index() ! {
	if !i.need_save || i.no_save {
		return
	}
	i.need_save = false

	data := i.index.encode()
	os.write_file_array(i.cache_file(), data) or {
		loglib.with_fields({
			'file':  i.cache_file()
			'error': err.str()
		}).error('Failed to write analyzer index file')
		return err
	}
}

// need_index returns true if the file needs to be indexed.
//
// We deliberately do not index some of test files to speed up the indexing and searching process.
fn (mut _ IndexingRoot) need_index(path string) bool {
	if path.ends_with('.vsh') {
		return true
	}

	if !path.ends_with('.v') {
		return false
	}

	return !path.contains('/tests/') && !path.contains('/slow_tests/')
		&& !path.contains('/.vmodules/cache/')
		&& !path.contains('/builtin/wasm/') // TODO: index this folder too
		&& !path.contains('/builtin/js/') // TODO: index this folder too
		&& !path.contains('/builtin/linux_bare/') // TODO: index this folder too
		&& !path.ends_with('.js.v') && !path.contains('/.git/') && !path.ends_with('_test.v')
}
