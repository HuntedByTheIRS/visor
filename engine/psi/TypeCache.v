// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

@[has_globals; translated]
module psi

import engine.psi.types
import sync
import engine.loglib

__global type_cache = TypeCache{}

pub struct TypeCache {
mut:
	mutex sync.RwMutex
	data  map[string]types.Type
}

// get returns the cached type for an element, or none when it has not been inferred yet.
pub fn (t &TypeCache) get(element PsiElement) ?types.Type {
	t.mutex.@rlock()
	defer {
		t.mutex.runlock()
	}

	fingerprint := t.element_fingerprint(element)
	return t.data[fingerprint] or { return none }
}

// put stores the type for an element and returns it, so the caller can use the result inline.
pub fn (mut t TypeCache) put(element PsiElement, typ types.Type) types.Type {
	t.mutex.@lock()
	defer {
		t.mutex.unlock()
	}

	fingerprint := t.element_fingerprint(element)
	t.data[fingerprint] = typ
	return typ
}

// clear empties the cache.
pub fn (mut t TypeCache) clear() {
	t.mutex.@lock()
	defer {
		t.mutex.unlock()
	}

	loglib.with_fields({
		'cache_size': t.data.len.str()
	}).log_one(.info, 'Clearing type cache')

	t.data = map[string]types.Type{}
}

@[inline]
fn (_ &TypeCache) element_fingerprint(element PsiElement) string {
	file := element.containing_file() or { return '' }
	range := element.text_range()
	return '${file.path}:${element.node().type_name}:${range.line}:${range.column}:${range.end_column}:${range.end_line}'
}
