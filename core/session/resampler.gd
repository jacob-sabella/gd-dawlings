class_name Resampler
extends RefCounted

## Sound at whatever rate a sound card insists on, to the session wire's 48kHz. Linear, which
## is plenty for 44.1 -> 48 and back, and continuous across blocks: each call carries on from
## where the last one left off, so a stream read a block at a time has no seam between them.
##
## The project asks every driver for 48kHz, but a card can insist on 44.1kHz, and played or
## stored as 48kHz the sound would come out 9% sharp and fast.

## Where the last block's resampling left off, in input frames, and that block's last frame.
var _phase := 0.0
var _last := Vector2.ZERO


func resample(got: PackedVector2Array, from_rate: float, to_rate := 48000.0) -> PackedVector2Array:
	if is_equal_approx(from_rate, to_rate) or got.is_empty():
		return got
	var step := from_rate / to_rate
	var out := PackedVector2Array()
	# Positions run from -1 (the previous block's last frame) to the end of this one.
	while _phase < got.size() - 1:
		var i := floori(_phase)
		var a := _last if i < 0 else got[i]
		out.append(a.lerp(got[i + 1], _phase - i))
		_phase += step
	_phase -= got.size()
	_last = got[got.size() - 1]
	return out


func reset() -> void:
	_phase = 0.0
	_last = Vector2.ZERO
