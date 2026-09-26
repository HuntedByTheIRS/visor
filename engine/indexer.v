// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module engine

import os
import time
import engine.loglib
import engine.index

// IndexingRootsStatus describes the indexing status of all roots.
pub enum IndexingRootsStatus {
	all_indexed
	needs_ensure_indexed // when at least one of the indexes was taken from the cache
}

// Indexer encapsulates the indexing logic and provides an interface for working with the index.
pub struct Indexer {
pub mut:
	roots   []&index.IndexingRoot
	no_save bool
}

// new_indexer returns an indexer with no roots.
pub fn new_indexer() &Indexer {
	return &Indexer{}
}

// set_no_save controls whether indexes are written to disk: true keeps them in memory
// only, on the indexer and on every root it holds.
pub fn (mut i Indexer) set_no_save(value bool) {
	i.no_save = value
	for mut root in i.roots {
		root.no_save = value
	}
}

// count_roots returns how many indexing roots the indexer holds.
pub fn (i Indexer) count_roots() int {
	return i.roots.len
}

// add_indexing_root adds a root to index, together with the directory its cache is stored in.
pub fn (mut i Indexer) add_indexing_root(root string, kind index.IndexingRootKind, cache_dir string) {
	loglib.with_fields({
		'root': root
	}).info('Adding indexing root')
	i.roots << index.new_indexing_root(root, kind, cache_dir)
}

// index indexes every root, calling on_start with each root as its turn comes, and reports
// whether every index was ready or at least one was loaded from the cache.
pub fn (mut i Indexer) index(on_start fn (root index.IndexingRoot, index int)) IndexingRootsStatus {
	now := time.now()
	loglib.info('Indexing ${i.roots.len} roots')

	mut need_ensure_indexed := false

	for index, mut indexing_root in i.roots {
		on_start(*indexing_root, index + 1)
		status := indexing_root.index()
		if status == .from_cache {
			// If at least one of the indexes was taken from the cache,
			// then we need to make sure that all indexes are up to date.
			need_ensure_indexed = true
		}
	}

	loglib.with_duration(time.since(now)).info('Indexing all roots')

	return if need_ensure_indexed {
		.needs_ensure_indexed
	} else {
		.all_indexed
	}
}

// ensure_indexed brings every root up to date after an index was taken from the cache.
pub fn (mut i Indexer) ensure_indexed() {
	now := time.now()
	loglib.info('Ensure indexed of ${i.roots.len} roots')

	for mut indexing_root in i.roots {
		indexing_root.ensure_indexed()
	}

	loglib.with_duration(time.since(now)).info('Ensure indexed of all roots')
}

// save_indexes writes every root's index to disk, unless saving was turned off.
pub fn (mut i Indexer) save_indexes() ! {
	if i.no_save {
		return
	}

	for mut indexing_root in i.roots {
		indexing_root.save_index() or {
			loglib.with_fields({
				'root': indexing_root.root
				'err':  err.str()
			}).error('Failed to save index')
			return err
		}
	}
}

// mark_as_dirty tells the roots that a file changed and hands them its new content.
pub fn (mut i Indexer) mark_as_dirty(filepath string, new_content string) ! {
	for mut indexing_root in i.roots {
		indexing_root.mark_as_dirty(filepath, new_content)!
	}
}

// add_file reads a file and adds it to the root that contains it, or none when no root does.
pub fn (mut i Indexer) add_file(path string) ?index.FileIndex {
	content := os.read_file(path) or {
		loglib.with_fields({
			'path': path
			'err':  err.str()
		}).error('Failed to read new file')
		return none
	}

	for mut root in i.roots {
		if root.contains(path) {
			return root.add_file(path, content) or {
				loglib.with_fields({
					'root': root.root
					'path': path
					'err':  err.str()
				}).error('Failed to add new file')
				return none
			}
		}
	}

	return none
}

// rename_file rewrites the index entry for a file that moved, or none when no root contains it.
pub fn (mut i Indexer) rename_file(old_path string, new_path string) ?index.FileIndex {
	for mut root in i.roots {
		if root.contains(old_path) {
			return root.rename_file(old_path, new_path) or {
				loglib.with_fields({
					'root':     root.root
					'old_path': old_path
					'new_path': new_path
					'err':      err.str()
				}).error('Failed to rename file')
				return none
			}
		}
	}

	return none
}

// remove_file drops a file from the root that contains it, or none when no root does.
pub fn (mut i Indexer) remove_file(path string) ?index.FileIndex {
	for mut root in i.roots {
		if root.contains(path) {
			return root.remove_file(path) or {
				loglib.with_fields({
					'root': root.root
					'path': path
					'err':  err.str()
				}).error('Failed to remove file')
				return none
			}
		}
	}

	return none
}
