module lsp

import json2

pub struct ProgressSession {
pub:
	token string
	title string
pub mut:
	// started is set when the client answers the create request. Reports before
	// that have no token to report against.
	started bool
}

// ProgressReporter tracks the work-done tokens this server has opened. A token
// exists only once the client has created it, so a token the client declined is
// never reported on.
pub struct ProgressReporter {
mut:
	open map[string]ProgressSession
pub mut:
	begun    int
	reported int
	ended    int
	// declined counts create requests the client answered with an error.
	declined int
}

// progress_enabled reports whether the client advertised work-done progress.
// Everything below is a no-op when it did not.
fn (s &Server) progress_enabled() bool {
	return s.client_caps.flag(cap_work_done_progress)
}

// progress_begin asks the client to create a work-done token. The begin report
// follows the client's answer rather than the request, because a token the
// client did not create has nothing to report against.
pub fn (mut s Server) progress_begin(token string, title string) bool {
	if token == '' || !s.progress_enabled() {
		return false
	}
	if token in s.progress.open {
		return false
	}
	s.progress.open[token] = ProgressSession{
		token: token
		title: title
	}
	mut params := map[string]json2.Any{}
	params['token'] = json2.Any(token)
	s.ask('window/workDoneProgress/create', json2.Any(params), .progress_create, token)
	return true
}

// progress_report sends a report for a token the client has created.
pub fn (mut s Server) progress_report(token string, message string, percentage int) bool {
	session := s.progress.open[token] or { return false }
	if !session.started {
		return false
	}
	mut value := map[string]json2.Any{}
	value['kind'] = json2.Any('report')
	value['message'] = json2.Any(message)
	if percentage >= 0 {
		value['percentage'] = json2.Any(percentage)
	}
	s.send_progress(token, value)
	s.progress.reported++
	return true
}

// progress_end closes a token. A closed token is gone: a later report with the
// same token is a no-op rather than a second begin.
pub fn (mut s Server) progress_end(token string, message string) bool {
	session := s.progress.open[token] or { return false }
	if !session.started {
		return false
	}
	mut value := map[string]json2.Any{}
	value['kind'] = json2.Any('end')
	if message != '' {
		value['message'] = json2.Any(message)
	}
	s.send_progress(token, value)
	s.progress.open.delete(token)
	s.progress.ended++
	return true
}

// progress_open reports whether a token is currently open, which is what a lane
// checks before spending work on a report.
pub fn (s &Server) progress_open(token string) bool {
	session := s.progress.open[token] or { return false }
	return session.started
}

// progress_created is the answer to a create request. It sends the begin report.
fn (mut s Server) progress_created(token string) {
	mut session := s.progress.open[token] or { return }
	session.started = true
	s.progress.open[token] = session
	mut value := map[string]json2.Any{}
	value['kind'] = json2.Any('begin')
	value['title'] = json2.Any(session.title)
	// cancellation of a work-done token would need the work to be interruptible,
	// which none of it is yet.
	value['cancellable'] = json2.Any(false)
	s.send_progress(token, value)
	s.progress.begun++
}

// progress_declined drops a token the client refused.
fn (mut s Server) progress_declined(token string) {
	if token in s.progress.open {
		s.progress.open.delete(token)
	}
	s.progress.declined++
}

fn (mut s Server) send_progress(token string, value map[string]json2.Any) {
	mut params := map[string]json2.Any{}
	params['token'] = json2.Any(token)
	params['value'] = json2.Any(value)
	s.write(encode_notification('$/progress', json2.Any(params)))
}
