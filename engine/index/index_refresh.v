// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module index

import time
import os
import engine.loglib
import engine.utils
import engine.parser

// ensure_indexed checks the index for freshness and re-indexes files if they have changed since the last indexing.
pub fn (mut i IndexingRoot) ensure_indexed() {
	now := time.now()

	loglib.with_fields({
		'root': i.root
	}).info('Ensuring indexed root')

	reindex_files_chan := chan string{cap: 1000}
	cache_chan := chan FileIndex{cap: 1000}

	spawn fn [reindex_files_chan, mut i] () {
		for filepath, datum in i.index.per_file.data {
			last_modified := os.file_last_mod_unix(filepath)
			if last_modified > datum.file_last_modified {
				loglib.with_fields({
					'uri': utils.path_to_uri(filepath)
				}).info('File was modified, reindexing')
				i.index.per_file.data.delete(filepath)
				reindex_files_chan <- filepath
			}
		}

		reindex_files_chan.close()
	}()

	spawn i.spawn_indexing_workers(cache_chan, reindex_files_chan)

	mut caches := []FileIndex{cap: 100}
	for {
		cache := <-cache_chan or { break }
		caches << cache
	}

	for cache in caches {
		i.index.per_file.data[cache.path()] = cache
	}

	if caches.len > 0 {
		i.index.updated_at = time.now()
		i.need_save = true
	}

	loglib.with_duration(time.since(now)).info('Reindexing finished')
}

// mark_as_dirty reindexes a file after its content changed and saves the index; paths outside this root are ignored.
pub fn (mut i IndexingRoot) mark_as_dirty(filepath string, new_content string) ! {
	if filepath !in i.index.per_file.data {
		// file does not belong to this index
		return
	}

	loglib.with_fields({
		'uri': utils.path_to_uri(filepath)
	}).info('Marking document as dirty')
	i.index.per_file.data.delete(filepath)

	mut p := parser.Parser.new()
	defer { p.free() }
	res := i.index_file(filepath, new_content, mut p) or {
		return error('Error indexing dirty ${filepath}: ${err}')
	}
	i.index.per_file.data[filepath] = res
	i.index.updated_at = time.now()
	i.need_save = true
	i.save_index() or { return err }

	loglib.with_fields({
		'uri': utils.path_to_uri(filepath)
	}).info('Finished reindexing document')
}

// add_file indexes a newly created file, saves the index, and returns its file index.
pub fn (mut i IndexingRoot) add_file(filepath string, content string) !FileIndex {
	loglib.with_fields({
		'uri': utils.path_to_uri(filepath)
	}).info('Adding new document')

	mut p := parser.Parser.new()
	defer { p.free() }
	res := i.index_file(filepath, content, mut p) or {
		return error('Error indexing added ${filepath}: ${err}')
	}
	i.index.per_file.data[filepath] = res
	i.index.updated_at = time.now()
	i.need_save = true
	i.save_index() or { return err }

	loglib.with_fields({
		'uri': utils.path_to_uri(filepath)
	}).info('Finished indexing added document')

	if isnil(res.sink) {
		return error('Sink of added file is nil')
	}

	return res
}

// rename_file moves a file's index entry to its new path, saves the index, and returns the moved entry.
pub fn (mut i IndexingRoot) rename_file(old string, new string) !FileIndex {
	cache := i.index.per_file.rename_file(old, new) or {
		return error('cannot find file index after rename, most likely rename was failed')
	}
	i.need_save = true
	i.save_index() or { return err }
	if isnil(cache.sink) {
		return error('Sink of renamed file is nil')
	}
	return cache
}

// remove_file drops a file's index entry, saves the index, and returns the removed entry.
pub fn (mut i IndexingRoot) remove_file(path string) !FileIndex {
	cache := i.index.per_file.remove_file(path) or {
		return error('cannot find file index after remove, most likely remove was failed')
	}
	i.need_save = true
	i.save_index() or { return err }
	if isnil(cache.sink) {
		return error('Sink of removed file is nil')
	}
	return cache
}

// contains reports whether the path starts with this root's directory.
pub fn (i &IndexingRoot) contains(path string) bool {
	return path.starts_with(i.root)
}
