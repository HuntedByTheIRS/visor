// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

@[has_globals; translated]
module loglib

import term
import io
import os
import time

__global logger = Logger{
	formatter: TextFormatter{}
	out:       os.stderr()
}

pub const support_colors = term.can_show_color_on_stderr() && term.can_show_color_on_stdout()

@[heap]
pub struct Logger {
pub mut:
	disabled   bool
	color_mode ColorMode

	formatter  Formatter
	out        io.Writer
	last_flush time.Time
	flush_rate time.Duration = 5 * time.second

	level u64 = u64(LogLevel.info)
}

// disable turns logging off until enable is called.
@[inline]
pub fn (mut l Logger) disable() {
	l.disabled = true
}

// enable resumes logging after disable.
@[inline]
pub fn (mut l Logger) enable() {
	l.disabled = false
}

// use_color_mode selects how the logger colorises its output.
@[inline]
pub fn (mut l Logger) use_color_mode(mode ColorMode) {
	l.color_mode = mode
}

// use_color_mode_string sets the color mode by name, falling back to auto when the name is unknown.
@[inline]
pub fn (mut l Logger) use_color_mode_string(mode string) {
	enum_value := get_color_mode_by_name(mode) or { ColorMode.auto }
	l.color_mode = enum_value
}

// level returns the current log level.
@[inline]
pub fn (l &Logger) level() u64 {
	return l.level
}

// set_level changes which messages the logger keeps; anything below level is dropped.
@[inline]
pub fn (mut l Logger) set_level(level LogLevel) {
	l.level = u64(level)
}

// set_flush_rate sets how often buffered output is written out.
@[inline]
pub fn (mut l Logger) set_flush_rate(dur time.Duration) {
	l.flush_rate = dur
}

// set_output redirects the logger's output to out.
@[inline]
pub fn (mut l Logger) set_output(out io.Writer) {
	l.out = out
}

// get_output returns the writer the logger writes to.
@[inline]
pub fn (mut l Logger) get_output() io.Writer {
	return l.out
}

// is_level_enabled reports whether messages of level are logged.
@[inline]
pub fn (l &Logger) is_level_enabled(level LogLevel) bool {
	return l.level() >= u64(level)
}

// log writes msg at level, unless that level is disabled.
pub fn (l &Logger) log(level LogLevel, msg ...string) {
	if !l.is_level_enabled(level) {
		return
	}

	entry := new_entry(l)
	entry.log(level, ...msg)
}

// with_fields starts an entry carrying fields.
@[inline]
pub fn (mut l Logger) with_fields(fields Fields) &Entry {
	entry := new_entry(l)
	return entry.with_fields(fields)
}

// with_duration starts an entry carrying dur as its duration.
@[inline]
pub fn (mut l Logger) with_duration(dur time.Duration) &Entry {
	entry := new_entry(l)
	return entry.with_duration(dur)
}

// with_gc_heap_usage starts an entry carrying usage as its heap stat.
@[inline]
pub fn (mut l Logger) with_gc_heap_usage(usage GCHeapUsage) &Entry {
	entry := new_entry(l)
	return entry.with_gc_heap_usage(usage)
}
