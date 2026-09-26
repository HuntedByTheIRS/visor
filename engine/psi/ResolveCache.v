// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

@[has_globals; translated]
module psi

import sync
import engine.loglib

__global resolve_cache = ResolveCache{}

pub struct ResolveCache {
mut:
	mutex sync.RwMutex
	data  map[string]PsiElement
}

// get returns the resolve target cached for the element, or none when nothing is cached for it.
pub fn (t &ResolveCache) get(element PsiElement) ?PsiElement {
	t.mutex.@rlock()
	defer {
		t.mutex.runlock()
	}

	fingerprint := t.element_fingerprint(element)
	return t.data[fingerprint] or { return none }
}

// put caches the resolve target for the element and returns that same target.
pub fn (mut t ResolveCache) put(element PsiElement, result PsiElement) PsiElement {
	t.mutex.@lock()
	defer {
		t.mutex.unlock()
	}

	fingerprint := t.element_fingerprint(element)
	t.data[fingerprint] = result
	return result
}

// clear drops every cached entry, so later lookups resolve from source again.
pub fn (mut t ResolveCache) clear() {
	t.mutex.@lock()
	defer {
		t.mutex.unlock()
	}

	loglib.with_fields({
		'cache_size': t.data.len.str()
	}).log_one(.info, 'Clearing resolve cache')

	t.data = map[string]PsiElement{}
}

@[inline]
fn (_ &ResolveCache) element_fingerprint(element PsiElement) string {
	file := element.containing_file() or { return '' }
	range := element.text_range()
	return '${file.path}:${element.node().type_name}:${range.line}:${range.column}:${range.end_column}:${range.end_line}'
}
