// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import os

// get_all_elements_from returns a list of all PSI elements defined in the given index.
//
// Example:
// ```
// // gets all the elements defined in the current project
// stubs_index.get_all_elements_from(.workspace)
// ```
pub fn (s &StubIndex) get_all_elements_from(kind StubIndexLocationKind) []PsiElement {
	data := s.data[kind]

	mut all_len := 0
	$for field in StubIndexKey.values {
		res := data[field.value]
		for _, stubs in res {
			all_len += stubs.psis.len
		}
	}
	mut elements := []PsiElement{cap: all_len}

	$for key in StubIndexKey.values {
		res := data[key.value]
		for _, stubs in res {
			for psi in stubs.psis {
				elements << psi
			}
		}
	}
	return elements
}

// get_all_elements_from_by_key returns a list of all PSI elements defined in the given index for the given key.
//
// Example:
// ```
// // gets all the functions defined in the current project
// stubs_index.get_all_elements_from_by_key(.workspace, .functions)
// ```
pub fn (s &StubIndex) get_all_elements_from_by_key(from StubIndexLocationKind, key StubIndexKey) []PsiElement {
	data := s.data[from]
	mp := data[key]

	mut elements := []PsiElement{cap: mp.len}
	for _, res in mp {
		elements << res.psis
	}
	return elements
}

// get_all_elements_from_file returns the elements the index holds for the given file.
pub fn (s &StubIndex) get_all_elements_from_file(file string) []PsiElement {
	mut elements := []PsiElement{cap: 20}
	for sink in s.sinks {
		if sink.stub_list.path != file {
			continue
		}

		$for key in StubIndexKey.values {
			if key.value !in [.attributes, .fields_fingerprint, .methods_fingerprint] {
				elements << s.get_all_elements_from_sink_by_key(key.value, sink)
			}
		}
	}
	return elements
}

// get_all_declarations_from_module returns a list of all PSI elements defined in the given module.
pub fn (s &StubIndex) get_all_declarations_from_module(module_fqn string, only_types bool) []PsiElement {
	if only_types {
		if elements := s.types_by_modules[StubIndexLocationKind.workspace][module_fqn] {
			return elements
		}

		$for value in StubIndexLocationKind.values {
			if value.value != StubIndexLocationKind.workspace {
				if elements := s.types_by_modules[value.value][module_fqn] {
					return elements
				}
			}
		}
	}

	// first try to get the elements from the workspace, if not found, try to get them from the other locations
	if elements := s.all_elements_by_modules[StubIndexLocationKind.workspace][module_fqn] {
		return elements
	}

	$for value in StubIndexLocationKind.values {
		if value.value != StubIndexLocationKind.workspace {
			if elements := s.all_elements_by_modules[value.value][module_fqn] {
				return elements
			}
		}
	}
	return []
}

// get_all_sinks_from_module returns every sink that belongs to the module.
pub fn (s &StubIndex) get_all_sinks_from_module(module_fqn string) []StubIndexSink {
	return s.module_to_files[module_fqn] or { return []StubIndexSink{} }
}

// get_all_sink_depends_on returns the workspace sinks that import the module.
pub fn (s &StubIndex) get_all_sink_depends_on(module_fqn string) []StubIndexSink {
	mut sinks := []StubIndexSink{cap: 10}
	for sink in s.sinks {
		if sink.kind != .workspace {
			continue
		}
		for imported in sink.imported_modules {
			if s.find_real_module_fqn(imported) == module_fqn {
				sinks << sink
				break
			}
		}
	}
	return sinks
}

// get_sink_for_file returns the sink indexed for the given file, if it is known.
pub fn (s &StubIndex) get_sink_for_file(file string) ?StubIndexSink {
	for sink in s.sinks {
		if sink.stub_list.path == file {
			return sink
		}
	}
	return none
}

// get_elements_by_name returns the definitions of the element with the given name from the given index.
pub fn (s &StubIndex) get_elements_by_name(key StubIndexKey, name string) []PsiElement {
	mut elements := []PsiElement{cap: 5}

	$for value in StubIndexLocationKind.values {
		data := s.data[value.value]
		res := data[key]
		if found := res[name] {
			elements << found.psis
		}
	}
	return elements
}

// get_elements_from_by_name returns the definitions stored under name in one index location.
pub fn (s &StubIndex) get_elements_from_by_name(from StubIndexLocationKind, key StubIndexKey, name string) []PsiElement {
	mut elements := []PsiElement{cap: 5}
	data := s.data[from]
	res := data[key]
	if found := res[name] {
		elements << found.psis
	}
	return elements
}

// get_any_elements_by_name returns the definitions of the element with the given name.
pub fn (s &StubIndex) get_any_elements_by_name(name string) []PsiElement {
	mut elements := []PsiElement{cap: 5}

	$for value in StubIndexLocationKind.values {
		data := s.data[value.value]
		$for key in StubIndexKey.values {
			if key.value !in [.methods, .attributes] {
				res := data[key.value]
				if found := res[name] {
					elements << found.psis
				}
			}
		}
	}
	return elements
}

// get_module_qualified_name returns the fully qualified name of the module in which the file is defined.
pub fn (s &StubIndex) get_module_qualified_name(file string) string {
	return s.file_to_module[file] or { '' }
}

// get_module_root returns the module's root directory.
pub fn (s &StubIndex) get_module_root(module_fqn string) string {
	files := s.module_to_files[module_fqn] or { return '' }
	first := files[0] or { return '' }
	return os.dir(first.stub_list.path)
}

// get_modules_by_name returns the modules matching the given name.
pub fn (s &StubIndex) get_modules_by_name(name string) []PsiElement {
	mut elements := []PsiElement{cap: 5}

	$for value in StubIndexLocationKind.values {
		data := s.data[value.value]
		res := data[int(StubIndexKey.modules_fingerprint)]
		if found := res[name] {
			elements << found.psis
		}
	}
	return elements
}

// get_all_modules returns all known modules.
pub fn get_all_modules() []string {
	return stubs_index.module_to_files.keys()
}

fn (_ &StubIndex) get_all_elements_from_sink_by_key(key StubIndexKey, sink StubIndexSink) []PsiElement {
	data := (sink.data[int(key)] or { return [] }).clone()

	element_type := StubbedElementType{}
	mut elements := []PsiElement{cap: data.len}
	for _, stub_ids in data {
		for stub_id in stub_ids {
			stub := sink.stub_list.index_map[stub_id] or { continue }
			elements << element_type.create_psi(stub) or { continue }
		}
	}

	return elements
}

// find_real_module_fqn resolves a module name to the full name it is known by.
pub fn (s &StubIndex) find_real_module_fqn(name string) string {
	workspace_idx := int(StubIndexLocationKind.workspace)
	workspace_modules := s.all_elements_by_modules[workspace_idx]

	if name in workspace_modules {
		return name
	}

	suffix := '.' + name
	for mod_fqn, _ in workspace_modules {
		if mod_fqn.ends_with(suffix) {
			return mod_fqn
		}
	}

	$for kind in StubIndexLocationKind.values {
		if kind.value != StubIndexLocationKind.workspace {
			modules := s.all_elements_by_modules[kind.value]
			if name in modules {
				return name
			}
		}
	}
	return name
}
