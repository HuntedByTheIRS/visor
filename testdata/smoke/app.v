module main

// A tiny fixture for the protocol smoke test. Two modules and one file with a
// symbol a later lane can hover over. The symbol is `greeter.greeting`, and the
// identifier `known_symbol` exists so a test can ask about a name that is
// already in the buffer.
//
// The struct, the function and the call below are what the inlay hint request
// answers for: a positional literal whose field names are not in the text, a
// call whose parameter names come from the declaration, and a `:=` the engine
// types.
//
// The two compile-time lines are what the token request and the hint request
// read there: `$env` is a keyword and `to_string` is the method a call on what a
// builtin produced goes through, and the `:=` on each one is a string.

struct Point {
	x int
	y int
}

@[inline]
fn scale(p Point, factor int) Point {
	return Point{p.x * factor, p.y * factor}
}

fn main() {
	base := Point{2, 3}
	scaled := scale(base, 4)
	home := $env('HOME')
	embedded := $embed_file('v.mod').to_string()
	println(greeter.greeting())
	println(scaled)
	println(base)
	println(home)
	println(embedded)
}
