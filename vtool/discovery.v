module vtool

import os

// env_command is the escape hatch for a V built somewhere visor would not look.
pub const env_command = 'VISOR_V_COMMAND'

// env_vexe is what a V tool sets in the environment of the processes it starts,
// so visor inherits the exact compiler it was launched from when a person runs
// it out of a V checkout.
pub const env_vexe = 'VEXE'

// Compiler is a resolved V binary.
//
// Resolution is a step of its own, separate from every call below it, because
// the failures are not alike. A compiler that cannot be found leaves visor
// unable to answer anything and has to be shown to the user, while a compiler
// that lacks one flag only takes one feature down.
pub struct Compiler {
pub:
	// abs_path is absolute because a check runs with the work folder set to a
	// module root. A relative executable path would resolve against that folder
	// rather than the folder visor was started in.
	abs_path string
	// origin names the source that produced abs_path. A VEXE inherited from
	// another tool is then visible in the message a person reads, instead of
	// leaving them to wonder which binary is in play.
	origin string
}

// vlib_dir is the standard library that belongs to this compiler: the directory
// named `vlib` beside the executable.
//
// Nothing is guessed about it. A compiler installed without its library, or one
// whose directory is named something else, answers none here and every module
// lookup keeps the answer it had.
pub fn (c &Compiler) vlib_dir() ?string {
	dir := os.join_path(os.dir(c.abs_path), 'vlib')
	if os.is_dir(dir) {
		return dir
	}
	return none
}

// find resolves the compiler from the environment visor was started with.
pub fn find() !Compiler {
	mut env := map[string]string{}
	env[env_command] = os.getenv(env_command)
	env[env_vexe] = os.getenv(env_vexe)
	env['PATH'] = os.getenv('PATH')
	return find_from_env(env)
}

// find_from_env takes the environment as an argument so a test can drive each
// source on its own, without setting process-wide variables that would leak
// into whatever else runs in the same test binary.
pub fn find_from_env(env map[string]string) !Compiler {
	configured := env[env_command] or { '' }
	if configured != '' {
		return from_path(configured, env_command)
	}
	vexe := env[env_vexe] or { '' }
	if vexe != '' {
		return from_path(vexe, env_vexe)
	}
	found := search_path(env['PATH'] or { '' }) or {
		return error('no V compiler found: set ${env_command} to a V binary, or run visor from a V tool that sets ${env_vexe}, or put `v` on PATH')
	}
	return Compiler{
		abs_path: found
		origin:   'PATH'
	}
}

// from_path accepts one configured path. Both variables are documented as
// paths, so anything else, a command line with arguments included, is reported
// rather than guessed at.
fn from_path(candidate string, source string) !Compiler {
	if !os.is_file(candidate) {
		return error('${source}=${candidate} is not a file')
	}
	if !os.is_executable(candidate) {
		return error('${source}=${candidate} is not executable')
	}
	return Compiler{
		abs_path: os.abs_path(candidate)
		origin:   source
	}
}

// search_path looks for `v` in the directories listed in PATH, in order. The
// first hit wins, which is how a shell would resolve the same name.
fn search_path(path_env string) ?string {
	if path_env == '' {
		return none
	}
	for dir in path_env.split(os.path_delimiter) {
		// An empty PATH entry means the current directory on POSIX. Skipping it
		// is deliberate: a `v` dropped next to an open project should not
		// become the compiler.
		if dir == '' {
			continue
		}
		candidate := os.join_path(dir, 'v')
		if os.is_file(candidate) && os.is_executable(candidate) {
			return os.abs_path(candidate)
		}
	}
	return none
}
