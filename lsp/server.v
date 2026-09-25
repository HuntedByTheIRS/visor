module lsp

// Sender is the sink the server writes encoded messages to. The stdio transport
// writes a frame to file descriptor 1; a test hands in a collector and reads
// what the server said.
//
// send takes a mutable receiver because a collector appends to itself. That
// pushes the implementation to hold a pointer, which is what the transport
// wants anyway.
pub interface Sender {
mut:
	send(message string)
}

pub enum ServerState {
	uninitialized
	initialized
	shutting_down
}

pub struct Server {
mut:
	router Router
	sink   Sender
	state  ServerState
	// exit_now is set by the exit notification and read by the serve loop.
	exit_now bool
	// exit_code is what the process should exit with. It starts at 1 because
	// exit without a shutdown is the failure path.
	exit_code int
pub mut:
	// The counters exist so a test can assert that a message was dropped rather
	// than answered, which is otherwise invisible from the outside.
	requests_answered     int
	notifications_handled int
	refused_frames        int
}

pub fn new_server(sink Sender) &Server {
	return &Server{
		sink:      sink
		exit_code: 1
	}
}

// on registers a handler for a method. Feature lanes call this with free
// functions of their own.
pub fn (mut s Server) on(method string, handler Handler) {
	s.router.on(method, handler)
}

// stub registers a method this build knows about and cannot serve yet.
pub fn (mut s Server) stub(method string, owner string) {
	s.router.stub(method, owner)
}

// session_state reports where the session is in the initialize, shutdown, exit
// sequence.
pub fn (s &Server) session_state() ServerState {
	return s.state
}

// wants_exit reports that the exit notification arrived.
pub fn (s &Server) wants_exit() bool {
	return s.exit_now
}

// code_on_exit is the exit code the process should use.
pub fn (s &Server) code_on_exit() int {
	return s.exit_code
}

// serve_batch works through one read batch. Frames arrive as a batch rather
// than one at a time so that a $/cancelRequest written together with its
// request is seen before the request is dispatched.
pub fn (mut s Server) serve_batch(frames []Frame) {
	for frame in frames {
		if frame.kind == .malformed {
			// Nothing in a frame the reader refused can be matched to a request
			// id, so there is no one to tell. The count is the record.
			s.refused_frames++
			continue
		}
		s.serve_message(parse_message(frame.body))
	}
}

pub fn (mut s Server) serve_message(m Message) {
	match m.kind {
		.request { s.serve_request(m) }
		.notification { s.serve_notification(m) }
		.response { s.serve_response(m) }
		.invalid { s.serve_invalid(m) }
	}
}

// serve_invalid answers a message that could not be routed. JSON-RPC has a null
// id for exactly this case: the reply cannot name a request that was never
// understood.
fn (mut s Server) serve_invalid(m Message) {
	code := if m.invalid_code != 0 { m.invalid_code } else { code_invalid_request }
	s.write(encode_error(null_value(), code, m.reason))
}

fn (mut s Server) serve_request(m Message) {
	reply := s.dispatch(m)
	if reply.failed() {
		s.write(encode_error(m.id, reply.err_code, reply.err_text))
	} else {
		s.write(encode_result(m.id, reply.result))
	}
	s.requests_answered++
}

fn (mut s Server) dispatch(m Message) Reply {
	if handler := s.router.handlers[m.method] {
		return handler(mut s, m)
	}
	if owner := s.router.stubs[m.method] {
		return not_implemented(m.method, owner)
	}
	// Naming the method in the message is what makes an unregistered feature
	// show up in an editor's log as a missing method rather than as a failure
	// with no cause.
	return fail(code_method_not_found, 'no handler for ${m.method}')
}

fn (mut s Server) serve_notification(m Message) {
	s.notifications_handled++
	if handler := s.router.handlers[m.method] {
		// The reply is dropped: a notification has nowhere to put one.
		handler(mut s, m)
	}
}

// serve_response takes a reply to a request the server sent. Progress creation
// and configuration pulls are the two places the server asks the client
// anything; both are wired up with the progress reporter.
fn (mut s Server) serve_response(m Message) {
	_ = m
}

// write puts one encoded message on the wire.
fn (mut s Server) write(message string) {
	s.sink.send(message)
}
