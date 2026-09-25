module lsp

import json2

// cancel_method is the one notification the router does not hold a handler for.
pub const cancel_method = '$/cancelRequest'

// A client that cancels ids it never sent can otherwise grow this map without
// bound. Past the cap a new mark is dropped, which can only affect ids the
// server never had.
const max_pending_cancels = 256

// CancelRegistry remembers which request ids the client has cancelled. Marks are
// keyed by the normalised id, so a cancellation for the integer 3 does not touch
// the request with the string id "3".
pub struct CancelRegistry {
mut:
	cancelled map[string]bool
pub mut:
	// marks counts cancellations that were recorded.
	marks int
	// applied counts requests they stopped answering.
	applied int
	// dropped counts cancellations refused because the registry was full or the
	// notification carried no id.
	dropped int
}

// mark records a cancellation. It reports whether the id was usable.
pub fn (mut c CancelRegistry) mark(id json2.Any) bool {
	key := id_key(id)
	if key == '' {
		c.dropped++
		return false
	}
	if key !in c.cancelled && c.cancelled.len >= max_pending_cancels {
		c.dropped++
		return false
	}
	c.cancelled[key] = true
	c.marks++
	return true
}

// take reports whether this id is cancelled, consuming the mark so a later
// request reusing the id starts clean.
pub fn (mut c CancelRegistry) take(id json2.Any) bool {
	key := id_key(id)
	if key == '' {
		return false
	}
	if key in c.cancelled {
		c.cancelled.delete(key)
		c.applied++
		return true
	}
	return false
}

// pending is how many marks are waiting for a request that may never come.
pub fn (c &CancelRegistry) pending() int {
	return c.cancelled.len
}
