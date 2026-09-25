module vtool

// ast returns the JSON that `v ast -p` prints for a file.
//
// Every position in that JSON is a byte offset into the file. There is no line
// and no column anywhere in it, so a byte offset cannot be turned into a place
// an editor can put a cursor without reading the file again. No feature may
// depend on this output; it is a fast path for building an outline, and the
// engine answers everything that needs a real position.
//
// The call is gated on the capability report. A V build without the ast
// subcommand would otherwise hand back an empty string, and an empty string
// reads as a file with nothing in it.
pub fn (c Compiler) ast(path string, report CapabilityReport) !string {
	status := report.status_of(.ast_outline)
	if status != .supported {
		return error('`v ast -p` is ${status.str()} on ${c.abs_path}: ${report.detail_of(.ast_outline)}')
	}
	r := exec(c.abs_path, ['ast', '-p', path], '', '', false)
	if r.spawn_err != '' {
		return error(r.spawn_err)
	}
	if r.exit_code != 0 {
		return error('`${c.abs_path} ast -p ${path}` exited ${r.exit_code}: ${first_line(r.stdout + '\n' + r.stderr)}')
	}
	if r.stdout.trim_space() == '' {
		return error('`${c.abs_path} ast -p ${path}` exited zero and wrote no JSON')
	}
	return r.stdout
}
