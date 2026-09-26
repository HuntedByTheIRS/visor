// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module index

import time
import os
import sync
import runtime
import math
import engine.loglib
import engine.psi
import engine.utils
import engine.parser

// index returns the index, loading it from cache when possible and building it from scratch otherwise.
pub fn (mut i IndexingRoot) index() BuiltIndexStatus {
	now := time.now()

	loglib.with_fields({
		'root': i.root
	}).info('Indexing root')

	if _ := i.load_index() {
		loglib.with_duration(time.since(now)).info('Index loaded from cache')
		return .from_cache
	}

	file_chan := chan string{cap: 1000}
	cache_chan := chan FileIndex{cap: 1000}

	spawn fn [mut i, file_chan] () {
		path := i.root
		os.walk(path, fn [mut i, file_chan] (path string) {
			if i.need_index(path) {
				file_chan <- path
			}
		})

		file_chan.close()
	}()

	spawn i.spawn_indexing_workers(cache_chan, file_chan)

	mut caches := []FileIndex{cap: 100}
	for {
		cache := <-cache_chan or { break }
		caches << cache
	}

	for cache in caches {
		i.index.per_file.data[cache.path()] = cache
	}

	i.updated_at = time.now()
	i.need_save = true

	loglib.with_duration(time.since(now)).info('Indexing finished')
	return .from_scratch
}

// index_file parses one file and builds its stub tree and file index.
pub fn (mut i IndexingRoot) index_file(path string, content string, mut p parser.Parser) !FileIndex {
	last_modified := os.file_last_mod_unix(path)
	res := p.parse_code(content)
	psi_file := psi.new_psi_file(path, res.tree, content)
	module_fqn := psi.module_qualified_name(psi_file, i.root)

	mut cache := FileIndex{
		kind:               i.kind
		file_last_modified: last_modified
		sink:               &psi.StubIndexSink{
			kind:      unsafe { psi.StubIndexLocationKind(u8(i.kind)) }
			stub_list: unsafe { nil }
		}
		stub_list:          unsafe { nil }
	}
	stub_tree := build_stub_tree(psi_file, i.root)

	stub_type := psi.StubbedElementType{}
	mut stub_list := stub_tree.root.stub_list
	stub_list.module_fqn = module_fqn
	stub_list.path = path

	cache.sink.imported_modules = stub_tree.get_imported_modules()

	stubs := stub_list.index_map.values()
	for stub in stubs {
		cache.sink.stub_id = stub.id
		cache.sink.stub_list = stub.stub_list
		stub_type.index_stub(stub, mut cache.sink)
	}
	cache.stub_list = stub_list

	unsafe { res.tree.free() }
	return cache
}

// spawn_indexing_workers indexes every path in file_chan on a pool of worker threads and closes cache_chan when the pool finishes.
pub fn (mut i IndexingRoot) spawn_indexing_workers(cache_chan chan FileIndex, file_chan chan string) {
	mut wg := sync.new_waitgroup()
	cpus := runtime.nr_cpus()
	workers := math.max(cpus - 4, 1)
	wg.add(workers)
	for j := 0; j < workers; j++ {
		spawn fn [file_chan, mut wg, mut i, cache_chan] () {
			mut p := parser.Parser.new()
			defer { p.free() }
			for {
				filepath := <-file_chan or { break }
				content := os.read_file(filepath) or {
					loglib.with_fields({
						'uri':   utils.path_to_uri(filepath)
						'error': err.str()
					}).error('Error reading file for index')
					continue
				}
				cache_chan <- i.index_file(filepath, content, mut p) or {
					loglib.with_fields({
						'uri':   utils.path_to_uri(filepath)
						'error': err.str()
					}).error('Error indexing file')
					continue
				}
			}

			wg.done()
		}()
	}

	wg.wait()
	cache_chan.close()
}
