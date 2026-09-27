module diag

import vtool

// Waiter is a document with a check scheduled for it.
struct Waiter {
	job    Job
	due_at i64
}

// Scheduler is the queue between edits and checks, and the store of what the
// last check of each document found.
//
// Checks run on the serving thread, so there is never more than one running in
// the process. What the queue buys is the other half: an edit that arrives
// while a buffer is still moving replaces the work that was pending rather than
// queueing behind it, and a check that finishes against text nobody is looking
// at any more is dropped instead of published.
pub struct Scheduler {
mut:
	policy Policy
	// waiting is one entry per document with a check scheduled.
	waiting map[string]Waiter
	// running counts checks in flight per module root.
	running map[string]int
	// reports is the newest finished check per document, which is what a pull
	// answers from when the buffer has not moved since.
	reports map[string]Report
pub mut:
	// checks_started counts the compiler runs this scheduler began.
	checks_started int
	// absorbed counts edits that landed on a document that already had a check
	// waiting. Each one is a check that did not have to start.
	absorbed int
	// superseded counts finished checks dropped because the buffer moved while
	// the compiler ran.
	superseded int
	// dropped counts scheduled checks given up without a compiler run, because
	// the document closed or a pull answered that version first.
	dropped int
}

// new_scheduler returns a scheduler with no documents and the given policy.
pub fn new_scheduler(policy Policy) Scheduler {
	return Scheduler{
		policy:  policy
		waiting: map[string]Waiter{}
		running: map[string]int{}
		reports: map[string]Report{}
	}
}

// note_edit schedules a check of the buffer debounce_ms from now, replacing
// whatever was scheduled for this document. The text is kept as it is at the
// moment of the call, because the next edit sends its own text and the two
// together would be a check of a buffer that never existed.
pub fn (mut s Scheduler) note_edit(job Job, now i64) {
	if job.uri in s.waiting {
		s.absorbed++
	}
	s.waiting[job.uri] = Waiter{
		job:    job
		due_at: now + s.policy.debounce_ms
	}
}

// due hands back the jobs that may run now: a buffer that has settled, a module
// root with room for another check, and no more than the policy allows in one
// pass.
//
// Which buffers win the cap is not promised. V does not order map iteration,
// and the cap is a ceiling on work rather than a queue position.
pub fn (mut s Scheduler) due(now i64) []Job {
	mut out := []Job{}
	mut started := map[string]int{}
	for uri, waiter in s.waiting {
		if out.len >= s.policy.max_per_pass {
			continue
		}
		if now < waiter.due_at {
			continue
		}
		busy := (s.running[waiter.job.root] or { 0 }) + (started[waiter.job.root] or { 0 })
		if busy >= s.policy.max_per_root {
			continue
		}
		out << waiter.job
		started[waiter.job.root] = (started[waiter.job.root] or { 0 }) + 1
	}
	for job in out {
		s.waiting.delete(job.uri)
		s.running[job.root] = (s.running[job.root] or { 0 }) + 1
		s.checks_started++
	}
	return out
}

// complete records a finished check and returns the report worth handing to a
// client, if there is one.
//
// result is what the compiler printed, and standing says what the caller knows
// about the document now. When it closed
// while the compiler ran there is nobody to publish to, and when its version
// moved the text that was read is already gone: the edit that replaced it
// scheduled its own check, and publishing this report would put a diagnostic on
// a line the person has since moved. Either way the report is dropped, and the
// count is the record of it.
pub fn (mut s Scheduler) complete(job Job, result vtool.CheckResult, standing Standing) ?Report {
	s.release(job.root)
	if !standing.open {
		s.superseded++
		return none
	}
	if waiter := s.waiting[job.uri] {
		if waiter.job.version == job.version {
			// the version this check covered is the one waiting, so the work is
			// already done and the waiter has nothing left to run.
			s.waiting.delete(job.uri)
			s.dropped++
		}
	}
	if standing.version != job.version {
		s.superseded++
		return none
	}
	report := Report{
		uri:         job.uri
		version:     job.version
		result_id:   job.version.str()
		diagnostics: result.diagnostics
		has_error:   result.has_error
	}
	s.reports[job.uri] = report
	return report
}

// pull says what answers a textDocument/diagnostic request for a document.
// previous_id is what the client echoed back, empty when it sent none.
//
// A buffer the scheduler has checked at its current version does not need the
// compiler run again: a pull and a push describe the same text. The run is only
// earned when the version moved, which is the case the client is asking about.
pub fn (s &Scheduler) pull(uri string, version int, previous_id string) Pull {
	report := s.reports[uri] or { return .fresh }
	if report.version != version {
		return .fresh
	}
	if previous_id != '' && previous_id == report.result_id {
		return .unchanged
	}
	return .cached
}

// report returns the newest finished check for a document.
pub fn (s &Scheduler) report(uri string) ?Report {
	return s.reports[uri] or { none }
}

// forget drops everything the scheduler holds for a document, which is what a
// close means. The check already running for it is left to finish: it costs
// nothing to let it end, and killing a compiler mid-run would leave the caller
// holding half a pipe.
pub fn (mut s Scheduler) forget(uri string) {
	if uri in s.waiting {
		s.waiting.delete(uri)
		s.dropped++
	}
	s.reports.delete(uri)
}

// release records that a check for this root finished.
fn (mut s Scheduler) release(root string) {
	left := (s.running[root] or { 1 }) - 1
	if left <= 0 {
		s.running.delete(root)
		return
	}
	s.running[root] = left
}

// waiting_count is how many documents have a check scheduled.
pub fn (s &Scheduler) waiting_count() int {
	return s.waiting.len
}

// running_count is how many checks are in flight across every module root.
pub fn (s &Scheduler) running_count() int {
	mut total := 0
	for _, count in s.running {
		total += count
	}
	return total
}
