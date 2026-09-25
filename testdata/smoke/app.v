module main

// A tiny fixture for the protocol smoke test. Two modules and one file with a
// symbol a later lane can hover over. The symbol is `greeter.greeting`, and the
// identifier `known_symbol` exists so a test can ask about a name that is
// already in the buffer.
fn main() {
	println(greeter.greeting())
}
