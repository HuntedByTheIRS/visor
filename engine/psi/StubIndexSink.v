// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

@[heap]
pub struct StubIndexSink {
pub mut:
	stub_id          StubId
	stub_list        &StubList = unsafe { nil } // List of stubs in the current file for which the index is being built.
	imported_modules []string
	kind             StubIndexLocationKind
	data             map[int]map[string][]StubId
}

// non_fqn_keys lists the keys whose values are not module qualified, so the
// occurrence below stores them as they are.
const non_fqn_keys = [StubIndexKey.global_variables, .methods_fingerprint, .fields_fingerprint,
	.interface_methods_fingerprint, .interface_fields_fingerprint, .methods, .static_methods,
	.attributes, .modules_fingerprint]!

fn (mut s StubIndexSink) occurrence(key StubIndexKey, value string) {
	module_fqn := s.module_fqn()
	resulting_value := if module_fqn != '' && key !in non_fqn_keys {
		'${module_fqn}.${value}'
	} else {
		value
	}

	// V 0.5.2 drops `s.data[int(key)][resulting_value] << s.stub_id` when the
	// outer key is absent: the append lands in a temporary map and the sink
	// keeps no occurrence at all, which leaves every index built from it empty.
	// Reading the ids out and setting them back works whether or not the outer
	// key is already there, where a nested append does not.
	mut ids := s.data[int(key)][resulting_value] or { []StubId{} }
	ids << s.stub_id
	s.data[int(key)][resulting_value] = ids
}

// module_fqn returns the module the stub list belongs to, empty when the
// sink has no stub list.
@[inline]
pub fn (s StubIndexSink) module_fqn() string {
	if s.stub_list == unsafe { nil } {
		return ''
	}
	return s.stub_list.module_fqn
}
