// session.v is what a server holds while it runs: one index over the folders
// the client has open, and the parse of every buffer it has been given.
//
// The split matters. The index says what a declaration is, and it is built from
// the files on disk because that is all an index can be built from cheaply. A
// buffer says what the text in front of the person is, and it is what every
// answer about that file has to be computed over. Ending an edit by refreshing
// the file's stubs is what keeps the two from disagreeing: the index answers
// `scaled : Point` for a call into the next file, and the buffer's own new
// function is in the index before the next question arrives.
//
// Nothing here writes to the disk. The text a client sends reaches the index
// through refresh_stub_file, which leaves the file alone, so an unsaved buffer
// is never mistaken for a save.
module engine

import engine.index
import engine.parser
import engine.psi
import os
import time

// Buffer is one open document: the path the client named, and the parse of the
// text it sent.
pub struct Buffer {
pub:
	path string
pub mut:
	file &psi.PsiFile = unsafe { nil }
}

// Session owns the index and the buffers. It is not safe to share between
// threads: the index it publishes is one global the whole process reads.
pub struct Session {
pub mut:
	manager &IndexingManager = unsafe { nil }
	// roots holds the directories that were indexed, in the order they were
	// added, which is what decides whether a buffer can be placed in the index
	// at all.
	roots []string
	// buffers is keyed by path. The values are pointers because every buffer
	// outlives the call that opened it.
	buffers map[string]&Buffer
	// indexed is false until a root has been indexed.
	indexed bool
	// cache_dir is where a root's index would be cached if this build saved one.
	// It does not, so the value is only ever handed back to the indexer; it is
	// remembered here so a later root, like a standard library module a buffer
	// imports, does not need the caller to name it again.
	cache_dir string
	// index_ms is how long indexing the roots took. A server that spends four
	// seconds of a handshake here owes the person a log line, and a test that
	// changed that owes a number.
	index_ms i64
}

// new_session returns a session with no roots and no index.
pub fn new_session() &Session {
	return &Session{
		manager: IndexingManager.new()
		buffers: map[string]&Buffer{}
	}
}

// index_root indexes one workspace folder and publishes the index. Adding a
// root that is already there does nothing, because indexing a folder twice is
// the same answer for twice the time.
//
// The index is not saved to disk: this build has no working cache path, since
// the serializer behind it dies, so every session pays for its own index. A
// workspace of a few hundred files costs a few hundred milliseconds, which is
// affordable inside a handshake; a whole vlib costs seconds, which is why the
// server indexes the folders it was given and nothing else.
pub fn (mut s Session) index_root(root string, cache_dir string) {
	s.index_roots([root], .workspace, cache_dir)
}

// index_roots indexes several folders as one job. A root that is already there is
// skipped, so calling it again with the same list costs nothing.
//
// The indexing runs once for the whole list rather than once per folder: every
// pass walks the roots that are already known, and paying that walk per module
// is what turns a few hundred milliseconds into a few seconds.
pub fn (mut s Session) index_roots(paths []string, kind index.IndexingRootKind, cache_dir string) []string {
	if cache_dir != '' {
		s.cache_dir = cache_dir
	}
	// The index belongs to this process for as long as it runs, and the
	// serializer behind the cache dies, so nothing is written where a later run
	// would read it as the truth.
	s.manager.indexer.set_no_save(true)
	mut added := []string{cap: paths.len}
	for path in paths {
		if path in s.roots || !os.is_dir(path) {
			continue
		}
		s.manager.indexer.add_indexing_root(path, kind, cache_dir)
		s.roots << path
		added << path
	}
	if added.len == 0 {
		return added
	}
	started := time.ticks()
	s.manager.indexer.index(fn (_root index.IndexingRoot, _index int) {})
	s.manager.setup_stub_indexes()
	s.index_ms += time.ticks() - started
	s.indexed = true
	return added
}

