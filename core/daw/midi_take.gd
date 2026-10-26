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
## The controllers a take carries beside its notes (Session.CONTROL_KINDS): the pitch wheel
## (DawKitClip.PITCH_BEND), the mod wheel (1) and expression (11).
const CONTROL_KINDS := [DawKitClip.PITCH_BEND, 1, 11]
## Peer input limit on a take's controls, as MAX_NOTES is on its notes. A wheel moved for an hour
## at 60 a second and thinned (`control`) is far under it.
const MAX_CONTROLS := 20000
## The thinning (`control`): a control is kept when it has moved at least this far since the last
## one kept of its kind, the bend's 32 of 16384 a sixty-fourth of a semitone and a CC's one step of
## 128 ...
const BEND_STEP := 32
const CC_STEP := 1
## ... and at least CONTROL_GAP has passed since then: a hand's tilt read at 90 Hz would otherwise
## keep every frame of a fast move, which nothing hears.
const CONTROL_GAP := 0.008
## A move not kept is kept anyway once nothing has followed it for this long, or a note lets go,
## or the take ends: so where a bend came to rest is exact, never a step short of it.
const CONTROL_HOLD := 0.05

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
## Controls kept (`control`), [at, kind, value, channel], in the order they were kept.
var controls: Array = []
## The last kept of each control, "channel:kind" -> [at, kind, value, channel].
var _kept: Dictionary = {}
## The latest move of each control not kept yet, "channel:kind" -> [at, kind, value, channel]:
## kept once it has stood CONTROL_HOLD, at a note-off, or at the end (`_settle`).
var _moved: Dictionary = {}


func begin(at_seconds: float) -> void:
	start = at_seconds
	reached = at_seconds
	notes.clear()
	_held.clear()
	_sustained.clear()
	controls.clear()
	_kept.clear()
	_moved.clear()


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
	# Where the wheel was as the note let go is what its release was heard at.
	_settle(INF)
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


## A control moved: `kind` one of CONTROL_KINDS, `value` -8192 to 8191 for the bend and 0 to 127
## otherwise (clamped), on `channel`, at song position `at_seconds`. Thinned as it is taken down:
## kept when it has moved BEND_STEP (the bend) or CC_STEP (a CC) since the last one of its kind
## kept AND CONTROL_GAP has passed since then; a move that is neither waits, and the latest one
## waiting is kept once it has stood CONTROL_HOLD, a note lets go or the take ends. A kept move
## lands no sooner than CONTROL_GAP after the one before it, so no two are closer. `keep`: kept
## whatever it moved (a wheel put back to rest at the player's last note-off). At most
## MAX_CONTROLS; past that, a move is dropped.
func control(kind: int, value: int, channel: int, at_seconds: float, keep := false) -> void:
	if not CONTROL_KINDS.has(kind) or not is_finite(at_seconds):
		return
	value = clampi(value, int(DawKitClip.BEND_MIN), int(DawKitClip.BEND_MAX)) if kind == DawKitClip.PITCH_BEND \
			else clampi(value, 0, 127)
	channel = clampi(channel, 0, 15)
	_settle(at_seconds - CONTROL_HOLD)
	reach(at_seconds)
	var key := "%d:%d" % [channel, kind]
	var row := [at_seconds, kind, value, channel]
	var last: Variant = _kept.get(key)
	if last == null or keep:
		_moved.erase(key)
		_keep(key, row)
		return
	var step := BEND_STEP if kind == DawKitClip.PITCH_BEND else CC_STEP
	if absi(value - int(last[2])) >= step and at_seconds - float(last[0]) >= CONTROL_GAP:
		_moved.erase(key)
		_keep(key, row)
	elif value == int(last[2]):
		# Back where it was kept: nothing to wait for.
		_moved.erase(key)
	elif not _moved.has(key) or int(_moved[key][2]) != value:
		# The newest move waits; the same value again keeps the time it was first reached.
		_moved[key] = row


## Every move waiting (`_moved`) from before `before` kept: all of them with INF.
func _settle(before: float) -> void:
	for key in _moved.keys():
		var row: Array = _moved[key]
		if float(row[0]) <= before:
			_moved.erase(key)
			_keep(key, row)


