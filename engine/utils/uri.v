module utils

// path_to_uri renders the file:// URI for a filesystem path.
//
// v-analyzer kept this in its lsp module. visor's engine does not port that
// module, so the two call sites (PsiFile.uri and the index log fields) get the
// function here instead. Only the POSIX rules are kept, since the engine runs
// wherever the V compiler runs.
pub fn path_to_uri(path string) string {
	scheme := 'file://'
	fixed_path := if path.starts_with(scheme) { path.all_after(scheme) } else { path }
	with_root := if fixed_path.starts_with('/') { fixed_path } else { '/' + fixed_path }
	return scheme + escape_uri(with_root)
}

fn escape_uri(s string) string {
	return s.bytes().map(if it.is_alnum() || it in [`-`, `.`, `_`, `~`, `/`] {
		rune(it).str()
	} else {
		'%${it:02X}'
	}).join('')
}
