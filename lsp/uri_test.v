module lsp

fn folder_of(uri string) WorkspaceFolder {
	return WorkspaceFolder{
		uri:  uri
		name: uri
	}
}

fn test_a_plain_file_uri_becomes_a_path() {
	assert path_from_uri('file:///tmp/proj/a.v') == '/tmp/proj/a.v'
	// a path with a space in it is escaped on the wire and a space on disk.
	assert path_from_uri('file:///tmp/my%20project/a.v') == '/tmp/my project/a.v'
	// the host is not part of the path.
	assert path_from_uri('file://localhost/tmp/a.v') == '/tmp/a.v'
}

fn test_escapes_are_resolved_as_bytes() {
	// two escapes are one rune, and the path is the bytes, not the runes.
	assert path_from_uri('file:///tmp/%C3%A9.v') == '/tmp/é.v'
	assert path_from_uri('file:///tmp/a%2Bb.v') == '/tmp/a+b.v'
}

fn test_a_percent_that_starts_no_escape_stays() {
	// a path holding a percent sign is a path. Dropping it would name a file
	// that does not exist.
	assert path_from_uri('file:///tmp/100%25.v') == '/tmp/100%.v'
	assert path_from_uri('file:///tmp/50%off.v') == '/tmp/50%off.v'
	assert path_from_uri('file:///tmp/a%2.v') == '/tmp/a%2.v'
}

fn test_a_query_and_a_fragment_are_not_part_of_the_path() {
	assert path_from_uri('file:///tmp/a.v?line=3') == '/tmp/a.v'
	assert path_from_uri('file:///tmp/a.v#L3') == '/tmp/a.v'
}

fn test_anything_that_is_not_a_file_uri_has_no_path() {
	assert path_from_uri('https://example.com/a.v') == ''
	assert path_from_uri('untitled:Untitled-1') == ''
	assert path_from_uri('') == ''
	assert path_from_uri('file://') == ''
	assert path_from_uri('file://host') == ''
}

fn test_the_root_is_the_folder_that_contains_the_file() {
	folders := [folder_of('file:///tmp/proj')]
	assert root_for_path('/tmp/proj/src/a.v', folders) == '/tmp/proj'
	// a sibling folder whose name starts the same way is not a parent.
	assert root_for_path('/tmp/proj-other/a.v', folders) == '/tmp/proj-other'
}

fn test_the_closest_containing_folder_wins() {
	folders := [folder_of('file:///tmp/proj'), folder_of('file:///tmp/proj/vendor/vmod')]
	assert root_for_path('/tmp/proj/src/a.v', folders) == '/tmp/proj'
	assert root_for_path('/tmp/proj/vendor/vmod/a.v', folders) == '/tmp/proj/vendor/vmod'
}

fn test_a_file_outside_every_folder_is_checked_from_its_own_directory() {
	assert root_for_path('/tmp/loose/a.v', [folder_of('file:///tmp/proj')]) == '/tmp/loose'
	assert root_for_path('/tmp/loose/a.v', []) == '/tmp/loose'
	// a root folder contains everything under it.
	assert root_for_path('/tmp/a.v', [folder_of('file:///')]) == '/'
}

fn test_a_path_that_is_empty_gets_no_root() {
	assert root_for_path('', [folder_of('file:///tmp/proj')]) == ''
}
