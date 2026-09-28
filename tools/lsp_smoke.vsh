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

// post_open_reply_ms is the window for the first request after a didOpen. That
// notification is where the buffer's imported modules are indexed, and on a
// cold machine the server reads no further frame until that finishes. Requests
// after the first are answered from the index and keep the short window.
const post_open_reply_ms = 15000

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
	// params is the payload of a message the client sent or the server sent as
	// a notification, which carries its payload there rather than in a result.
	params json2.Any
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
	if value := root['params'] {
		m.params = value
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
	out_fd int
	// waited_ms is how long the reply that just arrived took. It goes into the
	// ok line, so a run that got slow says so instead of looking normal.
	waited_ms int
	checks    int
	failures  int
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
			r.waited_ms = waited
			return decode_message(body)
		}
		if waited >= timeout_ms {
			r.waited_ms = waited
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
	r.record('${label} (${r.waited_ms} ms)', true, '')
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

// as_map and as_list read a decoded payload without the casts needing a guard,
// which keeps the assertions below about the protocol rather than about V's
// types.
fn as_map(value json2.Any) ?map[string]json2.Any {
	if value is map[string]json2.Any {
		return value as map[string]json2.Any
	}
	return none
}

fn as_list(value json2.Any) ?[]json2.Any {
	if value is []json2.Any {
		return value as []json2.Any
	}
	return none
}

fn no_map() map[string]json2.Any {
	return map[string]json2.Any{}
}

fn no_list() []json2.Any {
	return []json2.Any{}
}

// legend_types reads the token types the server advertised out of the
// initialize response, so the indices in a token answer can be checked by name
// rather than by number.
fn legend_types(response json2.Any) []string {
	root := as_map(response) or { return no_list_strings() }
	result := as_map(root['result'] or { json2.Any(no_map()) }) or { return no_list_strings() }
	caps := as_map(result['capabilities'] or { json2.Any(no_map()) }) or { return no_list_strings() }
	provider := as_map(caps['semanticTokensProvider'] or { json2.Any(no_map()) }) or {
		return no_list_strings()
	}
	legend := as_map(provider['legend'] or { json2.Any(no_map()) }) or { return no_list_strings() }
	listed := as_list(legend['tokenTypes'] or { json2.Any(no_list()) }) or {
		return no_list_strings()
	}
	mut out := []string{cap: listed.len}
	for item in listed {
		out << item.str()
	}
	return out
}

fn no_list_strings() []string {
	return []string{}
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

// change_notification replaces a whole buffer, which is how an editor sends an
// edit that has not been saved. Building it here rather than as a literal keeps
// the newlines of the text out of the hand written JSON.
fn change_notification(uri string, version int, text string) string {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	document['version'] = json2.Any(version)
	mut change := map[string]json2.Any{}
	change['text'] = json2.Any(text)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	params['contentChanges'] = json2.Any([json2.Any(change)])
	mut message := map[string]json2.Any{}
	message['jsonrpc'] = json2.Any('2.0')
	message['method'] = json2.Any('textDocument/didChange')
	message['params'] = json2.Any(params)
	return json2.encode(json2.Any(message))
}

// pull_request asks for a buffer's findings, echoing the report id the client
// already holds when there is one.
fn pull_request(id int, uri string, previous string) string {
	mut document := map[string]json2.Any{}
	document['uri'] = json2.Any(uri)
	mut params := map[string]json2.Any{}
	params['textDocument'] = json2.Any(document)
	if previous != '' {
		params['previousResultId'] = json2.Any(previous)
	}
	mut message := map[string]json2.Any{}
	message['jsonrpc'] = json2.Any('2.0')
	message['id'] = json2.Any(id)
	message['method'] = json2.Any('textDocument/diagnostic')
	message['params'] = json2.Any(params)
	return json2.encode(json2.Any(message))
}

// report_field reads one field out of a diagnostic report.
fn report_field(reply Message, key string) json2.Any {
	result := as_map(reply.result) or { return json2.Any('') }
	return result[key] or { json2.Any('') }
}

// report_items is the finding list of a full report, empty when it holds none.
fn report_items(reply Message) []json2.Any {
	return as_list(report_field(reply, 'items')) or { no_list() }
}

// finding_position reads line and character out of one finding.
fn finding_position(item json2.Any) (int, int) {
	obj := as_map(item) or { return -1, -1 }
	range_ := as_map(obj['range'] or { json2.Any(no_map()) }) or { return -1, -1 }
	start := as_map(range_['start'] or { json2.Any(no_map()) }) or { return -1, -1 }
	return (start['line'] or { json2.Any(-1) }).int(), (start['character'] or { json2.Any(-1) }).int()
}

// finding_message reads the text of one finding.
fn finding_message(item json2.Any) string {
	obj := as_map(item) or { return '' }
	return (obj['message'] or { json2.Any('') }).str()
}

// hint_label reads the label of one inlay hint.
fn hint_label(item json2.Any) string {
	obj := as_map(item) or { return '' }
	return (obj['label'] or { json2.Any('') }).str()
}

// hint_position reads where one inlay hint was placed. A hint carries a position
// rather than a range, which is the whole difference from a finding.
fn hint_position(item json2.Any) (int, int) {
	obj := as_map(item) or { return -1, -1 }
	position := as_map(obj['position'] or { json2.Any(no_map()) }) or { return -1, -1 }
	return (position['line'] or { json2.Any(-1) }).int(), (position['character'] or { json2.Any(-1) }).int()
}

// token_kind_at walks the delta-encoded token data and returns the kind of the
// token that starts at a line and a column, or an empty string when nothing
// starts there.
//
// The encoding counts from the token before: a token carries the step to its
// line and, within the same line, the step to its column, so the position of
// each one is a running sum rather than something the answer states.
fn token_kind_at(data []json2.Any, line int, column int, types []string) string {
	mut current_line := 0
	mut current_column := 0
	mut index := 0
	for index + 3 < data.len {
		delta_line := data[index].int()
		delta_start := data[index + 1].int()
		token_type := data[index + 3].int()
		if delta_line == 0 {
			current_column += delta_start
		} else {
			current_line += delta_line
			current_column = delta_start
		}
		if current_line == line && current_column == column {
			if token_type < 0 || token_type >= types.len {
				return ''
			}
			return types[token_type]
		}
		index += 5
	}
	return ''
}

// line_of finds the first line holding a needle, so an expected position in the
// checks below does not have to be recounted after the fixture is edited.
fn line_of(text string, needle string) int {
	for i, line in text.split_into_lines() {
		if line.contains(needle) {
			return i
		}
	}
	return -1
}

// column_of finds the first column of a needle on a line, or -1 when the line
// holds no such text.
fn column_of(text string, line_number int, needle string) int {
	lines := text.split_into_lines()
	if line_number < 0 || line_number >= lines.len {
		return -1
	}
	return lines[line_number].index(needle) or { -1 }
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
	if reply := runner.expect_reply('the session keeps answering after a didOpen', 2,
		post_open_reply_ms) {
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

	// Semantic tokens come from the buffer's parse tree, so this request proves
	// the walk, the advertised legend and the encoding agree across a real
	// pipe. The type is checked by name against the legend the server sent,
	// which is the part an index alone would not show.
	tokens := '{"jsonrpc":"2.0","id":5,"method":"textDocument/semanticTokens/full",' +
		'"params":{"textDocument":{"uri":"${root_uri}"}}}'
	runner.send(tokens)
	if reply := runner.expect_reply('semantic tokens are answered', 5, wait_for_reply_ms) {
		types := legend_types(response)
		keyword_index := types.index('keyword')
		runner.record('the token answer is not an error', !reply.err, reply.etext)
		result := as_map(reply.result) or { no_map() }
		data := as_list(result['data'] or { json2.Any(no_list()) }) or { no_list() }
		integers := data.len
		mut first_length := -1
		mut first_type := -1
		if data.len >= 4 {
			first_length = data[2].int()
			first_type = data[3].int()
		}
		runner.record('the token data is whole five-integer tuples', integers > 0
			&& integers % 5 == 0, '${integers} integers')
		// the fixture opens with `module main`, and `module` is six characters
		runner.record('the first token is the `module` keyword', first_length == 6
			&& first_type == keyword_index,
			'length ${first_length}, type ${first_type}, keyword sits at ${keyword_index}')

		// The compile-time names are the compiler's own and resolve to nothing in
		// any index, so the walk is the only thing that can type them. Both halves
		// of `$embed_file('v.mod').to_string()` are checked, because the name and
		// the method are the two answers a reader was missing.
		builtin_line := line_of(buffer, 'home := $env(')
		builtin_column := column_of(buffer, builtin_line, '$env')
		got_builtin := token_kind_at(data, builtin_line, builtin_column, types)
		runner.record('a compile-time builtin is a keyword', got_builtin == 'keyword',
			'kind ${got_builtin} at ${builtin_line}:${builtin_column}')

		method_line := line_of(buffer, '$embed_file(')
		method_column := column_of(buffer, method_line, 'to_string')
		got_method := token_kind_at(data, method_line, method_column, types)
		runner.record('the method on a compile-time value is a method', got_method == 'method',
			'kind ${got_method} at ${method_line}:${method_column}')
	}

	// Inlay hints come from the buffer's parse and the workspace index, so this
	// request proves across a real pipe that the folders the client named were
	// indexed and that a label lands on the text the engine said it describes.
	// The positions are computed from the buffer rather than written down, so
	// editing the fixture does not silently move the expectation.
	hints := '{"jsonrpc":"2.0","id":10,"method":"textDocument/inlayHint","params":' +
		'{"textDocument":{"uri":"${root_uri}"},"range":{"start":{"line":0,"character":0},' +
		'"end":{"line":1000,"character":0}}}}'
	runner.send(hints)
	if reply := runner.expect_reply('inlay hints are answered', 10, wait_for_reply_ms) {
		runner.record('the hint answer is not an error', !reply.err, reply.etext)
		items := as_list(reply.result) or { no_list() }
		mut labels := []string{}
		mut field_line := -1
		mut field_column := -1
		mut attribute_line := -1
		mut attribute_column := -1
		mut type_hint_found := false
		for item in items {
			label := hint_label(item)
			labels << label
			if label == 'x:' {
				field_line, field_column = hint_position(item)
			}
			if label == '    | INLINE' {
				attribute_line, attribute_column = hint_position(item)
			}
			if label == ': Point' {
				type_hint_found = true
			}
		}
		runner.record('the buffer earns a field label and a type label',
			'x:' in labels && type_hint_found, labels.str())

		// A compile-time builtin produces what the compiler says it does, and the
		// engine is the only place that answer can come from: there is no
		// declaration of `$env` or `$embed_file` in any index.
		mut comptime_labels := 0
		for label in labels {
			if label == ': string' {
				comptime_labels++
			}
		}
		runner.record('a compile-time value is labelled with what it produces',
			comptime_labels == 2, '${comptime_labels} string labels in ${labels.str()}')
		// `base := Point{ 2, 3 }` is where the first value is, and the hint has
		// to sit on the `2` rather than near it.
		want_line := line_of(buffer, 'base := Point{')
		want_column := column_of(buffer, want_line, '2')
		runner.record('the field hint sits on the value it describes',
			field_line == want_line && field_column == want_column,
			'${field_line}:${field_column}, wanted ${want_line}:${want_column}')

		// `fn scale` carries `@[inline]`, and the label restating it belongs after
		// the brace the body opens with rather than anywhere else on the line.
		want_attribute_line := line_of(buffer, 'fn scale(')
		want_attribute_column := column_of(buffer, want_attribute_line, '{') + 1
		runner.record('a declaration names the attributes it carries',
			attribute_line == want_attribute_line && attribute_column == want_attribute_column,
			'${attribute_line}:${attribute_column}, wanted ${want_attribute_line}:${want_attribute_column}')
	}

	// Diagnostics are computed from the client's text, so this pair of requests
	// proves over a real pipe that a check runs against the buffer and that the
	// finding is placed in it. The file on disk still holds the clean fixture,
	// so nothing here can have come from it.
	broken := 'fn main() {\n	x := \n}\n'
	runner.send(change_notification(root_uri, 2, broken))
	runner.send(pull_request(7, root_uri, ''))
	if reply := runner.expect_reply('a pull is answered from the unsaved buffer', 7,
		wait_for_reply_ms) {
		runner.record('the pull is not an error', !reply.err, reply.etext)
		kind := report_field(reply, 'kind').str()
		report_id := report_field(reply, 'resultId').str()
		items := report_items(reply)
		runner.record('a full report comes back with an id', kind == 'full' && report_id != '',
			'kind ${kind}, resultId ${report_id}')
		runner.record('the broken buffer earns one finding', items.len == 1, '${items.len} findings')
		if items.len == 1 {
			line, character := finding_position(items[0])
			// `x := ` is on the buffer's second line, and the finding lands
			// there rather than on a line of whatever the compiler read.
			runner.record('the finding sits in the buffer at 2:0', line == 2 && character == 0,
				'${line}:${character}')
			runner.record('the finding carries the compiler message',
				finding_message(items[0]).contains('unexpected token'), finding_message(items[0]))
			// The id round trip is what stops a client from asking for the same
			// list again on every keystroke.
			runner.send(pull_request(8, root_uri, report_id))
			if again := runner.expect_reply('a pull that echoes the id is answered', 8,
				wait_for_reply_ms) {
				runner.record('the echoed id is answered with unchanged',
					report_field(again, 'kind').str() == 'unchanged',
					'kind ${report_field(again, 'kind').str()}')
			}
		}
	}

	runner.send('{"jsonrpc":"2.0","id":6,"method":"shutdown"}')
	if reply := runner.expect_reply('shutdown answers', 6, wait_for_reply_ms) {
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

	// A third process, for the pushed half. This client says it will show what
	// the server pushes, opens a buffer that does not compile, and then says
	// nothing at all. The report has to arrive on its own, which is what proves
	// the serving loop comes back for a scheduled check while the client is
	// quiet: the check is debounced, so a loop that only woke for the client
	// would hold the finding until the next keystroke.
	mut push_proc := os.new_process(bin)
	push_proc.set_redirect_stdio()
	push_proc.run()
	mut pusher := Runner{
		framer: Framer{
			fd: push_proc.stdio_fd[1]
		}
		out_fd: push_proc.stdio_fd[0]
	}
	push_uri := 'file://${os.getwd()}/testdata/smoke/unsaved.v'
	pusher.send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":' +
		'{"textDocument":{"diagnostic":{},"publishDiagnostics":{}}}}}')
	pusher.next(wait_for_reply_ms) or { eprintln('smoke: the push server did not answer') }
	pusher.send('{"jsonrpc":"2.0","method":"initialized","params":{}}')
	pusher.send(open_notification(push_uri, broken))
	if pushed := pusher.next(wait_for_reply_ms) {
		pusher.record('the pushed report is a publishDiagnostics notification',
			pushed.method == 'textDocument/publishDiagnostics' && pushed.kind == .notification,
			pushed.method)
		params := as_map(pushed.params) or { no_map() }
		uri := (params['uri'] or { json2.Any('') }).str()
		version := (params['version'] or { json2.Any(0) }).int()
		items := as_list(params['diagnostics'] or { json2.Any(no_list()) }) or { no_list() }
		pusher.record('the push names the buffer it is about', uri == push_uri && version == 1,
			'${uri} at version ${version}')
		pusher.record('the pushed report carries the finding', items.len == 1,
			'${items.len} findings')
		if items.len == 1 {
			line, character := finding_position(items[0])
			pusher.record('the pushed finding sits at 2:0', line == 2 && character == 0,
				'${line}:${character}')
		}
	} else {
		pusher.record('a pushed report arrives with the client quiet', false,
			'nothing arrived within ${wait_for_reply_ms} ms')
	}
	pusher.send('{"jsonrpc":"2.0","id":2,"method":"shutdown"}')
	pusher.next(wait_for_reply_ms) or { eprintln('smoke: the push server did not answer shutdown') }
	pusher.send('{"jsonrpc":"2.0","method":"exit"}')
	push_proc.wait()
	runner.record('the push session exits cleanly', push_proc.code == 0, 'exit code ${push_proc.code}')
	// The push process ran its own checks through its own runner, and a failure
	// there has to reach the exit code the same way the rest of them do.
	runner.checks += pusher.checks
	runner.failures += pusher.failures

	println('${runner.checks} checks, ${runner.failures} failed')
	if runner.failures > 0 {
		exit(1)
	}
	println('smoke: ok')
}
