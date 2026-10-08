class_name MidiTake
extends RefCounted

## A take of notes, stamped by SONG POSITION rather than by when they arrived.
##
## The whole of recording a guest rests on that one choice. A guest in another room hears the
## host's mix about 46ms late and plays along to what it hears; a note it plays is therefore 46ms
## late against the host's clock, and a take placed by arrival time would land every note a beat
## fraction behind. But the guest knows which song position was coming out of its speakers when
## each key went down -- the mix stream carries it, see MixFeed -- so each note is stamped with
## that, and the host puts the take where the guest heard it. Latency then does not matter to
## the recording at all; it only matters to how comfortable it is to play.
##
## Two halves: assembly on the guest (note on/off in, a finished take out, hanging notes
## closed at the end), and `clean_args` on the host, because a take is peer input and the host
## validates everything a peer sends before it reaches the DAW.
##
## Nothing here is MIDI-device-specific and nothing is audio-specific: the same stamps will place
## an audio take from a guest -- see docs/loop_backlog.md.

## The shortest note kept. A note-off stamped before its note-on (the clock corrected itself
## between the two) is still a note somebody played.
const MIN_NOTE := 0.005
## Peer input limits. An hour of take and ten thousand notes is past anything a person plays in
## one pass, and a bound on both is what keeps a confused peer from asking the host to allocate
## without limit.
const MAX_SECONDS := 3600.0
const MAX_NOTES := 10000
const MAX_NAME := 64
## Values per note on the wire and in an item: on, off, pitch, velocity, channel.
const NOTE_WIDTH := 5

var start := 0.0
## The furthest song position heard while the take was running: where it ends.
var reached := 0.0
## Closed notes, [on, off, pitch, velocity, channel], in the order they were released.
var notes: Array = []
## Held notes: "channel:pitch" -> [on, velocity, channel, pitch].
var _held: Dictionary = {}
## Sustain pedal down, per channel; notes released under it wait for the pedal.
var _pedal: Dictionary = {}
## Notes released while the pedal was down: "channel:pitch" -> [on, velocity, channel, pitch].
var _sustained: Dictionary = {}


func begin(at_seconds: float) -> void:
	start = at_seconds
	reached = at_seconds
	notes.clear()
	_held.clear()
	_sustained.clear()


## The take has heard this far. Takes the furthest, so a position that steps back a hair (a
## clock correcting itself) does not shorten it.
func reach(at_seconds: float) -> void:
	reached = maxf(reached, at_seconds)


func note_on(pitch: int, velocity: int, channel: int, at_seconds: float) -> void:
	var key := "%d:%d" % [channel, pitch]
	# The same key struck again before it was let go, or while the pedal holds it: the first
	# strike ends where the second begins, as on a piano.
	if _held.has(key):
		_close(_held[key], at_seconds)
	if _sustained.has(key):
		_close(_sustained[key], at_seconds)
		_sustained.erase(key)
	_held[key] = [at_seconds, clampi(velocity, 1, 127), clampi(channel, 0, 15), clampi(pitch, 0, 127)]
	reach(at_seconds)


func note_off(pitch: int, channel: int, at_seconds: float) -> void:
	var key := "%d:%d" % [channel, pitch]
	if not _held.has(key):
		return
	if _pedal.get(channel, false):
		_sustained[key] = _held[key]
	else:
		_close(_held[key], at_seconds)
	_held.erase(key)
	reach(at_seconds)


## CC64. Notes let go while it is down keep sounding until it comes up, and that is how long
## they were played.
func sustain(down: bool, channel: int, at_seconds: float) -> void:
	_pedal[channel] = down
	if down:
		return
	for key in _sustained.keys():
		if (_sustained[key][2] as int) == channel:
			_close(_sustained[key], at_seconds)
			_sustained.erase(key)


func is_empty() -> bool:
	return notes.is_empty() and _held.is_empty() and _sustained.is_empty()


func held_count() -> int:
	return _held.size()


