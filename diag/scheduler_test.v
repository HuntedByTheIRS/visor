module diag

import vtool

// A policy with the debounce the server runs with. The tests feed the clock
// their own milliseconds, so the number is a label rather than a wait.
fn policy() Policy {
	return Policy{
		debounce_ms:  250
		max_per_pass: 2
		max_per_root: 1
	}
}

fn job_for(uri string, root string, version int, text string) Job {
	return Job{
		uri:     uri
		path:    uri.replace('file://', '')
		root:    root
		version: version
		text:    text
	}
}

// One error, in the shape the compiler reported it: the line and column it
// printed, one based, and the path the caller asked about.
fn one_error() vtool.CheckResult {
	return vtool.CheckResult{
		diagnostics: [
			vtool.Diagnostic{
				file:     '/tmp/proj/a.v'
				line:     3
				col:      1
				severity: .error
				message:  'invalid expression: unexpected token `}`'
			},
		]
		exit_code:   1
		has_error:   true
		raw:         'a.v:3:1: error: invalid expression: unexpected token `}`'
	}
}

fn clean() vtool.CheckResult {
	return vtool.CheckResult{}
}

// has_report asks whether a finished check is held for a document. An option
// compared to none does not read well in an assertion, so the question gets a
// name.
fn has_report(s &Scheduler, uri string) bool {
	if _ := s.report(uri) {
		return true
	}
	return false
}

fn test_an_edit_waits_for_the_debounce() {
	mut s := new_scheduler(policy())
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 1, 'x'), 0)
	assert s.waiting_count() == 1
	assert s.due(0).len == 0
	assert s.due(249).len == 0
	jobs := s.due(250)
	assert jobs.len == 1
	assert jobs[0].uri == 'file:///tmp/proj/a.v'
	assert s.checks_started == 1
	// the job left the queue when it was handed out, so a later pass does not
	// run the same text twice.
	assert s.waiting_count() == 0
	assert s.due(1000).len == 0
}

fn test_an_edit_inside_the_window_moves_the_check_later() {
	mut s := new_scheduler(policy())
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 1, 'one'), 0)
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 2, 'two'), 100)
	assert s.absorbed == 1
	// the first edit's deadline has passed and the check still waits, because
	// what runs is the buffer as it stands after the second edit.
	assert s.due(260).len == 0
	jobs := s.due(350)
	assert jobs.len == 1
	assert jobs[0].version == 2
	assert jobs[0].text == 'two'
}

fn test_a_burst_of_edits_starts_one_check() {
	mut s := new_scheduler(policy())
	// A hundred keystrokes the way a person types them, each one inside the
	// debounce window of the one before.
	for version in 1 .. 101 {
		s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', version, 'v${version}'),
			i64(version))
	}
	assert s.checks_started == 0
	jobs := s.due(350)
	assert jobs.len == 1
	assert jobs[0].version == 100
	assert s.checks_started == 1
	assert s.absorbed == 99
}

fn test_a_check_that_ran_against_a_stale_buffer_is_dropped() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 4, 'broken'), 0)
	started := s.due(250)
	assert started.len == 1
	// the buffer moved while the compiler ran, so this report describes text
	// nobody is looking at any more.
	report := s.complete(started[0], one_error(), Standing{
		open:    true
		version: 5
	})
	if _ := report {
		assert false, 'a report was kept for a version the buffer had left'
	}
	assert s.superseded == 1
	assert s.running_count() == 0
	assert !has_report(s, uri)
}

fn test_the_report_for_the_current_version_is_kept() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 4, 'broken'), 0)
	started := s.due(250)
	report := s.complete(started[0], one_error(), Standing{
		open:    true
		version: 4
	}) or { panic('no report') }
	assert report.uri == uri
	assert report.version == 4
	assert report.result_id == '4'
	assert report.diagnostics.len == 1
	assert report.has_error
	cached := s.report(uri) or { panic('the report was not kept') }
	assert cached.result_id == '4'
}

fn test_a_pull_that_echoes_the_result_id_is_unchanged() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 4, 'broken'), 0)
	started := s.due(250)
	report := s.complete(started[0], one_error(), Standing{
		open:    true
		version: 4
	}) or { panic('no report') }
	assert s.pull(uri, 4, report.result_id) == .unchanged
	// a client that echoes an id from an older version is asking about a
	// version this report does not describe, so it gets the report again.
	assert s.pull(uri, 4, '3') == .cached
	assert s.pull(uri, 5, report.result_id) == .fresh
	// a document the scheduler has never checked has nothing to answer from,
	// whatever the client echoed.
	assert s.pull('file:///tmp/proj/other.v', 1, '') == .fresh
}

fn test_a_pull_without_an_echoed_id_runs_no_compiler() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 7, 'clean'), 0)
	started := s.due(250)
	s.complete(started[0], clean(), Standing{
		open:    true
		version: 7
	}) or { panic('no report') }
	assert s.pull(uri, 7, '') == .cached
	assert s.checks_started == 1
}

