module main

// lsp_smoke drives a real visor process over stdio and checks the parts of the
// protocol core that only exist once there is a wire: the frame format, the
// initialize handshake against a committed golden, and the exit code.
//
// Run it from the repository root:
//
//   v -o /tmp/visor .
//   v run tools/lsp_smoke.vsh --bin /tmp/visor --fixture testdata/smoke
//
// Nothing here imports the lsp module. A harness that shares its framing code
// with the thing it tests cannot see a framing bug.

import json2
import os
import time

const wait_for_reply_ms = 3000
const silence_window_ms = 300

const usage = 'usage: v run tools/lsp_smoke.vsh --bin <server> --fixture <dir> [--update-golden]'

// Framer turns the child's byte stream back into messages. It is a second
// implementation of the framing on purpose.
struct Framer {
mut:
	fd  int
	buf []u8
}

fn (mut f Framer) take() ?string {
	text := f.buf.bytestr()
	sep := text.index('\r\n\r\n') or { return none }
	length := content_length(text[..sep]) or { return none }
	if text.len < sep + 4 + length {
		return none
	}
	body := text[sep + 4..sep + 4 + length]
	f.buf = f.buf[sep + 4 + length..].clone()
	return body
}

fn (mut f Framer) fill() bool {
	chunk, n := os.fd_read(f.fd, 4096)
	if n <= 0 {
		return false
	}
	f.buf << chunk.bytes()
	return true
}

fn content_length(header string) ?int {
	for line in header.split_into_lines() {
		colon := line.index(':') or { continue }
		if line[..colon].trim_space().to_lower() != 'content-length' {
			continue
		}
		value := line[colon + 1..].trim_space()
		if value == '' {
			return none
		}
		return value.int()
	}
	return none
}

fn frame_of(body string) string {
	return 'Content-Length: ${body.len}\r\n\r\n${body}'
}

enum MessageKind {
	response
	notification
	request
}

// Message is what the harness reads back, kept loose: only the fields the
// checks look at.
struct Message {
mut:
	body   string
	kind   MessageKind
	id     int
	method string
	result json2.Any
	// ecode is 0 on a message without an error.
	ecode int
	etext string
	err   bool
}

fn decode_message(body string) Message {
	root := json2.decode[map[string]json2.Any](body) or {
		return Message{
			body: body
		}
	}
	mut m := Message{
		body: body
	}
	if value := root['id'] {
		m.id = value.int()
	}
	if value := root['method'] {
		m.method = value.str()
		m.kind = if m.id != 0 { .request } else { .notification }
	} else {
		m.kind = .response
	}
	if value := root['result'] {
		m.result = value
	}
	if value := root['error'] {
		m.err = true
		fields := value.as_map()
		if code := fields['code'] {
			m.ecode = code.int()
		}
		if text := fields['message'] {
			m.etext = text.str()
		}
	}
	return m
}

// Runner owns the child process and the two counters that decide the exit code.
struct Runner {
mut:
	framer Framer
	// out_fd is the write end of the child's stdin. Writing through the file
	// descriptor directly keeps a frame in one write, which is what makes the
	// request and its cancellation arrive as one batch.
	out_fd   int
	checks   int
	failures int
}

fn (mut r Runner) send(body string) {
	os.fd_write(r.out_fd, frame_of(body))
}

// send_together writes several frames with one write to the pipe so the server
// reads them in a single batch. Cancellation needs that: the mark is applied to
// a whole batch before any handler runs.
fn (mut r Runner) send_together(bodies []string) {
	mut out := ''
	for body in bodies {
		out += frame_of(body)
	}
	os.fd_write(r.out_fd, out)
}

fn (mut r Runner) next(timeout_ms int) ?Message {
	mut waited := 0
	for {
		if body := r.framer.take() {
			return decode_message(body)
		}
		if waited >= timeout_ms {
			return none
		}
		if os.fd_is_pending(r.framer.fd) {
			if !r.framer.fill() {
				return none
			}
			continue
		}
		time.sleep(2 * time.millisecond)
		waited += 2
	}
	return none
}

fn (mut r Runner) record(label string, ok bool, detail string) {
	r.checks++
	if ok {
		println('ok   ${label}')
		return
	}
	r.failures++
	suffix := if detail == '' { '' } else { ': ${detail}' }
	println('FAIL ${label}${suffix}')
}

