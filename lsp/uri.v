// uri.v maps the names the protocol uses onto paths the compiler can read.
//
// A client names a file by URI, and the compiler wants a path: every feature
// that runs the compiler crosses this boundary once. The scheme, the authority
// and the percent escapes all have to go, and the same file is not spelled the
// same way twice by every editor.
module lsp

import os

// path_from_uri turns a file URI into the path the compiler is handed.
//
// A URI that is not a file URI returns an empty string. Nothing else can be
// read by a compiler, and a guess at a path would put diagnostics on a file the
// person never opened.
//
// Linux paths only: a Windows drive letter arrives as `/c:/...` here, which is
// not a path that compiler call could use. Nothing in this repository builds
// for Windows yet, so the case is named rather than half-done.
pub fn path_from_uri(uri string) string {
	if !uri.starts_with('file://') {
		return ''
	}
	mut rest := uri[7..]
	// `file:///tmp/a.v` has no authority and starts at the root slash.
	// `file://localhost/tmp/a.v` names the machine the file is on, which for a
	// server running on that machine is the same file.
	if !rest.starts_with('/') {
		slash := rest.index('/') or { return '' }
		rest = rest[slash..]
	}
	// A query or a fragment is not part of the path, and reading one as text
	// would invent a filename that no compiler can find.
	for marker in ['?', '#'] {
		if at := rest.index(marker) {
			rest = rest[..at]
		}
	}
	return percent_decoded(rest)
}

// root_for_path is the module root a compiler run starts in: the workspace
// folder the file sits under, or its own directory when no folder contains it.
//
// Imports resolve against this, so a file inside a project has to be checked
// from the project rather than from wherever the server happens to have been
// started. The longest matching folder wins, so a file in a nested folder is
// checked from the folder closest to it.
pub fn root_for_path(path string, folders []WorkspaceFolder) string {
	if path == '' {
		return ''
	}
	mut best := ''
	for folder in folders {
		root := path_from_uri(folder.uri)
		if root == '' || !path.starts_with(root) {
			continue
		}
		// A folder has to end on a path boundary. `/tmp/project` does not
		// contain `/tmp/project-other`.
		if root != '/' && path.len > root.len && path[root.len] != `/` {
			continue
		}
		if root.len > best.len {
			best = root
		}
	}
	if best == '' {
		return os.dir(path)
	}
	return best
}

// percent_decoded resolves the %XX escapes of a URI. Only the escapes are
// touched: a path is bytes, and everything else in it stands as it is. A `%`
// that does not start an escape stays where it is, because a path holding one
// is a path, not a broken URI.
fn percent_decoded(text string) string {
	if !text.contains('%') {
		return text
	}
	mut out := []u8{cap: text.len}
	mut at := 0
	for at < text.len {
		if text[at] == `%` && at + 2 < text.len {
			high := hex_digit(text[at + 1])
			low := hex_digit(text[at + 2])
			if high >= 0 && low >= 0 {
				out << u8(high * 16 + low)
				at += 3
				continue
			}
		}
		out << text[at]
		at++
	}
	return out.bytestr()
}

// hex_digit reads one hex digit, or -1 when the byte is not one.
fn hex_digit(ch u8) int {
	if ch >= `0` && ch <= `9` {
		return int(ch - `0`)
	}
	if ch >= `a` && ch <= `f` {
		return int(ch - `a`) + 10
	}
	if ch >= `A` && ch <= `F` {
		return int(ch - `A`) + 10
	}
	return -1
}
