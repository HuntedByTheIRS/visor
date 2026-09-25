module greeter

pub const default_name = 'visor'

// greeting is the symbol a feature lane hovers over: it is exported, it has a
// doc comment, and its call site is in the file next door.
pub fn greeting() string {
	return 'hello from ${default_name}'
}
