module index

// The ported index serializer was written against vlib's `bytes` module, which
// V 0.5.2 no longer ships. These two types replace it and keep the wire format
// the serializer was written for: an integer is eight bytes little-endian, a
// string is its length followed by its bytes.
//
// Reading past the end yields zeros instead of a panic, so a truncated cache
// file fails the version check rather than taking the process down.
pub struct Serializer {
pub mut:
	data []u8
}

@[inline]
pub fn (mut s Serializer) write_u8(value u8) {
	s.data << value
}

pub fn (mut s Serializer) write_i64(value i64) {
	unsigned := u64(value)
	s.data << u8(unsigned)
	s.data << u8(unsigned >> 8)
	s.data << u8(unsigned >> 16)
	s.data << u8(unsigned >> 24)
	s.data << u8(unsigned >> 32)
	s.data << u8(unsigned >> 40)
	s.data << u8(unsigned >> 48)
	s.data << u8(unsigned >> 56)
}

@[inline]
pub fn (mut s Serializer) write_int(value int) {
	s.write_i64(i64(value))
}

pub fn (mut s Serializer) write_string(value string) {
	s.write_int(value.len)
	s.data << value.bytes()
}

pub struct Deserializer {
mut:
	data []u8
	pos  int
}

pub fn new_deserializer(data []u8) Deserializer {
	return Deserializer{
		data: data
	}
}

pub fn (mut d Deserializer) read_u8() u8 {
	value := d.data[d.pos] or { return 0 }
	d.pos++
	return value
}

pub fn (mut d Deserializer) read_i64() i64 {
	mut unsigned := u64(0)
	for shift in 0 .. 8 {
		unsigned |= u64(d.data[d.pos + shift] or { 0 }) << (shift * 8)
	}
	d.pos += 8
	return i64(unsigned)
}

@[inline]
pub fn (mut d Deserializer) read_int() int {
	return int(d.read_i64())
}

pub fn (mut d Deserializer) read_string() string {
	length := d.read_int()
	if length <= 0 || d.pos + length > d.data.len {
		d.pos += length
		return ''
	}
	value := d.data[d.pos..d.pos + length].bytestr()
	d.pos += length
	return value
}
