// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.loglib

// sub_indexes_from_sink records the sink's module and file mappings without indexing its data.
pub fn (mut s StubIndex) sub_indexes_from_sink(sink StubIndexSink) {
	unsafe { s.module_to_files[sink.stub_list.module_fqn] << sink }
	s.file_to_module[sink.stub_list.path] = sink.stub_list.module_fqn
}

// update_index_from_sink adds the stubs of one sink to the index.
pub fn (mut s StubIndex) update_index_from_sink(sink StubIndexSink) {
	element_type := StubbedElementType{}
	s.sub_indexes_from_sink(sink)

	for index_id, datum in sink.data {
		kind := sink.kind

		mut mp := s.data[kind][index_id]
		for name, ids in datum {
			mut stubs_result := []&StubBase{cap: ids.len}
			mut psi_result := []PsiElement{cap: ids.len}
			mut top_level_elements_psi_result := []PsiElement{cap: ids.len}
			mut top_level_types_elements_psi_result := []PsiElement{cap: ids.len}

			for stub_id in ids {
				stub := sink.stub_list.index_map[stub_id] or { continue }
				stubs_result << stub
				element := element_type.create_psi(stub) or { continue }
				psi_result << element

				if stub.stub_type in [
					.function_declaration,
					.constant_declaration,
					.global_variable,
				] {
					top_level_elements_psi_result << element
				}

				if stub.stub_type in [
					.struct_declaration,
					.interface_declaration,
					.enum_declaration,
					.type_alias_declaration,
				] {
					top_level_types_elements_psi_result << element
				}
			}

			mut data_by_name := unsafe { mp[name] }
			data_by_name.stubs << stubs_result
			data_by_name.psis << psi_result
			mp[name] = data_by_name

			module_fqn := sink.module_fqn()
			// V treat different '' (different cap) as different keys
			module_key := if module_fqn == '' { '' } else { module_fqn }

			s.types_by_modules[kind][module_key] << top_level_types_elements_psi_result

			s.all_elements_by_modules[kind][module_key] << top_level_elements_psi_result
			s.all_elements_by_modules[kind][module_key] << top_level_types_elements_psi_result
		}
		s.data[kind][index_id] = mp.move()
	}
}

// update_stubs_index replaces the sinks and rebuilds the workspace index after workspace changes.
pub fn (mut s StubIndex) update_stubs_index(changed_sinks []StubIndexSink, all_sinks []StubIndexSink) {
	loglib.log_one(.info, 'Updating stubs index...')
	loglib.log_one(.info, 'Changed files: ${changed_sinks.len}')

	s.sinks = all_sinks

	mut is_workspace_changes := false
	for sink in changed_sinks {
		if sink.kind == .workspace {
			is_workspace_changes = true
			break
		}
	}

	if !is_workspace_changes {
		return
	}

	s.module_to_files = map[string][]StubIndexSink{}
	s.file_to_module = map[string]string{}

	// clear all workspace index
	s.data[StubIndexLocationKind.workspace] = [count_index_keys]map[string]StubResult{}
	for i in 0 .. count_index_keys {
		s.data[StubIndexLocationKind.workspace][i] = map[string]StubResult{}
	}

	s.all_elements_by_modules[StubIndexLocationKind.workspace] = map[string][]PsiElement{}
	s.types_by_modules[StubIndexLocationKind.workspace] = map[string][]PsiElement{}

	for sink in all_sinks {
		if sink.kind != .workspace {
			// for non workspace sinks we just update the module_to_files and file_to_module maps
			s.sub_indexes_from_sink(sink)
			continue
		}

		s.update_index_from_sink(sink)
	}
}
