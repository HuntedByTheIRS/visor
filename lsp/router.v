module lsp

import json2

// Handler answers one method. Handlers are free functions rather than methods:
// V does not let a method value with a mutable receiver escape its call site, so
// a handler table can only hold plain function pointers.
//
// One table serves requests and notifications. A notification's handler still
// returns a Reply, and the server drops it, because splitting the table in two
// would double every registration for no gain.
pub type Handler = fn (mut s Server, req Message) Reply

pub struct Reply {
pub:
	result json2.Any
	// err_code is 0 when the handler produced a result.
	err_code int
	err_text string
}

// ok builds a successful reply carrying the handler's result.
pub fn ok(result json2.Any) Reply {
	return Reply{
		result: result
	}
}

// fail builds an error reply with the given code and message.
pub fn fail(code int, text string) Reply {
	return Reply{
		err_code: code
		err_text: text
	}
}

// failed reports whether the reply carries an error.
pub fn (r &Reply) failed() bool {
	return r.err_code != 0
}

// not_implemented is what a stubbed method answers. It is an error on purpose:
// an empty successful answer tells the editor the feature ran and found nothing,
// which is a different claim from "this build cannot do that yet".
pub fn not_implemented(method string, owner string) Reply {
	return fail(code_request_failed, '${method} is not implemented in this build: ${owner}')
}

// Router is the method table. Feature lanes register handlers on it as they
// land; until then their methods are either stubs or unknown.
pub struct Router {
mut:
	handlers map[string]Handler
	stubs    map[string]string
}

// on registers a handler. Registering the same method twice replaces the
// earlier handler, and registering one that was stubbed takes the stub out of
// the table, which is what a lane that supersedes a stub wants.
pub fn (mut r Router) on(method string, handler Handler) {
	r.handlers[method] = handler
	if method in r.stubs {
		r.stubs.delete(method)
	}
}

// stub registers a method name that this build knows about and cannot serve.
// The owner names the lane that will replace it.
pub fn (mut r Router) stub(method string, owner string) {
	r.stubs[method] = owner
}

// is_stub reports whether the method is one this build knows about and cannot
// serve.
pub fn (r &Router) is_stub(method string) bool {
	return method in r.stubs
}

// knows reports whether the method is either served or stubbed.
pub fn (r &Router) knows(method string) bool {
	return method in r.handlers || method in r.stubs
}

// served_count returns the number of handlers registered on the router.
pub fn (r &Router) served_count() int {
	return r.handlers.len
}

// stub_count returns the number of stubs registered on the router.
pub fn (r &Router) stub_count() int {
	return r.stubs.len
}
