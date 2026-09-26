// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module index

import engine.psi

// PerFileIndex describes the cache of a group of files in the index.
pub struct PerFileIndex {
pub mut:
	data map[string]FileIndex
}

// get_sinks returns the index sink of every file the cache holds.
pub fn (p &PerFileIndex) get_sinks() []psi.StubIndexSink {
	mut res := []psi.StubIndexSink{cap: p.data.len}
	for _, cache in p.data {
		if !isnil(cache.sink) {
			res << *cache.sink
		}
	}
	return res
}

// rename_file moves a file's cache to the new path and returns it. It returns none
// when the two paths are equal or when the cache does not hold the old one.
pub fn (mut p PerFileIndex) rename_file(old string, new string) ?FileIndex {
	if old == new {
		return none
	}
	if mut cache := p.data[old] {
		cache.stub_list.path = new
		p.data[new] = cache
		p.data.delete(old)
		return cache
	}

	return none
}

// remove_file drops a file's cache and returns it, or none when the cache does not
// hold the file.
pub fn (mut p PerFileIndex) remove_file(path string) ?FileIndex {
	if mut cache := p.data[path] {
		p.data.delete(path)
		return cache
	}

	return none
}