// index_imported_modules reads the standard library modules a buffer imports
// into the index, so a call into `os` answers the way a call into the next file
// does.
//
// A vlib module is a directory, and only the modules a buffer names are read.
// The whole library measured about ten seconds for this machine, while the
// handful of modules one file imports cost a few hundred milliseconds between
// them, once per session: a root that is already indexed is skipped.
//
// `builtin` goes in first whether or not it was imported, because the signature
// of everything else is written in its types and a module indexed without it
// answers with the names of the types left out.
//
// The answer says nothing about whether the modules were found. A module the
// compiler keeps somewhere else, or a name in a file that does not exist, adds
// nothing and every call into it keeps inferring unknown.
pub fn (mut s Session) index_imported_modules(vlib_dir string, modules []string) []string {
	mut wanted := []string{cap: modules.len + 1}
	wanted << 'builtin'
	for module in modules {
		if module !in wanted {
			wanted << module
		}
	}
	mut paths := []string{cap: wanted.len}
	for module in wanted {
		paths << os.join_path(vlib_dir, ...module.split('.'))
	}
	added := s.index_roots(paths, .standard_library, s.cache_dir)
	if added.len > 0 {
		// A call that could not be resolved a moment ago is resolved now, and
		// the answer it was given is still in the caches.
		psi.forget_answers()
	}
	return added
}

// put_buffer makes the text a client sent the text this session answers from,
// opening the buffer if it is new and replacing its parse if it is not.
//
// An error means no indexed root contains the path. The buffer's parse is kept
// either way, so a caller can still walk it, but the index holds nothing about
// that file and every answer about a name in it would be a guess.
pub fn (mut s Session) put_buffer(path string, text string) !&Buffer {
	mut buffer := s.buffers[path] or { &Buffer{ path: path } }
	s.parse_into(mut buffer, text)
	s.buffers[path] = buffer
	// Every answer the engine worked out for the text that was here a moment
	// ago is now about a file that no longer exists in that shape.
	psi.forget_answers()
	if !s.owns(path) {
		return error('no indexed workspace folder contains ${path}')
	}
	s.manager.refresh_file(path, text)!
	return buffer
}

// close_buffer drops the parse and hands the file back to the index, which
// describes the text on disk again.
//
// A file that is not on disk at all keeps the stubs the buffer gave it. There
// is no text to put back, and the entry describes a file the person has never
// saved; the next index over the root is what removes it.
pub fn (mut s Session) close_buffer(path string) {
	if buffer := s.buffers[path] {
		buffer.file.free()
		s.buffers.delete(path)
	}
	psi.forget_answers()
	if !s.indexed {
		return
	}
	if text := os.read_file(path) {
		s.manager.refresh_file(path, text) or {}
	}
}

// parse_into replaces a buffer's parse with one over text. The tree belongs to
// the buffer from here on, and closing is what releases it.
fn (mut s Session) parse_into(mut buffer Buffer, text string) {
	if !isnil(buffer.file) {
		// the previous tree is replaced, so nothing reads a tree the buffer
		// has moved past.
		buffer.file.free()
	}
	mut p := parser.Parser.new()
	defer {
		p.free()
	}
	res := p.parse_code(text)
	buffer.file = psi.new_psi_file(buffer.path, res.tree, res.source_text)
}

// file returns the parse of an open buffer, or none when the path is not open.
pub fn (s &Session) file(path string) ?&psi.PsiFile {
	buffer := s.buffers[path] or { return none }
	return buffer.file
}

// owns reports whether an indexed root contains the path.
pub fn (s &Session) owns(path string) bool {
	for i in 0 .. s.manager.indexer.roots.len {
		if s.manager.indexer.roots[i].contains(path) {
			return true
		}
	}
	return false
}

// is_indexed reports whether any root has been indexed.
pub fn (s &Session) is_indexed() bool {
	return s.indexed
}

// indexed_roots lists the directories that were indexed.
pub fn (s &Session) indexed_roots() []string {
	return s.roots
}
