class_name ItemVoices
extends RefCounted

## The built-in engine's voices for what the room's items record: a MIDI item's drum notes
## (channel 9, General MIDI's percussion) as drums, and its pitched items' notes (channel 10, the
## handbells) as bells, where the engine's instrument (DawKitTine) would play both as tines.
##
## A hit recorded off a shaker plays back as the shaker that was heard when it was played: every
## sound is Foley's own synthesis (`Foley.samples`), the one the item rings in the room, and the
## drum kit around them (kick, snare, cymbals, congas...) is made the same way. A note is a
## one-shot: it rings out whole whatever its length, as a struck drum or bell does, and only its
## start, its note and its velocity matter.
##
## Each note's take (which of Foley.TAKES it is) is seeded by its time, never by an order or a
## clock, so an item renders the same every time, on any machine, and a run of sixteenths is not
## one sample said again and again.
##
## Only the built-in engine plays through this. On Reaper the track's own instrument plays what it
## is given, as for any MIDI. GodotBackend.render_midi splits an item by channel and sums the two.

## The hand percussion's channel, 0-based (HitRecorder.CHANNEL), and the pitched items'
## (InstrumentItem.MELODIC_CHANNEL). Mirrored rather than referenced, because the engine knows
## nothing of core/items/; a suite check keeps them equal, as TourPart.ITEM_CHANNELS.
const DRUM_CHANNEL := 9
const PITCHED_CHANNEL := 10

## General MIDI's percussion notes, as [Foley's sound, how far it is pitched]. Where an item of
## the room records a note (ShakerItem 82, CowbellItem 56 and 68...), it is that item's sound at
## the pitch the item plays it (a second voice, InstrumentItem.VOICE_PITCH, a fifth's 0.8 lower),
## so a take sounds as it was heard. Any note not here is `Foley.click`.
const DRUMS := {
	35: [&"kick", 0.88], 36: [&"kick", 1.0],
	37: [&"rim", 1.0],
	38: [&"snare", 1.0], 40: [&"snare", 1.1],
	39: [&"clap", 1.0],
	# Hats: closed, pedal, and open as the hi-hat item's own second voice.
	42: [&"hihat", 1.0], 44: [&"hihat", 0.9], 46: [&"hihat", 0.8],
	# Toms, low floor to high: the drum pad's sound, 47 and 45 as PadItem plays them.
	41: [&"pad", 0.67], 43: [&"pad", 0.75], 45: [&"pad", 0.8], 47: [&"pad", 1.0],
	48: [&"pad", 1.12], 50: [&"pad", 1.26],
	# Cymbals: crash 1 and 2, china (a crash down), splash (a crash up); ride 1 and 2, its bell.
	49: [&"crash", 1.0], 57: [&"crash", 0.94], 52: [&"crash", 0.8], 55: [&"crash", 1.3],
	51: [&"ride", 1.0], 59: [&"ride", 0.95], 53: [&"ride", 1.15],
	# The tambourine, as the jingles shaken: TambourineItem records a shake and a strike alike as
	# 54, and a shake is how it is mostly played, so its take is the jingle the room heard.
	54: [&"jingle", 1.0],
	# Cowbell, and the agogos as the cowbell item's voices.
	56: [&"cowbell", 1.0], 67: [&"cowbell", 1.25], 68: [&"cowbell", 0.8],
	# The claves' second voice records as the vibraslap.
	58: [&"claves", 0.8], 75: [&"claves", 1.0],
	60: [&"bongo", 1.0], 61: [&"bongo", 0.8],
	# Congas: mute high, open high, low.
	62: [&"conga", 1.06], 63: [&"conga", 1.0], 64: [&"conga", 0.78],
	# Cabasa and maracas from the shaker, and the shaker's own note.
	69: [&"shaker", 0.85], 70: [&"shaker", 1.0], 82: [&"shaker", 1.0],
	76: [&"woodblock", 1.0], 77: [&"woodblock", 0.8],
	80: [&"triangle", 0.8], 81: [&"triangle", 1.0],
}

## Under the tine's loudest (DawKitTine's 0.27 a voice), as the room's items sit under the keys.
const LEVEL := 0.8


## The sound a drum note is, and how far it is pitched: [kind, ratio].
static func drum(note: int) -> Array:
	return DRUMS.get(note, [&"click", 1.0])


## Which of Foley.TAKES a note struck at `on` (seconds from the item's start) is: from its time
## to the millisecond, so the same note at the same place is the same take on every render.
static func take_at(on: float) -> int:
	return posmod(hash(int(round(on * 1000.0))), Foley.TAKES)


## A hit's gain by its velocity (1-127): the curve InstrumentItem.level_db plays a hit at live.
static func level(velocity: int) -> float:
	return LEVEL * db_to_linear(linear_to_db(clampf(velocity / 127.0, 0.05, 1.0)) * 1.2 - 3.0)


## Whether a note on `channel` is played here rather than by the tine.
static func plays(channel: int) -> bool:
	return channel == DRUM_CHANNEL or channel == PITCHED_CHANNEL


## `notes` (flat [on, off, pitch, velocity, channel], as DawKitTine.render_notes takes them) in
## two: [the tine's, these voices'].
static func split(notes: PackedFloat64Array) -> Array:
	var tine := PackedFloat64Array()
	var ours := PackedFloat64Array()
	for i in range(0, notes.size() - 4, 5):
		var note := notes.slice(i, i + 5)
		if plays(int(notes[i + 4])):
			ours.append_array(note)
		else:
			tine.append_array(note)
	return [tine, ours]


## As many silent stereo frames as DawKitTine.render_notes makes for `seconds`: the clip and the
## tail it rings out into.
static func silence(seconds: float, rate: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(int(ceil((seconds + DawKitTine.TAIL_SECONDS) * rate)))
	return out


## `notes`' drum and bell notes (others are skipped) rung into `out`, stereo at `rate`, each on
## its own sample. A note at or past `seconds` is not played, as the tine's is not; one rings for
## as long as `out` is, and no longer. Safe off the main thread.
static func add_to(out: PackedVector2Array, notes: PackedFloat64Array, seconds: float, rate: int) -> void:
	for i in range(0, notes.size() - 4, 5):
		var on := notes[i]
		var channel := int(notes[i + 4])
		if on >= seconds or not plays(channel):
			continue
		var note := int(notes[i + 2])
		var kind: StringName
		var ratio: float
		if channel == DRUM_CHANNEL:
			var d := drum(note)
			kind = d[0]
			ratio = d[1]
		else:
			# A bell rung at its note, from the C5 its sound rings (HandbellItem.sound_pitch).
			kind = &"handbell"
			ratio = pow(2.0, float(note - Foley.HANDBELL_NOTE) / 12.0)
		_ring(out, Foley.samples(kind, take_at(on)), int(round(maxf(on, 0.0) * rate)),
				ratio * float(Foley.RATE) / float(rate), level(int(notes[i + 3])))


## One sound added into `out` from frame `at`, read `step` of its own samples a frame (its pitch
## and its rate against the render's together), between samples by a straight line.
static func _ring(out: PackedVector2Array, s: PackedFloat32Array, at: int, step: float, gain: float) -> void:
	var last := s.size() - 1
	var frames := mini(out.size() - at, int(float(last) / step))
	for j in maxi(frames, 0):
		var from := float(j) * step
		var k := int(from)
		var v := lerpf(s[k], s[mini(k + 1, last)], from - float(k)) * gain
		out[at + j] += Vector2(v, v)
