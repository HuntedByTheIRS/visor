module main

// update_ver writes a new version into VERSION and carries the string to every
// other place in the tree that spells the old one out.
//
//   v run tools/update_ver.vsh 0.0.3
//   v run tools/update_ver.vsh 0.0.3 -n    # print the plan, write nothing
//
// VERSION is the only source of truth: the binary embeds the file at build
// time, and `visor --version` prints what it holds. Every other copy of that
// string has to move with it. The issue templates ask a reporter for the
// version they ran. The smoke golden records the `serverInfo` block the server
// sends back. A doc that quotes a release number goes stale the same way.
//
// A copy is an exact match on the previous version, with one boundary rule: the
// match cannot begin or end inside a number, so `0.0.2` is not found in
// `0.0.20`. A `v` in front is fine, since `v0.0.2` is this version wearing the
// prefix the docs prefer. Everything else that looks like a version stays
// where it is: `0.5.2` is the V compiler this tree needs, and `v0.1.0` is a
// release ROADMAP.md plans for. Neither one moves when this one does.
//
// The scan reads tracked files only. Local state under `.omh`, build output and
// the scratch directories are not part of the repository, so they are not the
// tool's business.
//
// v.mod declares a version of its own, so it is set from the new number rather
// than matched against the old one. It had drifted a patch behind VERSION, and
// a declaration that disagrees with VERSION is wrong whether or not anyone
// bumps that day.
//
// The plan is built in full before the first write. Every file is read and
// rewritten in memory, so the only failure left when writing starts is the
// disk itself.

import os
import strings

const usage = 'usage: v run tools/update_ver.vsh <version> [-n|--dry-run]'

const version_path = 'VERSION'

const manifest_path = 'v.mod'

// Edit is one file and the text it should hold once the bump lands.
struct Edit {
	path  string
	text  string
	found int // mentions of the old version, for the report
	note  string
}

// Bump is one run: the version being replaced, the one replacing it, and
// whether the writes should actually happen.
struct Bump {
	old string
	new string
	dry bool
}

fn main() {
	args := os.args[1..]
	if args.any(it in ['-h', '--help']) {
		println(usage)
		return
	}
	mut requested := ''
	mut dry := false
	for arg in args {
		if arg in ['-n', '--dry-run'] {
			dry = true
			continue
		}
		if arg.starts_with('-') {
			eprintln('update_ver: unknown flag "${arg}"')
			eprintln(usage)
			exit(1)
		}
		if requested != '' {
			eprintln('update_ver: one version at a time')
			eprintln(usage)
			exit(1)
		}
		requested = arg
	}
	if requested == '' {
		eprintln(usage)
		exit(1)
	}
	next := checked_version(requested) or {
		eprintln('update_ver: ${err.msg()}')
		eprintln(usage)
		exit(1)
	}
	old := os.read_file(version_path) or {
		eprintln('update_ver: ${version_path} cannot be read: ${err.msg()}')
		exit(1)
	}.trim_space()
	if old == '' {
		eprintln('update_ver: ${version_path} is empty')
		exit(1)
	}
	bump := Bump{
		old: old
		new: next
		dry: dry
	}
	files := tracked_files() or {
		eprintln('update_ver: ${err.msg()}')
		exit(1)
	}
	edits := bump.plan(files)
	if edits.len == 0 {
		println('update_ver: nothing to change, the tree already says ${next}')
		return
	}
	println('update_ver: ${old} -> ${next}${if dry { ' (dry run)' } else { '' }}')
	bump.report(edits)
	if dry {
		println('nothing written')
		return
	}
	for edit in edits {
		os.write_file(edit.path, edit.text) or {
			eprintln('update_ver: ${edit.path} cannot be written: ${err.msg()}')
			exit(1)
		}
	}
	mentions := edits.filter(it.found > 0).len
	println('wrote ${edits.len} files, ${mentions} of them copies of the version')
}

// checked_version rejects anything that is not a version, before a run starts
// rewriting files with it. Pre-release and build metadata suffixes are allowed;
// the three numbers are not optional.
fn checked_version(requested string) !string {
	core := requested.split('-')[0].split('+')[0]
	parts := core.split('.')
	if parts.len != 3 {
		return error('"${requested}" is not three numbers, as in 0.0.3')
	}
	for part in parts {
		if part == '' || !part.bytes().all(it.is_digit()) {
			return error('"${requested}" is not three numbers, as in 0.0.3')
		}
	}
	return requested
}

