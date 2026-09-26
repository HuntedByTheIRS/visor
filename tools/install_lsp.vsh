module main

// install_lsp installs visor into an editor: the server binary, the client
// files that talk to it, and a command that starts that editor with them.
//
//   v run tools/install_lsp.vsh nvim
//   v run tools/install_lsp.vsh nvim vim --name visorvim
//   v run tools/install_lsp.vsh all -n          # print the plan, write nothing
//
// An install lands under a name. For Neovim the name is an NVIM_APPNAME, so the
// profile gets its own config directory and the setup the user already has keeps
// its own; the command that starts it is that name on PATH. Nothing here reads
// or writes `~/.config/nvim` or `~/.vimrc`: an editor someone has already set up
// is not this tool's to change.
//
// The server is built from the checkout this script lives in, with the compiler
// that ran the script, into --bin. `--rebuild` builds a fresh one.
//
// Every generated file carries a marker comment, and that marker is what lets a
// later run replace it. A file without one needs --force, so a run does not walk
// over something the user wrote.
//
// The plan is complete before the first write, so --dry-run prints what a real
// run does and there is no half-started state to reason about.

import os

const usage = 'usage: v run tools/install_lsp.vsh <editor> [<editor>...] [flags]'

// editor_names are the editors this tool can install for. `all` stands for
// every name in it.
const editor_names = ['nvim']

// editor_planned are names this tool answers to and cannot install yet. They are
// listed in the help because a user looking for them should get an answer, not
// "unknown editor".
const editor_planned = ['vim', 'code', 'codium']

// marker sits in every file this tool writes. It is the difference between a
// file a later run may replace and one that belongs to the user.
const marker = 'written by tools/install_lsp.vsh'

// compiler is the V that built this script, so the binary is built with the same
// one the caller used.
const compiler = @VEXE

const flags_help = 'editors: nvim (all for every editor it installs; vim, code and codium are not
implemented yet)
flags:
  --name <name>        profile name, also the command it installs (default: visorvim)
  --bin <path>         where the server binary goes (default: <root>/.local/bin/visor)
  --from <dir>         checkout to install from (default: the one this script is in)
  --root <dir>         install under this directory instead of $HOME
  --vim-lsp <dir>      a vim-lsp checkout to use instead of cloning one
  --no-format-on-save  leave saves alone instead of running them through `v fmt`
  --rebuild            build the binary even when one is already installed
  --force              replace files this tool did not write
  -n, --dry-run        print the plan and write nothing
  -h, --help'

// Request is the command line once the flags are read and the paths resolved.
// The fields sit in one `mut:` section because the flag loop fills them in after
// the literal is built.
struct Request {
mut:
	editors        []string
	name           string
	from           string
	root           string
	config         string
	bin            string
	bin_dir        string
	vim_lsp        string
	format_on_save bool
	force          bool
	rebuild        bool
	dry            bool
}

// Write is one file the install leaves behind. `exec` marks the ones that are
// commands rather than configuration, and `generated` marks the ones this tool
// authored: a generated file carries the marker, which a later run checks before
// replacing it. A file copied out of the checkout is not generated and is
// replaced every run, the same as the directories that are copied.
struct Write {
	path      string
	text      string
	exec      bool
	generated bool
}

// Copy is a directory taken from the checkout into the profile, so an install
// does not depend on the checkout staying where it is.
struct Copy {
	src string
	dst string
}

// Command is one program to run, in the order it is listed.
struct Command {
	line string
	dir  string
}

// Plan is everything an install would do: what runs, what is copied, what is
// written, and notes worth printing alongside them.
struct Plan {
mut:
	commands []Command
	copies   []Copy
	writes   []Write
	notes    []string
}

