module lsp

import diag
import json2
import vtool

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

// PendingKind says what the server should do with a reply from the client.
pub enum PendingKind {
	// the reply to window/workDoneProgress/create. The token is the key.
	progress_create
	// the reply to workspace/configuration. The result replaces the settings.
	configuration
}

pub struct PendingRequest {
pub:
	kind PendingKind
	key  string
}

// BufferSink collects messages instead of writing them. A test hands one to
// new_server and reads what the server said; without it every test file would
// carry its own copy of these twelve lines.
pub struct BufferSink {
pub mut:
	messages []string
}

// send appends a message to the buffer a test reads back.
pub fn (mut b BufferSink) send(message string) {
	b.messages << message
}

// last_message is the most recent message, or an invalid one when the server has
// said nothing. A test that expected a reply and got none fails on the reason
// rather than on an index.
pub fn (b &BufferSink) last_message() Message {
	if b.messages.len == 0 {
		return Message{
			kind:   .invalid
			reason: 'the server sent nothing'
		}
	}
	return parse_message(b.messages[b.messages.len - 1])
}

pub struct Server {
mut:
	router Router
	sink   Sender
	state  ServerState
	// exit_now is set by the exit notification and read by the serve loop.
	exit_now bool
	// exit_code is what the process should exit with. It starts at 1 because
	// exit without a shutdown is the failure path, and only handle_exit lowers
	// it.
	exit_code              int
	client_caps            ClientCapabilities
	client_name            string
	client_ready           bool
	server_version         string
	negotiation_notes      []string
	initialization_options json2.Any
	settings               json2.Any
	documents              DocumentStore
	// diagnostics is the queue between the editor's edits and the compiler runs
	// they earn, plus the last report each buffer was given.
	diagnostics diag.Scheduler
	cancel      CancelRegistry
	progress    ProgressReporter
	// compiler is the V binary the feature lanes run. It is resolved at
	// startup, and compiler_error holds why there is none when there is none.
	compiler       ?vtool.Compiler
	compiler_caps  ?vtool.CapabilityReport
	compiler_error string
	// semantic_legend is the token legend the client agreed to in initialize.
	// A request that arrives with an empty legend has nowhere to put a token.
	semantic_legend SemanticLegend
	// pending maps the ids of requests the server sent to the client onto what
	// the reply means.
	pending          map[string]PendingRequest
	next_outbound_id int
pub mut:
	// The counters exist so a test can assert that a message was dropped rather
	// than answered, which is otherwise invisible from the outside.
	requests_answered     int
	notifications_handled int
	refused_frames        int
	// cancelled_requests counts requests dropped because the client cancelled
	// their id before they were dispatched.
	cancelled_requests int
	// sync_refusals counts didChange notifications for a buffer the store does
	// not have, which means the two sides disagree about what is open.
	sync_refusals int
	// unsolicited_responses counts replies that matched no request the server
	// sent.
	unsolicited_responses int
	workspace_folders     []WorkspaceFolder
}

