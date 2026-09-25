module vtool

import os

// real_v is the compiler this machine already has on PATH. Discovery tests run
// against it so that a passing test says the sources were searched in the right
// order, not that a stub was called.
fn real_v() string {
	return os.find_abs_path_of_executable('v') or { panic('the test environment has no `v` on PATH') }
}

fn test_visor_v_command_wins() {
	env := {
		env_command: real_v()
		env_vexe:    '/nonexistent/vexe'
		'PATH':      '/nonexistent/bin'
	}
	c := find_from_env(env) or { panic(err.msg()) }
	assert c.abs_path == real_v()
	assert c.origin == env_command
}

fn test_vexe_is_used_when_the_command_variable_is_empty() {
	env := {
		env_command: ''
		env_vexe:    real_v()
		'PATH':      '/nonexistent/bin'
	}
	c := find_from_env(env) or { panic(err.msg()) }
	assert c.abs_path == real_v()
	assert c.origin == env_vexe
}

fn test_path_is_the_last_source() {
	env := {
		env_command: ''
		env_vexe:    ''
		'PATH':      os.dir(real_v())
	}
	c := find_from_env(env) or { panic(err.msg()) }
	assert c.abs_path == real_v()
	assert c.origin == 'PATH'
}

fn test_path_entries_without_v_are_skipped() {
	env := {
		'PATH': '/nonexistent/one${os.path_delimiter}${os.dir(real_v())}'
	}
	c := find_from_env(env) or { panic(err.msg()) }
	assert c.abs_path == real_v()
}

fn test_a_configured_command_that_is_not_a_file_is_rejected() {
	env := {
		env_command: '/nonexistent/definitely-not-a-v'
	}
	find_from_env(env) or {
		assert err.msg().contains(env_command)
		assert err.msg().contains('not a file')
		return
	}
	assert false
}

fn test_a_configured_command_that_cannot_run_is_rejected() {
	// A source file in this module: it exists, and it carries no executable bit.
	not_a_program := os.join_path(@DIR, 'discovery.v')
	assert os.exists(not_a_program)
	env := {
		env_command: not_a_program
	}
	find_from_env(env) or {
		assert err.msg().contains(env_command)
		assert err.msg().contains('not executable')
		return
	}
	assert false
}

fn test_nothing_found_names_every_source() {
	env := {
		env_command: ''
		env_vexe:    ''
		'PATH':      '/nonexistent/bin'
	}
	find_from_env(env) or {
		assert err.msg().contains(env_command)
		assert err.msg().contains(env_vexe)
		assert err.msg().contains('PATH')
		return
	}
	assert false
}

fn test_find_returns_the_compiler_this_machine_has() {
	c := find() or { panic(err.msg()) }
	assert os.is_file(c.abs_path)
	assert os.is_executable(c.abs_path)
	assert os.is_abs_path(c.abs_path)
}
