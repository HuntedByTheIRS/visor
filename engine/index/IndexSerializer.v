// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module index

import engine.psi

pub struct IndexSerializer {
mut:
	s Serializer
}

pub fn (mut s IndexSerializer) serialize_index(value Index) {
	s.s.write_string(value.version)
	s.s.write_i64(value.updated_at.unix())
	s.serialize_file_indexes(value.per_file.data)
}

pub fn (mut s IndexSerializer) serialize_file_indexes(indexes map[string]FileIndex) {
	s.s.write_int(indexes.len)
	for _, file_index in indexes {
		s.serialize_file_index(file_index)
	}
}

pub fn (mut s IndexSerializer) serialize_file_index(value FileIndex) {
	s.s.write_u8(u8(value.kind))
	s.s.write_i64(value.file_last_modified)

	s.serialize_stub_list(value.stub_list)
	s.serialize_stub_index_sink(value.sink)
}

pub fn (mut s IndexSerializer) serialize_stub_index_sink(sink &psi.StubIndexSink) {
	s.s.write_int(sink.data.len)
	for key, datum in sink.data {
		s.s.write_int(key)
		s.serialize_stub_index_sink_map(datum)
	}

	s.s.write_int(sink.imported_modules.len)
	for module_ in sink.imported_modules {
		s.s.write_string(module_)
	}
}

pub fn (mut s IndexSerializer) serialize_stub_index_sink_map(sink_map map[string][]psi.StubId) {
	s.s.write_int(sink_map.len)
	for key, stub_ids in sink_map {
		s.s.write_string(key)
		s.s.write_int(stub_ids.len)
		for id in stub_ids {
			s.s.write_int(id)
		}
	}
}

pub fn (mut s IndexSerializer) serialize_stub_list(list psi.StubList) {
	s.s.write_string(list.path)
	s.s.write_string(list.module_fqn)
	s.s.write_int(list.child_map.len)
	for id, children in list.child_map {
		s.s.write_int(id)
		s.s.write_int(children.len)
		for child in children {
			s.s.write_int(child)
		}
	}

	// serialize stubs as array
	s.s.write_int(list.index_map.len)
	for stub in list.index_map.values() {
		s.serialize_stub(stub)
	}
}

pub fn (mut s IndexSerializer) serialize_stub(stub psi.StubBase) {
	s.s.write_string(stub.text)
	s.s.write_string(stub.comment)
	s.s.write_string(stub.receiver)
	s.s.write_string(stub.additional)
	s.s.write_string(stub.name)

	s.s.write_int(stub.identifier_text_range.line)
	s.s.write_int(stub.identifier_text_range.column)
	s.s.write_int(stub.identifier_text_range.end_line)
	s.s.write_int(stub.identifier_text_range.end_column)

	s.s.write_int(stub.text_range.line)
	s.s.write_int(stub.text_range.column)
	s.s.write_int(stub.text_range.end_line)
	s.s.write_int(stub.text_range.end_column)

	s.s.write_int(stub.parent_id)
	s.s.write_u8(u8(stub.stub_type))
	s.s.write_int(stub.id)
}