// expect_silence asserts that nothing arrives inside the window. A reply to a
// request the server actually served arrives in microseconds, so the window is
// only there to keep a passing run short.
fn (mut r Runner) expect_silence(label string, window_ms int) {
	reply := r.next(window_ms) or {
		r.record(label, true, '')
		return
	}
	if reply.kind == .response {
		r.record(label, false, 'the server answered id ${reply.id}')
		return
	}
	r.record(label, false, 'the server sent ${reply.method}')
}

fn (mut r Runner) expect_reply(label string, want_id int, window_ms int) ?Message {
	reply := r.next(window_ms) or {
		r.record(label, false, 'nothing arrived within ${window_ms} ms')
		return none
	}
	if reply.kind != .response || reply.id != want_id {
		r.record(label, false, 'got a ${reply.kind} for id ${reply.id}')
		return none
	}
	r.record(label, true, '')
	return reply
}

fn arg_value(name string) ?string {
	for i, arg in os.args {
		if arg == name && i + 1 < os.args.len {
			return os.args[i + 1]
		}
		if arg.starts_with(name + '=') {
			return arg[name.len + 1..]
		}
	}
	return none
}

// canon writes a value in one canonical form: object keys sorted, no
// whitespace. The golden is pretty printed for review, and this is what makes
// the comparison ignore that.
fn canon(value json2.Any) string {
	if value is map[string]json2.Any {
		object := value as map[string]json2.Any
		mut keys := object.keys()
		keys.sort()
		mut parts := []string{cap: keys.len}
		for key in keys {
			inner := object[key] or { json2.Any(json2.Null{}) }
			parts << '${json2.encode(json2.Any(key))}:${canon(inner)}'
		}
		return '{${parts.join(',')}}'
	}
	if value is []json2.Any {
		items := value as []json2.Any
		mut parts := []string{cap: items.len}
		for item in items {
			parts << canon(item)
		}
		return '[${parts.join(',')}]'
	}
	return json2.encode(value)
}

fn pretty(value json2.Any, depth int) string {
	pad := '  '.repeat(depth)
	if value is map[string]json2.Any {
		object := value as map[string]json2.Any
		if object.len == 0 {
			return '{}'
		}
		mut keys := object.keys()
		keys.sort()
		mut lines := []string{cap: keys.len}
		for key in keys {
			inner := object[key] or { json2.Any(json2.Null{}) }
			lines << '${pad}  ${json2.encode(json2.Any(key))}: ${pretty(inner, depth + 1)}'
		}
		return '{\n${lines.join(',\n')}\n${pad}}'
	}
	if value is []json2.Any {
		items := value as []json2.Any
		if items.len == 0 {
			return '[]'
		}
		mut lines := []string{cap: items.len}
		for item in items {
			lines << '${pad}  ${pretty(item, depth + 1)}'
		}
		return '[\n${lines.join(',\n')}\n${pad}]'
	}
	return json2.encode(value)
}

