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

struct Point {
	x int
	y int
}

fn scale(p Point, factor int) Point {
	return Point{p.x * factor, p.y * factor}
}

fn main() {
	base := Point{2, 3}
	scaled := scale(base, 4)
	println(greeter.greeting())
	println(scaled)
	println(base)
}
