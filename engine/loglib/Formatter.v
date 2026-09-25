// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module loglib

pub interface Formatter {
mut:
	format(entry &Entry) ![]u8
}
