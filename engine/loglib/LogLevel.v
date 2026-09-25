// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module loglib

pub enum LogLevel {
	panic
	fatal
	error
	warn
	info
	debug
	trace
}

fn (l LogLevel) label() string {
	return match l {
		.panic { 'PANIC' }
		.fatal { 'FATAL' }
		.error { 'ERROR' }
		.warn { 'WARN' }
		.info { 'INFO' }
		.debug { 'DEBUG' }
		.trace { 'TRACE' }
	}
}