## Everything still down is closed at `end`, and the take comes back in time order. A note held
## past the end of the take is a note that was still sounding when the recording stopped -- it
## is kept, cut at the end, rather than lost.
func finish(end_seconds: float = NAN) -> Dictionary:
	var end := reached if is_nan(end_seconds) else end_seconds
	for held in _held.values():
		_close(held, end)
	for held in _sustained.values():
		_close(held, end)
	_held.clear()
	_sustained.clear()
	var out: Array = []
	for n in notes:
		var on: float = clampf(n[0], start, end)
		var off: float = clampf(n[1], on, end)
		if off - on < MIN_NOTE:
			off = minf(on + MIN_NOTE, maxf(end, on + MIN_NOTE))
		out.append([on, off, n[2], n[3], n[4]])
	out.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[2] < b[2]))
	return {"start": start, "end": maxf(end, start + MIN_NOTE), "notes": out}


func _close(held: Array, at_seconds: float) -> void:
	var on: float = held[0]
	notes.append([on, maxf(at_seconds, on + MIN_NOTE), held[3], held[1], held[2]])


# --- the host's side ------------------------------------------------------------------------

## A take as it arrived from a peer, made safe: `[track, start, end, notes, name]` back, or []
## if it cannot be read as a take at all. Everything is clamped rather than refused where a
## clamp has an honest meaning -- a note past the end of the take ends at the end -- and refused
## where it does not.
static func clean_args(args: Array) -> Array:
	if args.size() < 4:
		return []
	if not _is_number(args[0]) or not _is_number(args[1]) or not _is_number(args[2]):
		return []
	var track := int(args[0])
	var t0 := float(args[1])
	var t1 := float(args[2])
	if track < 1 or not is_finite(t0) or not is_finite(t1) or t1 <= t0:
		return []
	t0 = maxf(t0, 0.0)
	t1 = minf(t1, t0 + MAX_SECONDS)
	if t1 <= t0:
		return []
	var raw = args[3]
	if not (raw is Array):
		return []
	var cleaned: Array = []
	for n in raw:
		if cleaned.size() >= MAX_NOTES:
			break
		if not (n is Array or n is PackedFloat32Array or n is PackedFloat64Array) or n.size() < 4:
			continue
		var ok := true
		for i in mini(n.size(), NOTE_WIDTH):
			ok = ok and _is_number(n[i]) and is_finite(float(n[i]))
		if not ok:
			continue
		var on := clampf(float(n[0]), t0, t1)
		var off := clampf(float(n[1]), on, t1)
		if off - on < MIN_NOTE:
			off = minf(on + MIN_NOTE, t1)
		if off <= on:
			continue
		cleaned.append([on, off, clampi(int(n[2]), 0, 127), clampi(int(n[3]), 1, 127),
				clampi(int(n[4]) if n.size() > 4 else 0, 0, 15)])
	var name := ""
	if args.size() > 4 and args[4] is String:
		name = clean_name(args[4])
	return [track, t0, t1, cleaned, name]


## A take's name, as something every backend can carry: printable, short, and without the
## characters the ReaScript bridge's flat argument list uses as punctuation.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		var code := c.unicode_at(0)
		if code < 32 or c in [",", "\"", "[", "]", "\\", "{", "}"]:
			continue
		out += c
	return out.substr(0, MAX_NAME).strip_edges()


static func _is_number(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## Notes relative to an item's start, flat, the way an item carries them:
## [on, off, pitch, velocity, channel] repeating, seconds from the item's left edge.
static func pack_relative(notes: Array, item_start: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(notes.size() * NOTE_WIDTH)
	var at := 0
	for n in notes:
		out[at] = float(n[0]) - item_start
		out[at + 1] = float(n[1]) - item_start
		out[at + 2] = float(n[2])
		out[at + 3] = float(n[3])
		out[at + 4] = float(n[4]) if n.size() > 4 else 0.0
		at += NOTE_WIDTH
	return out


## The other way: absolute [on, off, pitch, velocity, channel] rows from an item's payload.
static func unpack_relative(packed: PackedFloat32Array, item_start: float) -> Array:
	var out: Array = []
	var i := 0
	while i + NOTE_WIDTH - 1 < packed.size():
		out.append([item_start + packed[i], item_start + packed[i + 1], int(packed[i + 2]),
				int(packed[i + 3]), int(packed[i + 4])])
		i += NOTE_WIDTH
	return out
