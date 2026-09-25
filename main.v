module main

import lsp
import os

const version = '0.0.1'

const usage_text = 'visor ${version}
A language server for V.

usage:
  visor             speak the language server protocol on stdin and stdout
  visor --version   print the version and exit
  visor --help      print this text and exit'

fn main() {
	if os.args.len < 2 {
		// No arguments is the way an editor starts a language server, so this is
		// the normal path rather than a forgotten flag. The exit code comes from
		// the session: zero after a shutdown, one otherwise.
		exit(lsp.serve_stdio(version))
	}
	match os.args[1] {
		'--version', '-v', 'version' {
			println('visor ${version}')
		}
		'--help', '-h', 'help' {
			println(usage_text)
		}
		else {
			eprintln('visor: unknown argument "${os.args[1]}"')
			// an implementation defined code, kept at 2 as it has been.
			exit(2)
		}
	}
}
