module sample

pub struct Counter {
pub mut:
	value int
}

pub fn (mut c Counter) increment() int {
	c.value += 1
	return c.value
}

fn main() {
	mut c := Counter{}
	println(c.increment())
}
