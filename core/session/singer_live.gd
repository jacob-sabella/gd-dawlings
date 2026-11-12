class_name SingerLive
extends RefCounted

## What the vocal booth's singer is doing right now, as the host sends it to guests: the voice's body (its
## telemetry as the engine reports it, VoiceTele), the head's outlines (RackEngine.frames), the syllable being sung
## the beat's step and where that syllable is on the lyric board (VocalPart.sung_span). The engine runs on the host alone, so without this a guest's head would stand still while the
## host's sings. Sent with the project state as the volatile entry `/singer/live` (unreliable, sent again every
## tick), it lands in `MixState.singer_live`. The outlines are hundredths of a centimetre in 16 bits.

const ADDRESS := "/singer/live"
## A guest that has heard nothing for this long shows the singer as still.
const STALE_MSEC := 1500


## The entry's arguments: `[false]` for a singer that is not running.
static func pack(running: bool, tele: PackedFloat32Array, frame: Dictionary, sung: String, step: int,
		span := PackedInt32Array()) -> Array:
	if not running:
		return [false]
	return [true, tele, encode_frame(frame), sung.left(40), step, span if span.size() == 3 else PackedInt32Array()]


## The state a guest keeps: {tele, frame, sung, step, span, at}; `{}` for a singer that stopped; `before` for anything else.
static func unpack(args: Array, before: Dictionary) -> Dictionary:
	if args.size() == 1 and args[0] == false:
		return {}
	if args.size() != 6 or not (args[0] is bool and args[1] is PackedFloat32Array and args[2] is PackedByteArray \
			and args[3] is String and args[4] is int and args[5] is PackedInt32Array):
		return before
	var span: PackedInt32Array = args[5]
	if span.size() != 3 and not span.is_empty():
		return before
	var tele: PackedFloat32Array = args[1]
	if tele.size() > 4096:
		return before
	var frame := decode_frame(args[2])
	return {"tele": tele, "frame": frame if not frame.is_empty() else before.get("frame", {}), "sung": args[3],
			"step": int(args[4]), "span": span, "at": Time.get_ticks_msec()}


## `state` as live: `{}` when it is empty or older than STALE_MSEC.
static func fresh(state: Dictionary) -> Dictionary:
	if state.is_empty() or Time.get_ticks_msec() - int(state.get("at", 0)) > STALE_MSEC:
		return {}
	return state


## The head's outlines (RackEngine.frames' shape) as bytes: the glottis, then each line's point count and points,
## little-endian 16-bit hundredths of a centimetre.
static func encode_frame(frame: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	if frame.is_empty():
		return out
	var words := PackedInt32Array()
	var g: Vector2 = frame.get("glottis", Vector2.ZERO)
	words.append(_q(g.x))
	words.append(_q(g.y))
	var lines: Dictionary = frame.get("lines", {})
	for name in VoiceTele.LINES:
		var pts: PackedVector2Array = lines.get(name, PackedVector2Array())
		words.append(mini(pts.size(), 64))
		for i in mini(pts.size(), 64):
			words.append(_q(pts[i].x))
			words.append(_q(pts[i].y))
	out.resize(words.size() * 2)
	for i in words.size():
		out.encode_s16(i * 2, words[i])
	return out


static func _q(cm: float) -> int:
	return clampi(roundi(cm * 100.0), -32768, 32767)


static func decode_frame(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 4 or bytes.size() % 2 != 0:
		return {}
	var n := bytes.size() / 2
	var w := PackedInt32Array()
	w.resize(n)
	for i in n:
		w[i] = bytes.decode_s16(i * 2)
	var g := Vector2(w[0] / 100.0, w[1] / 100.0)
	var at := 2
	var lines := {}
	for name in VoiceTele.LINES:
		if at >= n:
			return {}
		var k := w[at]
		at += 1
		if k < 0 or k > 64 or at + 2 * k > n:
			return {}
		var pts := PackedVector2Array()
		pts.resize(k)
		for i in k:
			pts[i] = Vector2(w[at + 2 * i] / 100.0, w[at + 2 * i + 1] / 100.0)
		at += 2 * k
		lines[name] = pts
	return {"glottis": g, "lines": lines}