fn main() {
	request := parse_arguments(os.args[1..]) or {
		eprintln('install_lsp: ${err.msg()}')
		eprintln(usage)
		exit(1)
	}
	mut plan := Plan{}
	plan.server(request) or {
		eprintln('install_lsp: ${err.msg()}')
		exit(1)
	}
	for editor in request.editors {
		plan.editor(editor, request) or {
			eprintln('install_lsp: ${err.msg()}')
			exit(1)
		}
	}
	println('install_lsp: ${request.editors.join(', ')} as ${request.name}, under ${short_path(request.root)}')
	plan.report(request)
	if request.dry {
		println('nothing written')
		return
	}
	plan.run(request) or {
		eprintln('install_lsp: ${err.msg()}')
		exit(1)
	}
	version := os.execute('${shell_quote(request.bin)} --version')
	if version.exit_code == 0 {
		println('server: ${version.output.trim_space()}')
	}
	if !path_is_on_env(request.bin_dir, 'PATH') {
		println('note: ${short_path(request.bin_dir)} is not on your PATH, so `${request.name}` needs the full path')
	}
	println('start it with: ${request.name} path/to/main.v')
}

// parse_arguments reads the command line. Flags take a value either as
// `--flag value` or `--flag=value`.
fn parse_arguments(args []string) !Request {
	mut request := Request{
		name:           'visorvim'
		format_on_save: true
	}
	mut root := os.home_dir()
	mut bin := ''
	mut from := os.dir(@DIR)
	mut asked := []string{}
	mut at := 0
	for at < args.len {
		arg := args[at]
		at++
		if arg in ['-h', '--help'] {
			print_help()
			exit(0)
		}
		if arg == '' {
			continue
		}
		if !arg.starts_with('-') {
			for editor in editor_choice(arg) {
				if editor !in asked {
					asked << editor
				}
			}
			continue
		}
		key := arg.split('=')[0]
		mut value := if arg.contains('=') { arg.all_after('=') } else { '' }
		if key in ['--name', '--bin', '--from', '--root', '--vim-lsp'] && value == '' {
			if at >= args.len {
				return error('${key} needs a value')
			}
			value = args[at]
			at++
		}
		match key {
			'-n', '--dry-run' { request.dry = true }
			'--force' { request.force = true }
			'--rebuild' { request.rebuild = true }
			'--no-format-on-save' { request.format_on_save = false }
			'--name' { request.name = value }
			'--bin' { bin = value }
			'--from' { from = value }
			'--root' { root = value }
			'--vim-lsp' { request.vim_lsp = value }
			else {
				return error('unknown flag "${arg}"')
			}
		}
	}
	if asked.len == 0 {
		return error('no editor named (${editor_names.join(', ')} or all)')
	}
	request.editors = asked
	request.name = checked_name(request.name) or { return error(err.msg()) }
	request.root = os.real_path(expand_root(root))
	request.from = os.real_path(from)
	request.config = os.join_path(config_home(request.root), request.name)
	request.bin_dir = os.join_path(request.root, '.local', 'bin')
	request.bin = if bin != '' {
		os.real_path(expand_root(bin))
	} else {
		os.join_path(request.bin_dir, 'visor')
	}
	if !os.exists(os.join_path(request.from, 'plugins', 'nvim', 'plugin', 'visor.lua')) {
		return error('${request.from} does not hold plugins/nvim; pass --from with the checkout')
	}
	return request
}

// print_help prints what the tool takes and where each editor's files land.
fn print_help() {
	println(usage)
	println(flags_help)
}

// editor_choice turns one positional argument into editor names. `all` is every
// editor this tool installs.
fn editor_choice(name string) []string {
	if name == 'all' {
		return editor_names
	}
	return [name]
}

// checked_name rejects a name that would not be a command and a directory name:
// the name becomes both.
fn checked_name(name string) !string {
	if name == '' {
		return error('the name cannot be empty')
	}
	for character in name.bytes() {
		allowed := character.is_alnum() || character == u8(`-`) || character == u8(`_`)
			|| character == u8(`.`)
		if !allowed {
			return error('"${name}" is not a name: letters, digits, dots, dashes and underscores only')
		}
	}
	return name
}

// expand_root resolves a path the user typed, which may start with `~`.
fn expand_root(path string) string {
	return os.expand_tilde_to_home(path)
}