// tracked_files is the file list the scan runs over. git answers for what is in
// the repository, which keeps the walk off build output and local scratch.
fn tracked_files() ![]string {
	result := os.execute('git ls-files -z')
	if result.exit_code != 0 {
		return error('git ls-files failed with exit code ${result.exit_code}')
	}
	mut files := []string{}
	for name in result.output.split('\x00') {
		if name != '' {
			files << name
		}
	}
	return files
}

// plan reads every candidate and returns the edits worth making. A file that
// holds no mention of the old version, or that would come out unchanged, is not
// in the list.
fn (b Bump) plan(files []string) []Edit {
	mut edits := []Edit{}
	for path in files {
		if path == manifest_path {
			continue // set as a declaration below, not matched as a mention
		}
		text := os.read_file(path) or { continue }
		if text.index_u8(0) != -1 {
			continue // binary: no version string lives in a file like this
		}
		found := count_mentions(text, b.old)
		if found == 0 {
			continue
		}
		updated := replace_mentions(text, b.old, b.new)
		if updated == text {
			continue
		}
		edits << Edit{
			path:  path
			text:  updated
			found: found
		}
	}
	manifest := os.read_file(manifest_path) or { return edits }
	declared := manifest_version(manifest)
	if declared != b.new {
		edits << Edit{
			path: manifest_path
			text: with_manifest_version(manifest, b.new)
			note: 'version declaration ${declared}'
		}
	}
	return edits
}

// report prints what the run would do, one line per file. The paths are padded
// to the longest of them so the counts line up.
fn (b Bump) report(edits []Edit) {
	mut width := 0
	for edit in edits {
		if edit.path.len > width {
			width = edit.path.len
		}
	}
	for edit in edits {
		path := edit.path + ' '.repeat(width - edit.path.len)
		if edit.found > 0 {
			println('  ${path}  ${edit.found} mention${if edit.found == 1 { '' } else { 's' }}')
			continue
		}
		println('  ${path}  ${edit.note} -> ${b.new}')
	}
}

// manifest_version reads the version v.mod declares, or an empty string when
// the file has no version line.
fn manifest_version(text string) string {
	for line in text.split_into_lines() {
		body := line.trim_space()
		if body.starts_with('version:') {
			value := body.all_after('version:').trim_space()
			return value.trim("'").trim('"')
		}
	}
	return ''
}

// with_manifest_version returns the manifest with its version line set to
// `version`, leaving the rest of the file alone. A manifest with no version
// line comes back unchanged, and the caller drops it for lack of a diff.
fn with_manifest_version(text string, version string) string {
	mut lines := []string{}
	for line in text.split_into_lines() {
		if line.trim_space().starts_with('version:') {
			indent := line[..line.len - line.trim_left('\t').len]
			lines << "${indent}version: '${version}'"
			continue
		}
		lines << line
	}
	return lines.join('\n') + '\n'
}

// is_mention reports whether the old version sits at byte offset `at` as a
// number of its own. A digit or a dot on either side means the text is a longer
// number, not this version.
fn is_mention(text string, at int, old string) bool {
	if old == '' || at + old.len > text.len {
		return false
	}
	if text[at..at + old.len] != old {
		return false
	}
	if at > 0 && (text[at - 1].is_digit() || text[at - 1] == u8(`.`)) {
		return false
	}
	end := at + old.len
	if end < text.len && (text[end].is_digit() || text[end] == u8(`.`)) {
		return false
	}
	return true
}

fn count_mentions(text string, old string) int {
	mut count := 0
	mut at := 0
	for at + old.len <= text.len {
		if is_mention(text, at, old) {
			count++
			at += old.len
			continue
		}
		at++
	}
	return count
}

fn replace_mentions(text string, old string, next string) string {
	mut out := strings.Builder{}
	mut at := 0
	for at < text.len {
		if is_mention(text, at, old) {
			out.write_string(next)
			at += old.len
			continue
		}
		out.write_u8(text[at])
		at++
	}
	return out.str()
}