fn test_a_pull_answers_a_check_that_was_already_waiting() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 3, 'text'), 0)
	// the client asked before the debounce expired. The check the pull runs
	// reads the same text, so the scheduled one has nothing left to add.
	s.complete(job_for(uri, '/tmp/proj', 3, 'text'), one_error(), Standing{
		open:    true
		version: 3
	}) or { panic('no report') }
	assert s.dropped == 1
	assert s.waiting_count() == 0
	assert s.due(250).len == 0
}

fn test_one_check_at_a_time_per_module_root() {
	mut s := new_scheduler(policy())
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 1, 'a'), 0)
	s.note_edit(job_for('file:///tmp/proj/b.v', '/tmp/proj', 1, 'b'), 0)
	// Two buffers, one module: one check runs and the second waits for it to
	// end, because both of them would read the same tree.
	first := s.due(250)
	assert first.len == 1
	assert s.running_count() == 1
	assert s.due(250).len == 0
	s.complete(first[0], clean(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	assert s.running_count() == 0
	second := s.due(250)
	assert second.len == 1
	assert second[0].root == first[0].root
	assert second[0].uri != first[0].uri
	// A buffer in another module is a different tree, so it gets its own check
	// while this one is still in flight.
	s.note_edit(job_for('file:///tmp/other/c.v', '/tmp/other', 1, 'c'), 0)
	third := s.due(250)
	assert third.len == 1
	assert third[0].root == '/tmp/other'
	s.complete(second[0], clean(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	s.complete(third[0], clean(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	assert s.running_count() == 0
	assert s.checks_started == 3
}

fn test_the_pass_cap_holds_across_module_roots() {
	mut s := new_scheduler(policy())
	for name in ['a', 'b', 'c'] {
		s.note_edit(job_for('file:///tmp/${name}/main.v', '/tmp/${name}', 1, name), 0)
	}
	first := s.due(250)
	assert first.len == 2
	// the third root waits for the next pass rather than for the client to say
	// something. Which two went first is not promised, so only the count is.
	s.complete(first[0], clean(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	s.complete(first[1], clean(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	rest := s.due(250)
	assert rest.len == 1
	assert s.checks_started == 3
}

fn test_a_closed_document_leaves_nothing_behind() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 1, 'a'), 0)
	started := s.due(250)
	s.complete(started[0], one_error(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	s.note_edit(job_for(uri, '/tmp/proj', 2, 'b'), 300)
	s.forget(uri)
	assert s.waiting_count() == 0
	assert s.dropped == 1
	assert !has_report(s, uri)
	assert s.pull(uri, 2, '') == .fresh
}

fn test_a_check_whose_document_closed_reports_nothing() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 1, 'a'), 0)
	started := s.due(250)
	s.forget(uri)
	// the check finished for a document that is gone, so there is nobody to
	// publish to.
	report := s.complete(started[0], one_error(), Standing{
		open:    false
		version: 1
	})
	if _ := report {
		assert false, 'a closed document was given a report'
	}
	assert !has_report(s, uri)
}

fn test_a_document_reopened_at_the_same_version_is_checked_again() {
	mut s := new_scheduler(policy())
	uri := 'file:///tmp/proj/a.v'
	s.note_edit(job_for(uri, '/tmp/proj', 1, 'broken'), 0)
	started := s.due(250)
	s.complete(started[0], one_error(), Standing{
		open:    true
		version: 1
	}) or { panic('no report') }
	// closed and opened again at version 1, which is where a fresh session
	// starts counting. The report that was kept describes a buffer that no
	// longer exists.
	s.forget(uri)
	assert s.pull(uri, 1, '') == .fresh
}

fn test_the_next_check_is_the_earliest_one_scheduled() {
	mut s := new_scheduler(policy())
	// nothing scheduled: there is no moment to name, and a loop that slept until
	// one would never wake.
	if _ := s.next_due() {
		assert false, 'an empty scheduler named a moment'
	}
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 1, 'broken'), 0)
	s.note_edit(job_for('file:///tmp/proj/b.v', '/tmp/proj', 1, 'broken'), 100)
	// the first edit is due at 250 and the second at 350, so the loop comes back
	// for the first one.
	first := s.next_due() or { panic('a scheduled check had no moment') }
	assert first == 250
	// an edit inside the window moves its own check later, so the moment now
	// belongs to the buffer nobody touched.
	s.note_edit(job_for('file:///tmp/proj/a.v', '/tmp/proj', 2, 'broken'), 400)
	second := s.next_due() or { panic('a scheduled check had no moment') }
	assert second == 350
	// and once that one is gone, the moved check is the next moment.
	s.forget('file:///tmp/proj/b.v')
	moved := s.next_due() or { panic('a scheduled check had no moment') }
	assert moved == 650
	s.forget('file:///tmp/proj/a.v')
	if _ := s.next_due() {
		assert false, 'a scheduler with nothing scheduled named a moment'
	}
}