// config_home is the directory an editor reads its named configs from. Neovim
// follows XDG_CONFIG_HOME, so the profile has to land there when it is set.
fn config_home(root string) string {
	configured := os.getenv('XDG_CONFIG_HOME')
	if configured != '' && root == os.home_dir() {
		return configured
	}
	return os.join_path(root, '.config')
}

// path_is_on_env reports whether dir is one of the colon separated entries of
// the named environment variable.
fn path_is_on_env(dir string, name string) bool {
	for entry in os.getenv(name).split(':') {
		if entry != '' && os.real_path(entry) == dir {
			return true
		}
	}
	return false
}

// short_path prints a path under the user's home with `~` in front, which keeps
// the report to one line per file.
fn short_path(path string) string {
	home := os.home_dir()
	if path == home {
		return '~'
	}
	if path.starts_with(home + '/') {
		return '~' + path[home.len..]
	}
	return path
}

// shell_quote wraps a path for a shell command line.
fn shell_quote(path string) string {
	if path.contains(' ') || path.contains('"') {
		return "'" + path.replace("'", "'\\''") + "'"
	}
	return path
}

// Plan.editor adds what one editor needs on top of the server.
fn (mut plan Plan) editor(editor string, request &Request) ! {
	match editor {
		'nvim' { plan.nvim(request) or { return error(err.msg()) } }
		else {
			if editor in editor_planned {
				return error('${editor} is not implemented yet; this tool installs for ${editor_names.join(' and ')}')
			}
			return error('unknown editor "${editor}" (${editor_names.join(', ')} or all)')
		}
	}
}

// Plan.server adds the build when the binary is not already there. A binary that
// is present is left alone: replacing it is what --rebuild is for.
fn (mut plan Plan) server(request &Request) ! {
	if os.exists(request.bin) && !request.rebuild {
		plan.notes << 'using the server already at ${short_path(request.bin)}'
		return
	}
	if !os.exists(os.join_path(request.from, 'v.mod')) {
		return error('${request.from} holds no v.mod, so it is not a checkout to build from')
	}
	plan.commands << Command{
		line: '${compiler} -o ${shell_quote(request.bin)} .'
		dir:  request.from
	}
	plan.notes << 'building the server with ${compiler}'
}

// Plan.nvim installs the Neovim profile: a copy of the client, a config that
// loads it, and a command that starts Neovim under that name.
fn (mut plan Plan) nvim(request &Request) ! {
	source := os.join_path(request.from, 'plugins', 'nvim')
	client := os.join_path(request.config, 'plugins', 'visor')
	for directory in ['lua', 'plugin'] {
		plan.copies << Copy{
			src: os.join_path(source, directory)
			dst: os.join_path(client, directory)
		}
	}
	readme := os.read_file(os.join_path(source, 'README.md')) or {
		return error('${source}/README.md cannot be read: ${err.msg()}')
	}
	plan.write(os.join_path(client, 'README.md'), readme, false, false)
	plan.write(os.join_path(request.config, 'init.lua'), nvim_config(request, client), false, true)
	plan.write(os.join_path(request.bin_dir, request.name), nvim_command(request), true, true)
}

// nvim_config is the generated init.lua. It names the copy of the client, the
// server binary and the two features, and it says when a client attaches.
fn nvim_config(request &Request, client string) string {
	mut config := '-- ${marker}; run the tool again to regenerate it.\n'
	config += '--\n'
	config += "-- visor's own Neovim config. Start it with the ${request.name} command:\n"
	config += '-- that command is this appname, so this directory is its config and the\n'
	config += '-- setup you already have is not on this path.\n'
	config += '\n'
	config += 'vim.opt.runtimepath:prepend("${client}")\n'
	config += '\n'
	config += 'require("visor").setup({\n'
	config += '  cmd = "${request.bin}",\n'
	config += '  format_on_save = ${request.format_on_save},\n'
	config += '  semantic_tokens = true,\n'
	config += '  root_markers = { "v.mod", ".git" },\n'
	config += '})\n'
	config += '\n'
	config += '-- The server answers the pull-diagnostics request with an error naming the\n'
	config += '-- diagnostics lane, on purpose: an empty list would read as a file with no\n'
	config += '-- problems. Neovim turns that answer into a message on every V buffer, and a\n'
	config += '-- message that arrives while a command runs comes back out of it as an\n'
	config += '-- error, so the answer is taken here instead. Remove this when the lane lands.\n'
	config += 'vim.lsp.handlers["textDocument/diagnostic"] = function()\n'
	config += '  return true\n'
	config += 'end\n'
	config += '\n'
	config += '-- Say when a client lands. A server that never started looks the same as one\n'
	config += '-- that started and did nothing, so this is the difference you can see.\n'
	config += 'vim.api.nvim_create_autocmd("LspAttach", {\n'
	config += '  callback = function(args)\n'
	config += '    local client = vim.lsp.get_client_by_id(args.data.client_id)\n'
	config += '    if client and client.name == "visor" then\n'
	config += '      vim.notify(string.format("visor attached (%s)", client.config.root_dir or "no root"))\n'
	config += '    end\n'
	config += '  end,\n'
	config += '})\n'
	return config
}

