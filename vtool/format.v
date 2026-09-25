module vtool

// format returns the buffer as `v fmt -` writes it.
//
// Formatting goes through the compiler rather than through a formatter of
// visor's own. A second formatter would drift from `v fmt`, and a project whose
// format gate disagrees with its editor is worse off than one with no
// formatter at all.
//
// The streams stay apart here, unlike the check path: stdout is the formatted
// source and is returned untouched.
pub fn (c Compiler) format(buffer string) !string {
	r := exec(c.abs_path, ['fmt', '-'], buffer, '', false)
	if r.spawn_err != '' {
		return error(r.spawn_err)
	}
	if r.exit_code != 0 {
		// A buffer the formatter cannot parse leaves stdout empty and explains
		// itself on stderr, so that text is all there is to hand back. The path
		// in it belongs to the compiler's own scratch file, which is why this
		// is an error message and not a diagnostic.
		message := r.stderr.trim_space()
		if message == '' {
			return error('`v fmt -` exited ${r.exit_code} without saying why')
		}
		return error('`v fmt -` exited ${r.exit_code}: ${message}')
	}
	return r.stdout
}
