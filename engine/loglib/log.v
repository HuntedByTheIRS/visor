// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module loglib

import io
import time

@[inline]
pub fn log(level LogLevel, msg ...string) {
	logger.log(level, ...msg)
}

// log_one writes msg at the given level.
@[inline]
pub fn log_one(level LogLevel, msg string) {
	logger.log(level, msg)
}

// warn writes msg at the warn level.
@[inline]
pub fn warn(msg ...string) {
	logger.log(.warn, ...msg)
}

// info writes msg at the info level.
@[inline]
pub fn info(msg ...string) {
	logger.log(.info, ...msg)
}

// trace writes msg at the trace level.
@[inline]
pub fn trace(msg ...string) {
	logger.log(.trace, ...msg)
}

// error writes msg at the error level.
@[inline]
pub fn error(msg ...string) {
	logger.log(.error, ...msg)
}

// set_level changes which messages are logged; anything below level is dropped.
@[inline]
pub fn set_level(level LogLevel) {
	logger.set_level(level)
}

// set_flush_rate sets how often buffered output is written out.
@[inline]
pub fn set_flush_rate(dur time.Duration) {
	logger.flush_rate = dur
}

// set_output redirects the log output to out.
@[inline]
pub fn set_output(out io.Writer) {
	logger.set_output(out)
}

// get_output returns the writer the log output goes to.
@[inline]
pub fn get_output() io.Writer {
	return logger.get_output()
}

// with_fields starts an entry carrying fields.
@[inline]
pub fn with_fields(fields Fields) &Entry {
	return logger.with_fields(fields)
}

// with_duration starts an entry carrying dur as its duration.
@[inline]
pub fn with_duration(dur time.Duration) &Entry {
	return logger.with_duration(dur)
}

// with_gc_heap_usage starts an entry carrying usage as its heap stat.
@[inline]
pub fn with_gc_heap_usage(usage GCHeapUsage) &Entry {
	return logger.with_gc_heap_usage(usage)
}
