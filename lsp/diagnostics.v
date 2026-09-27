// diagnostics.v answers what the compiler found wrong with a buffer, both ways
// round: pushed as the person types, and pulled when the client asks.
//
// Both answers are computed from the buffer the client holds, never from the
// file on disk, and the text reaches the compiler on stdin. That is what makes
// an unsaved buffer diagnosable, and it is also why a report here can be newer
// than anything on disk.
module lsp

import diag
import json2
import time
import vtool

// publish_method is the notification an editor draws findings with. It is a
// constant because a typo in it is silent: the client would simply never show
// anything, and the server would have no way to notice.
const publish_method = 'textDocument/publishDiagnostics'

// handle_diagnostic answers textDocument/diagnostic from the open buffer.
//
// Every way this can fail is an error naming the cause. A client that asked a
// question and got an empty list would read it as a file with no problems,
// which is a claim this handler has not earned when it holds no compiler.
fn handle_diagnostic(mut s Server, req Message) Reply {
	params := as_object(req.params) or {
		return fail(code_invalid_params, 'diagnostic params is not an object')
	}
	item := parse_text_document(params['textDocument'] or {
		return fail(code_invalid_params, 'diagnostic has no textDocument')
	}) or { return fail(code_invalid_params, 'diagnostic textDocument has no uri') }
	document := s.document(item.uri) or {
		return fail(code_invalid_params, 'no open document for ${item.uri}')
	}
	compiler := s.checker() or { return fail(code_request_failed, err.msg()) }
	previous := string_field(params, 'previousResultId')
	match s.diagnostics.pull(item.uri, document.version, previous) {
		.unchanged {
			report := s.diagnostics.report(item.uri) or {
				return fail(code_content_modified, 'the report was dropped before it was read')
			}
			return ok(unchanged_report(report))
		}
		.cached {
			report := s.diagnostics.report(item.uri) or {
				return fail(code_content_modified, 'the report was dropped before it was read')
			}
			return ok(full_report(document.text, report))
		}
		.fresh {
			report := s.check_now(s.job_for(document), compiler) or {
				return fail(code_request_failed, err.msg())
			}
			return ok(full_report(document.text, report))
		}
	}
}

// schedule_check puts a buffer in line for a check. The check runs once the
// typing stops, which the scheduler decides; nothing is run here.
fn (mut s Server) schedule_check(uri string) {
	if !s.wants_diagnostics() {
		return
	}
	document := s.documents.get(uri) or { return }
	s.diagnostics.note_edit(s.job_for(document), clock())
}

// pump_diagnostics runs whatever checks are due and publishes their reports. It
// is called after every batch the server serves and again when the loop has
// nothing to read, so an edit earns its report without the client asking.
//
// The return value is how many notifications went out, which is what lets a
// test tell "this client asked for pushes and got one" from "this client never
// asked".
pub fn (mut s Server) pump_diagnostics(now i64) int {
	jobs := s.diagnostics.due(now)
	if jobs.len == 0 {
		return 0
	}
	compiler := s.checker() or {
		// Nothing can be run. A pushed empty list would read as a file with no
		// problems, and the missing capability was already named at
		// initialize, so the scheduled work is dropped instead.
		for job in jobs {
			s.diagnostics.forget(job.uri)
		}
		return 0
	}
	mut published := 0
	for job in jobs {
		report := s.check_now(job, compiler) or { continue }
		if s.publish(report) {
			published++
		}
	}
	return published
}

// quiet_for_ms is how long the serve loop may sleep on the client before it has
// to come back for a scheduled check: 0 when one is due now, and -1 when
// nothing is scheduled and the client may take as long as it likes.
//
// Without this the loop only wakes when the client writes, so a report would
// wait for the next keystroke to go out, and the client would be told about the
// line before the one the person just typed.
fn (s &Server) quiet_for_ms(now i64) i64 {
	due := s.diagnostics.next_due() or { return -1 }
	if due <= now {
		return 0
	}
	return due - now
}

// clear_diagnostics drops a buffer's report and clears whatever an editor is
// showing for it. A closed file keeps no marks: they would sit on lines nobody
// is looking at, and nothing would ever remove them.
fn (mut s Server) clear_diagnostics(uri string) {
	s.diagnostics.forget(uri)
	if !s.client_caps.advertises(cap_publish_diagnostics) {
		return
	}
	mut params := map[string]json2.Any{}
	params['uri'] = json2.Any(uri)
	params['diagnostics'] = json2.Any([]json2.Any{})
	s.write(encode_notification(publish_method, json2.Any(params)))
}

// check_now runs one check and keeps the report it produced. The error case is
// a compiler that would not run: a caller that has someone waiting for an
// answer has to say so rather than answer nothing.
fn (mut s Server) check_now(job diag.Job, compiler vtool.Compiler) !diag.Report {
	result := diag.check(job, compiler) or { return error(err.msg()) }
	standing := s.standing_for(job.uri)
	report := s.diagnostics.complete(job, result, standing) or {
		return error('the buffer moved while it was checked')
	}
	return report
}

// publish sends a report to the client, and reports whether anything went out.
//
// The report stays in the scheduler either way, because a client that pulls is
// asking about the same text and gets the same answer without a second compiler
// run.
fn (mut s Server) publish(report diag.Report) bool {
	if !s.client_caps.advertises(cap_publish_diagnostics) {
		return false
	}
	document := s.documents.get(report.uri) or {
		// the buffer closed between the check and the publish. A report for a
		// file nobody has open is one no editor would ever remove.
		return false
	}
	if document.version != report.version {
		// the buffer moved in between. The edit that moved it scheduled its own
		// check, so this one is dropped rather than sent against text it does
		// not describe.
		return false
	}
	s.write(encode_notification(publish_method, diagnostics_notification(report, document.text)))
	return true
}

