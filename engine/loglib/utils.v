// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module loglib

import os
import io

pub fn check_if_terminal(w io.Writer) bool {
	if w is os.File {
		return is_terminal(w.fd)
	}
	return false
}

// is_terminal reports whether the file descriptor is attached to a terminal.
// On Windows a ConEmu console or one with virtual terminal processing counts.
pub fn is_terminal(fd int) bool {
	$if windows {
		env_conemu := os.getenv('ConEmuANSI')
		if env_conemu == 'ON' {
			return true
		}
		// 4 is enable_virtual_terminal_processing
		return (os.is_atty(fd) & 0x0004) > 0
	}

	return os.is_atty(fd) > 0
}
