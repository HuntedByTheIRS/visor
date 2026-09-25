module main

import os

const version = '0.0.1'

const usage_text = 'visor ${version}
A language server for V.

usage:
  visor --version   print the version and exit
  visor --help      print this text and exit

The stdio protocol loop arrives with the lsp module. Until then the binary
answers these two flags and nothing else.'

fn main() {
	if os.args.len < 2 {
		println(usage_text)
		return
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
			exit(2)
		}
	}
}
