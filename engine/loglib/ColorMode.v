// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module loglib

pub enum ColorMode {
	auto
	always
	never
}

fn get_color_mode_by_name(name string) ?ColorMode {
	return match name {
		'auto' { ColorMode.auto }
		'always' { ColorMode.always }
		'never' { ColorMode.never }
		else { none }
	}
}