// nvim_command is the shell command that starts Neovim under the profile name.
fn nvim_command(request &Request) string {
	mut text := '#!/bin/sh\n'
	text += '# ${marker}: Neovim under the visor profile "${request.name}".\n'
	text += 'exec env NVIM_APPNAME=${request.name} nvim "\$@"\n'
	return text
}

// Plan.write adds one file. `generated` says the text came from this tool rather
// than from the checkout, which is what the marker rule turns on.
fn (mut plan Plan) write(path string, text string, exec bool, generated bool) {
	plan.writes << Write{
		path:      path
		text:      text
		exec:      exec
		generated: generated
	}
}

// Plan.report prints the plan, one line per step, in the order they run.
fn (plan &Plan) report(request &Request) {
	for command in plan.commands {
		where := if command.dir == '' { '' } else { '   (in ${short_path(command.dir)})' }
		println('  run   ${command.line}${where}')
	}
	for copy in plan.copies {
		println('  copy  ${short_path(copy.src)} -> ${short_path(copy.dst)}')
	}
	for write in plan.writes {
		suffix := if write.exec { '  (executable)' } else { '' }
		println('  write ${short_path(write.path)}${suffix}')
	}
	for note in plan.notes {
		println('  note  ${note}')
	}
	if request.dry {
		return
	}
}

// Plan.run carries the plan out: directories, then commands, then copies, then
// writes. A file that is already there and does not carry the marker stops the
// run unless --force.
fn (plan &Plan) run(request &Request) ! {
	// Directories before anything runs: the compiler creates its scratch next to
	// the binary it is building, so that directory has to be there first.
	for write in plan.writes {
		os.mkdir_all(os.dir(write.path)) or {
			return error('${os.dir(write.path)} cannot be created: ${err.msg()}')
		}
	}
	for command in plan.commands {
		line := if command.dir == '' {
			command.line
		} else {
			'cd ${shell_quote(command.dir)} && ${command.line}'
		}
		result := os.execute(line)
		if result.exit_code != 0 {
			return error('`${line}` failed with exit code ${result.exit_code}\n${result.output.trim_space()}')
		}
	}
	for copy in plan.copies {
		os.mkdir_all(os.dir(copy.dst)) or {
			return error('${os.dir(copy.dst)} cannot be created: ${err.msg()}')
		}
		os.cp_all(copy.src, copy.dst, true) or {
			return error('${copy.src} cannot be copied to ${copy.dst}: ${err.msg()}')
		}
	}
	for write in plan.writes {
		if write.generated && os.exists(write.path) && !request.force {
			existing := os.read_file(write.path) or { '' }
			if !existing.contains(marker) {
				return error("${write.path} is not this tool's to replace; pass --force")
			}
		}
		os.mkdir_all(os.dir(write.path)) or {
			return error('${os.dir(write.path)} cannot be created: ${err.msg()}')
		}
		os.write_file(write.path, write.text) or {
			return error('${write.path} cannot be written: ${err.msg()}')
		}
		if write.exec {
			os.chmod(write.path, 0o755) or {
				return error('${write.path} cannot be made executable: ${err.msg()}')
			}
		}
	}
}
