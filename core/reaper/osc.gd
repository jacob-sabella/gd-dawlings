class_name OSC
extends RefCounted

## Open Sound Control 1.0 encode/decode.
##
## Godot ships no OSC, and the two things this project needs from it are small: build a message
## to push a fader, and take apart the ~30Hz flood Reaper sends back. So it lives here, with no
## dependency, rather than as a plugin.
##
## Everything is BIG-endian and padded to 4 bytes. The padding is the part that bites: a string
## is null-terminated AND THEN padded, so a 4-character address like "/vu/" occupies 8 bytes, not
## 5. Reaper is strict about it and simply drops a malformed packet, which looks exactly like a
## wrong port.

const PAD := 4


static func _pad_len(n: int) -> int:
	return (PAD - (n % PAD)) % PAD


static func _put_osc_string(buf: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer()
	buf.put_data(bytes)
	# One null is mandatory even when the length already lands on a boundary, hence the +1
	# before rounding up.
	buf.put_u8(0)
	for _i in range(_pad_len(bytes.size() + 1)):
		buf.put_u8(0)


static func _get_osc_string(buf: StreamPeerBuffer) -> String:
	var start := buf.get_position()
	var size := buf.get_size()
	var end := start
	var data := buf.data_array
	while end < size and data[end] != 0:
		end += 1
	var s := data.slice(start, end).get_string_from_utf8()
	# Step over the terminator, then over the padding that follows it.
	var consumed := (end - start) + 1
	buf.seek(start + consumed + _pad_len(consumed))
	return s


## Encode one message. Argument types are inferred from the Variant, which is what callers
## actually want: `OSC.message("/track/1/volume", [0.78])`.
##
## Reaper reads booleans as floats on its `b/` and `t/` patterns, so a bool is deliberately sent
## as 0.0/1.0 rather than as OSC's typed True/False -- the typed form is legal OSC that Reaper
## ignores, which is a uniquely annoying bug to chase.
static func message(address: String, args: Array = []) -> PackedByteArray:
	var tags := ","
	for a in args:
		match typeof(a):
			TYPE_INT: tags += "i"
			TYPE_FLOAT: tags += "f"
			TYPE_BOOL: tags += "f"
			TYPE_STRING, TYPE_STRING_NAME: tags += "s"
			TYPE_PACKED_BYTE_ARRAY: tags += "b"
			_:
				push_error("OSC: unsupported argument type %d in %s" % [typeof(a), address])
				return PackedByteArray()

	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	_put_osc_string(buf, address)
	_put_osc_string(buf, tags)
	for a in args:
		match typeof(a):
			TYPE_INT: buf.put_32(a)
			TYPE_FLOAT: buf.put_float(a)
			TYPE_BOOL: buf.put_float(1.0 if a else 0.0)
			TYPE_STRING, TYPE_STRING_NAME: _put_osc_string(buf, a)
			TYPE_PACKED_BYTE_ARRAY:
				var blob: PackedByteArray = a
				buf.put_32(blob.size())
				buf.put_data(blob)
				for _i in range(_pad_len(blob.size())):
					buf.put_u8(0)
	return buf.data_array


## Decode a packet into an Array of {address: String, args: Array}.
##
## Returns a LIST because a packet may be a bundle: Reaper coalesces a bank of meter updates into
## one, so a caller that assumed one-message-per-packet would see the first channel move and the
## rest sit still.
static func decode(packet: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if packet.size() < 4:
		return out
	var buf := StreamPeerBuffer.new()
	buf.big_endian = true
	buf.data_array = packet
	_decode_into(buf, packet.size(), out)
	return out


static func _decode_into(buf: StreamPeerBuffer, limit: int, out: Array[Dictionary]) -> void:
	if buf.get_position() >= limit:
		return
	var head := _get_osc_string(buf)
	if head == "#bundle":
		# 8-byte NTP timetag. Reaper sends "immediately" (1); nothing here schedules, so it is
		# read only to advance past it.
		buf.get_64()
		while buf.get_position() + 4 <= limit:
			var size := buf.get_32()
			if size <= 0 or buf.get_position() + size > limit:
				return
			var sub_limit := buf.get_position() + size
			_decode_into(buf, sub_limit, out)
			buf.seek(sub_limit)
		return

	if buf.get_position() >= limit:
		out.append({"address": head, "args": []})
		return

	var tags := _get_osc_string(buf)
	var args: Array = []
	for i in range(1, tags.length()):
		match tags[i]:
			"i": args.append(buf.get_32())
			"f": args.append(buf.get_float())
			"d": args.append(buf.get_double())
			"h": args.append(buf.get_64())
			"s", "S": args.append(_get_osc_string(buf))
			"b":
				var n := buf.get_32()
				args.append(buf.get_data(n)[1])
				buf.seek(buf.get_position() + _pad_len(n))
			"T": args.append(true)
			"F": args.append(false)
			"N": args.append(null)
			"I": args.append(INF)
			_:
				# An unknown tag means the rest of the payload can no longer be located, so the
				# message is surrendered rather than guessed at.
				break
	out.append({"address": head, "args": args})