// wants_diagnostics reports whether a report would be used by anyone: a client
// that pulls, a client that draws pushed findings, and a compiler that can
// produce one. Without all three, a scheduled check is a process started for
// nobody.
fn (s &Server) wants_diagnostics() bool {
	if !s.client_caps.advertises(cap_pull_diagnostics)
		&& !s.client_caps.advertises(cap_publish_diagnostics) {
		return false
	}
	if _ := s.checker() {
		return true
	}
	return false
}

// checker resolves what runs a check, or says why nothing can. The two failures
// are different to a person: a session with no compiler at all, and a compiler
// that ran and did not report diagnostics.
fn (s &Server) checker() !vtool.Compiler {
	compiler := s.compiler or {
		return error('no V compiler to check with: ${s.compiler_error}')
	}
	report := s.compiler_caps or {
		return error('the compiler was never probed, so a check is unproven')
	}
	if !report.supports(.check) {
		return error('this compiler cannot check a buffer: ${report.detail_of(.check)}')
	}
	return compiler
}

// job_for is the check for one buffer: the text the client sent, and the names
// the findings come back under. The path is the caller's, never the temporary
// name the compiler invents for a buffer it read on stdin.
fn (s &Server) job_for(document TextDocument) diag.Job {
	path := path_from_uri(document.uri)
	return diag.Job{
		uri:     document.uri
		path:    path
		root:    root_for_path(path, s.workspace_folders)
		version: document.version
		text:    document.text
	}
}

// standing_for is what the scheduler is told about a buffer once a check has
// run: the version it holds now, and whether it is still open at all.
fn (s &Server) standing_for(uri string) diag.Standing {
	document := s.documents.get(uri) or {
		return diag.Standing{
			open: false
		}
	}
	return diag.Standing{
		open:    true
		version: document.version
	}
}

// clock is the wall clock the debounce is measured against. It is a function so
// that the loop and the tests both go through one name.
fn clock() i64 {
	return time.ticks()
}

// diagnostics_notification builds the push payload: the file, the version the
// report describes, and the findings.
fn diagnostics_notification(report diag.Report, text string) json2.Any {
	mut params := map[string]json2.Any{}
	params['uri'] = json2.Any(report.uri)
	params['version'] = json2.Any(report.version)
	params['diagnostics'] = encode_diagnostics(text, report.diagnostics)
	return json2.Any(params)
}

// full_report is the answer to a pull that cannot be served from what the
// client already has.
fn full_report(text string, report diag.Report) json2.Any {
	mut result := map[string]json2.Any{}
	result['kind'] = json2.Any('full')
	result['resultId'] = json2.Any(report.result_id)
	result['items'] = encode_diagnostics(text, report.diagnostics)
	return json2.Any(result)
}

// unchanged_report is the answer to a client that echoed the id of the report
// it already holds. The id goes back so the client can keep using it.
fn unchanged_report(report diag.Report) json2.Any {
	mut result := map[string]json2.Any{}
	result['kind'] = json2.Any('unchanged')
	result['resultId'] = json2.Any(report.result_id)
	return json2.Any(result)
}

// encode_diagnostics turns the compiler's findings into the wire shape.
fn encode_diagnostics(text string, findings []vtool.Diagnostic) json2.Any {
	mut items := []json2.Any{cap: findings.len}
	for finding in findings {
		items << encode_diagnostic(text, finding)
	}
	return json2.Any(items)
}

// encode_diagnostic places one finding in the buffer.
//
// The compiler counts lines and columns from one and its column is a byte
// offset into the line. The wire counts lines from zero and characters in
// UTF-16 code units, so the position is recomputed from the byte offset rather
// than adjusted: a line holding an astral character would otherwise place every
// finding after it short by a unit per character.
//
// The compiler reports a point and says nothing about where the token it is
// complaining about ends, so the range runs from that point to the end of the
// line. A range of no width is invisible in some editors, which reads as no
// finding at all.
fn encode_diagnostic(text string, finding vtool.Diagnostic) json2.Any {
	line := if finding.line > 0 { finding.line - 1 } else { 0 }
	col := if finding.col > 0 { finding.col - 1 } else { 0 }
	stop := line_end(text, line)
	mut start := line_start(text, line) + col
	if start > stop {
		start = stop
	}
	mut item := map[string]json2.Any{}
	item['range'] = encode_range(Range{
		start: position_for_offset(text, start)
		end:   position_for_offset(text, stop)
	})
	item['severity'] = json2.Any(severity_number(finding.severity))
	// the compiler produced the finding, and an editor that shows several
	// sources from one server has to be able to say which one this is.
	item['source'] = json2.Any('v')
	item['message'] = json2.Any(finding.message)
	return json2.Any(item)
}

// severity_number maps the compiler's word for a finding onto the number the
// protocol counts in. The compiler has three levels and the protocol four: a
// notice is what an editor calls Information, and nothing the compiler prints
// is a hint.
fn severity_number(severity vtool.Severity) int {
	return match severity {
		.error { 1 }
		.warning { 2 }
		.notice { 3 }
	}
}

// line_start is the byte offset a zero based line begins at. A line past the
// end of the buffer starts at the end of it.
fn line_start(text string, line int) int {
	mut offset := 0
	mut seen := 0
	for seen < line && offset < text.len {
		if text[offset] == `\n` {
			seen++
		}
		offset++
	}
	return offset
}

// line_end is the byte offset of the newline that ends a line, or the end of
// the buffer when the line has none.
fn line_end(text string, line int) int {
	mut at := line_start(text, line)
	for at < text.len {
		if text[at] == `\n` {
			return at
		}
		at++
	}
	return text.len
}