fn open_notification(uri string, text string) string {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['languageId'] = json2.Any('v')
	document['version'] = json2.Any(1)
	document['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	mut message := map[string]json2.Any{}
	message['jsonrpc'] = json2.Any('2.0')
	message['method'] = json2.Any('textDocument/didOpen')
	message['params'] = json2.Any(params)
	return json2.encode(json2.Any(message))
}

fn main() {
	bin := arg_value('--bin') or {
		eprintln(usage)
		exit(1)
	}
	fixture := arg_value('--fixture') or {
		eprintln(usage)
		exit(1)
	}
	if !os.exists(bin) {
		eprintln('smoke: no server binary at ${bin}')
		exit(1)
	}
	capabilities_path := os.join_path(fixture, 'client-capabilities.json')
	golden_path := os.join_path(fixture, 'capabilities.golden.json')
	if !os.exists(capabilities_path) {
		eprintln('smoke: no client capabilities at ${capabilities_path}')
		exit(1)
	}
	client_capabilities := os.read_file(capabilities_path)!
	buffer := os.read_file(os.join_path(fixture, 'app.v'))!
	root_uri := 'file://${os.join_path(os.getwd(), fixture, 'app.v')}'

	mut proc := os.new_process(bin)
	proc.set_redirect_stdio()
	proc.run()
	mut runner := Runner{
		framer: Framer{
			fd: proc.stdio_fd[1]
		}
		out_fd: proc.stdio_fd[0]
	}

	// One write: initialize. The id is fixed so the golden can hold the whole
	// response, not just the capability object.
	runner.send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{' +
		'"processId":null,"clientInfo":{"name":"lsp_smoke","version":"1"},' +
		'"capabilities":${client_capabilities},' +
		'"workspaceFolders":[{"uri":"file://${os.getwd()}","name":"smoke"}]}}')
	handshake := runner.next(wait_for_reply_ms) or {
		eprintln('smoke: the server did not answer initialize')
		proc.signal_kill()
		exit(1)
	}
	response := json2.decode[json2.Any](handshake.body)!

	if '--update-golden' in os.args {
		os.write_file(golden_path, pretty(response, 0) + '\n')!
		println('wrote ${golden_path}')
		proc.signal_kill()
		exit(0)
	}

	runner.record('initialize answers with a result', !handshake.err && handshake.id == 1,
		handshake.etext)
	golden := json2.decode[json2.Any](os.read_file(golden_path)!)!
	runner.record('initialize response matches the committed golden',
		canon(response) == canon(golden), 'rerun with --update-golden after an intended change')

	runner.send('{"jsonrpc":"2.0","method":"initialized","params":{}}')
	runner.send(open_notification(root_uri, buffer))
	// A notification is never answered. If the sync handling lost the frame
	// order, the reply to the next request would carry the wrong id.
	runner.expect_silence('initialized and didOpen are answered with nothing', silence_window_ms)

	hover := '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":' +
		'{"textDocument":{"uri":"${root_uri}"},"position":{"line":7,"character":14}}}'
	runner.send(hover)
	if reply := runner.expect_reply('the session keeps answering after a didOpen', 2, wait_for_reply_ms) {
		runner.record('an unknown method gets MethodNotFound (-32601)', reply.err
			&& reply.ecode == -32601, 'error code ${reply.ecode}')
	}

	// A request and its cancellation in one write, so the server reads them as
	// one batch and the mark is set before the request is dispatched.
	cancelled := '{"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":' +
		'{"textDocument":{"uri":"${root_uri}"},"position":{"line":7,"character":14}}}'
	runner.send_together([
		cancelled,
		'{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":3}}',
	])
	runner.expect_silence('a cancelled request gets no response', silence_window_ms)
	after := '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":' +
		'{"textDocument":{"uri":"${root_uri}"},"position":{"line":7,"character":14}}}'
	runner.send(after)
	if reply := runner.expect_reply('the server is still serving after a cancellation', 4,
		wait_for_reply_ms) {
		runner.record('the cancelled id did not take the next request with it', reply.err
			&& reply.ecode == -32601, 'error code ${reply.ecode}')
	}

	runner.send('{"jsonrpc":"2.0","id":5,"method":"shutdown"}')
	if reply := runner.expect_reply('shutdown answers', 5, wait_for_reply_ms) {
		runner.record('shutdown result is null', reply.result is json2.Null, 'result: ${reply.result}')
	}
	runner.send('{"jsonrpc":"2.0","method":"exit"}')
	proc.wait()
	runner.record('exit after shutdown ends the process with code 0', proc.code == 0,
		'exit code ${proc.code}')

	// A second process, for the other exit code. exit without a shutdown is the
	// one the spec calls a failure, and it is worth seeing from a real process
	// rather than only from the loop unit tests.
	mut other_proc := os.new_process(bin)
	other_proc.set_redirect_stdio()
	other_proc.run()
	mut other := Runner{
		framer: Framer{
			fd: other_proc.stdio_fd[1]
		}
		out_fd: other_proc.stdio_fd[0]
	}
	other.send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}')
	other.next(wait_for_reply_ms) or { eprintln('smoke: the second server did not answer') }
	other.send('{"jsonrpc":"2.0","method":"initialized","params":{}}')
	other.send('{"jsonrpc":"2.0","method":"exit"}')
	other_proc.wait()
	runner.record('exit without shutdown ends the process with code 1', other_proc.code == 1,
		'exit code ${other_proc.code}')

	println('${runner.checks} checks, ${runner.failures} failed')
	if runner.failures > 0 {
		exit(1)
	}
	println('smoke: ok')
}