func _keep(key: String, row: Array) -> void:
	if controls.size() >= MAX_CONTROLS:
		return
	var last: Variant = _kept.get(key)
	if last != null and float(row[0]) < float(last[0]) + CONTROL_GAP:
		row = [float(last[0]) + CONTROL_GAP, row[1], row[2], row[3]]
	controls.append(row)
	_kept[key] = row


func is_empty() -> bool:
	return notes.is_empty() and _held.is_empty() and _sustained.is_empty() and controls.is_empty() \
			and _moved.is_empty()


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
	_settle(INF)
	var last := maxf(end, start + MIN_NOTE)
	return {"start": start, "end": last, "notes": out, "controls": flat_controls(controls, start, last)}


## Controls, [at, kind, value, channel] rows, flat and in time order as ItemState.controls has
## them ([time, kind, value, channel] repeating) but in song seconds, each pulled inside [from, to]:
## one stamped a hair before the take began is where the wheel stood as it began.
static func flat_controls(rows: Array, from: float, to: float) -> Array:
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for r in sorted:
		out.append_array([clampf(float(r[0]), from, to), int(r[1]), int(r[2]), int(r[3])])
	return out


func _close(held: Array, at_seconds: float) -> void:
	var on: float = held[0]
	notes.append([on, maxf(at_seconds, on + MIN_NOTE), held[3], held[1], held[2]])


# --- the host's side ------------------------------------------------------------------------

## A take as it arrived from a peer, made safe: `[track, start, end, notes, name, controls]` back,
## or [] if it cannot be read as a take at all. Everything is clamped rather than refused where a
## clamp has an honest meaning -- a note past the end of the take ends at the end -- and refused
## where it does not: a control is refused (left out) unless it is one of CONTROL_KINDS with a
## value in its range, since a bend of 9000 is not a bend a little less far. `controls` is flat
## [time, kind, value, channel] in song seconds, as `finish` gives it, each time pulled inside the
## take, at most MAX_CONTROLS.
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
	return [track, t0, t1, cleaned, name, clean_controls(args[5] if args.size() > 5 else [], t0, t1)]


## A peer's flat [time, kind, value, channel] controls, made safe for a take from `t0` to `t1`: a
## row whose numbers are not all finite, whose kind is not one of CONTROL_KINDS or whose value is
## out of its kind's range is left out; a time is pulled inside the take and a channel into 0-15.
## In time order, at most MAX_CONTROLS.
static func clean_controls(raw: Variant, t0: float, t1: float) -> Array:
	if not (raw is Array or raw is PackedFloat32Array or raw is PackedFloat64Array):
		return []
	var rows: Array = []
	for o in range(0, raw.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		if rows.size() >= MAX_CONTROLS:
			break
		var ok := true
		for i in DawKitClip.CONTROL_WIDTH:
			ok = ok and _is_number(raw[o + i]) and is_finite(float(raw[o + i]))
		if not ok:
			continue
		var kind := int(raw[o + 1])
		var value := float(raw[o + 2])
		if not CONTROL_KINDS.has(kind) or value != floorf(value):
			continue
		var low := DawKitClip.BEND_MIN if kind == DawKitClip.PITCH_BEND else 0.0
		var high := DawKitClip.BEND_MAX if kind == DawKitClip.PITCH_BEND else 127.0
		if value < low or value > high:
			continue
		rows.append([float(raw[o]), kind, int(value), clampi(int(raw[o + 3]), 0, 15)])
	return flat_controls(rows, t0, t1)


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


## Controller events (DawKitClip.controls: [time, kind, value, channel] repeating, seconds from the
## item's left edge) of an item that began at `old_start`, kept for the window [from, to) of the
## song and counted from `new_start`.
static func controls_between(controls: PackedFloat64Array, old_start: float, from: float, to: float,
		new_start: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for o in range(0, controls.size() - DawKitClip.CONTROL_WIDTH + 1, DawKitClip.CONTROL_WIDTH):
		var at := old_start + controls[o]
		if at >= from - 0.000001 and at < to:
			out.append_array(PackedFloat64Array([maxf(at - new_start, 0.0), controls[o + 1], controls[o + 2], controls[o + 3]]))
	return out