// new_server builds a server that writes to sink and registers the methods of the
// protocol core.
pub fn new_server(sink Sender) &Server {
	mut s := &Server{
		sink:        sink
		exit_code:   1
		diagnostics: diag.new_scheduler(diag.default_policy())
	}
	s.register_core()
	return s
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

// set_version is what the executable passes down so the initialize reply can
// name the build. The protocol core carries no version literal of its own.
pub fn (mut s Server) set_version(version string) {
	s.server_version = version
}

// client_announced is the capability view the client sent in initialize.
pub fn (s &Server) client_announced() ClientCapabilities {
	return s.client_caps
}

// is_ready reports that the client sent initialized.
pub fn (s &Server) is_ready() bool {
	return s.client_ready
}

// notes are the negotiation decisions, one line each.
pub fn (s &Server) notes() []string {
	return s.negotiation_notes
}

// document reads a buffer out of the store, which is how a feature handler gets
// the text it is asked about.
pub fn (s &Server) document(uri string) ?TextDocument {
	return s.documents.get(uri)
}

// open_documents lists the buffers the client has open.
pub fn (s &Server) open_documents() []string {
	return s.documents.uris()
}

// cancelled_count is how many requests the client cancelled before they ran.
pub fn (s &Server) cancelled_count() int {
	return s.cancelled_requests
}

// outstanding_requests is how many requests the server is still waiting on an
// answer to.
pub fn (s &Server) outstanding_requests() int {
	return s.pending.len
}

// serve_batch works through one read batch. Frames arrive as a batch rather
// than one at a time so that a $/cancelRequest written together with its
// request is seen before the request is dispatched.
pub fn (mut s Server) serve_batch(frames []Frame) {
	mut messages := []Message{cap: frames.len}
	for frame in frames {
		if frame.kind == .malformed {
			// nothing in a frame the reader refused can be matched to a request
			// id, so there is no one to tell. The count is the record.
			s.refused_frames++
			continue
		}
		messages << parse_message(frame.body)
	}
	// Cancellation is applied to the whole batch before any handler runs, which
	// is what makes a $/cancelRequest written together with its request take
	// effect: the two frames arrive in one batch and the mark is set before the
	// request is dispatched. It also means a cancel that arrives alone is
	// recorded and then waits for a request that will never come, which is why
	// the registry is capped.
	for m in messages {
		if m.kind == .notification && m.method == cancel_method {
			s.note_cancel(m)
		}
	}
	for m in messages {
		s.serve_message(m)
		if s.exit_now {
			// exit is the end of the session. Anything the client wrote after it
			// in the same batch is not served.
			return
		}
	}
}

// note_cancel records a cancellation. There is no handler registered for
// $/cancelRequest: this pre-pass is the handler, and it works on the batch
// rather than on one message at a time.
fn (mut s Server) note_cancel(m Message) {
	params := as_object(m.params) or { return }
	s.cancel.mark(params['id'] or { null_value() })
}

// serve_message routes one message to the handler for its kind. A body that could
// not be used is answered before the phase check; a message in the wrong phase is
// answered with an error when it is a request, and dropped when it is not.
pub fn (mut s Server) serve_message(m Message) {
	if m.kind == .invalid {
		// A body that could not be used has no method and no phase, so it is
		// answered before the phase check. Otherwise a client whose first frame
		// was mangled would hear nothing at all.
		s.serve_invalid(m)
		return
	}
	if refused := s.refuse_before_dispatch(m) {
		// A request in the wrong phase gets an answer naming the phase. A
		// notification in the wrong phase is dropped: the client is gone or not
		// ready, and there is nobody to tell.
		if m.kind == .request {
			s.write(encode_error(m.id, refused.err_code, refused.err_text))
			s.requests_answered++
		}
		return
	}
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
	if s.cancel.take(m.id) {
		// The client cancelled this id. Answering anyway would leave it with a
		// reply it has already thrown away, and the mark is consumed so the id
		// starts clean if it is ever used again.
		s.cancelled_requests++
		return
	}
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
// and the configuration pull are the two reasons the server asks the client
// anything, and both are matched here by the id the server chose.
fn (mut s Server) serve_response(m Message) {
	key := m.id_key()
	if key == '' {
		// a response with a null id matches no request the server sent.
		s.unsolicited_responses++
		return
	}
	request := s.pending[key] or {
		s.unsolicited_responses++
		return
	}
	s.pending.delete(key)
	if m.failed() {
		match request.kind {
			.progress_create { s.progress_declined(request.key) }
			.configuration {
				// the client refused to answer, so the pushed settings stand.
			}
		}
		return
	}
	match request.kind {
		.progress_create { s.progress_created(request.key) }
		.configuration { s.settings = first_configuration(m.result) }
	}
}

// ask sends a request to the client and records what its reply means. The
// direction has its own id space, so a server id never collides with a client
// id even when both are small integers.
fn (mut s Server) ask(method string, params json2.Any, kind PendingKind, key string) int {
	s.next_outbound_id++
	id := s.next_outbound_id
	s.pending[id_key(json2.Any(id))] = PendingRequest{
		kind: kind
		key:  key
	}
	s.write(encode_request(id, method, params))
	return id
}

// write puts one encoded message on the wire.
fn (mut s Server) write(message string) {
	s.sink.send(message)
}
