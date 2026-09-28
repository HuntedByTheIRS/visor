// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

// The engine keeps two caches of answers it worked out from the text it was
// handed: the target of a reference, and the type of an element.
//
// Both are keyed by path, node kind and range, and neither key holds the text
// or a version of the file. A call that keeps its offsets after an edit answers
// with the type of the name that used to sit there, and nothing inside the
// engine can tell that the text moved. The caller that replaces a buffer's text
// is the only one who knows, so it says so here, once, for both caches.
@[has_globals]
module psi

// forget_answers drops every resolution and every inferred type, so the next
// question is answered from the text that is in the engine now.
//
// A server calls this on every edit it accepts. Paying for the answers it
// recomputes is the price of an answer that describes the buffer rather than
// the buffer's past.
pub fn forget_answers() {
	type_cache.clear()
	resolve_cache.clear()
}
