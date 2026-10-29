class_name ModularWorld
extends Node

## The world into the modular (docs/spatial_loop.md part two, slice 53; idea #31): what the room's own
## music-makers play into the modular's world sockets (Modular.WORLD), worked out on every machine
## from the song clock and the rows, so the rain on the filter sounds the same everywhere and nothing
## of it crosses the wire. The studio's (`Studio.modular_world`).
##
## Each socket carries a level (Modular.Event.WORLD) and a gate (Event.TRIG):
## - `world:weather`: the weather's density as a level, the storm's swinging with its gusts, at every
##   sixteenth (Weather.level), and a gate each drop on the glass (Weather.drops).
## - `world:drips`: in the cave, a gate each drip into its pools, and its velocity as the level
##   while the gate is open (a pulse, `_pulses`).
## - `world:venue`: a gate each strike of the venue's instrument, at the song its item hit was struck
##   at (`strike`, Session.item_hit's `song`), and its velocity, a pulse likewise.
## - `world:ring_1` to `world:ring_8`: each of the looper's layers, lowest ring first, as its own
##   notes' velocities over the loop (the loudest note sounding, 0 between them), and a gate each note
##   begins: its notes, not a meter, so it is the same on every machine (`ring_level`).
## - `world:marbles`: a gate each bell a marble rings (MarbleRun.rings), a pulse likewise.
##
## `events(from, to)` is every one of them from song position `from` up to `to`, in order, and pure:
## the same span, the same rows, the same events, on every machine. `levels_at` is where each level
## stands at a moment, for a take or a voice starting from it. As the song plays here (`follow`), each
## frame's span is handed on (`fired`) to every copy of the patch this machine plays (ModularVoice:
## this player's, each bandmate's, the world's own at the wall). A strike heard from a bandmate after
## its song has gone by is played into them at once.

## The events a span of the song played into the world's sockets: [song, Modular.Event, socket, value]
## each, in order.
signal fired(events: Array)

## A sixteenth, in the tempo map's quarter-note beats: how often the weather's level is told.
const SIXTEENTH := 0.25
## The most sixteenths one span reads.
const MOST_STEPS := 4096
## A jump of the song this far or more (s), or back, is a seek: nothing between is played.
const JUMP := 1.0
## The most strikes of the venue's instrument kept (for takes rendered after them).
const MOST_STRIKES := 2048
## The weather's density that is a level of 1: the storm's most (Weather.KINDS).
const WEATHER_TOP := 0.42

## Where the song is, here: {seconds, playing, valid}. GuestMidi.heard by default.
var heard_source: Callable = Callable()
## The song (its tempo, meter, brackets and tracks): DAW.state by default.
var state_source: Callable = Callable()
## The venue's weather (a Weather), its marble run (a MarbleRun), and whether it has an instrument
## to strike: each a Callable the studio gives, null or false where there is none.
var weather: Callable = Callable()
var marbles: Callable = Callable()
var has_venue: Callable = Callable()
## The venue's instrument's strikes, [song, velocity] each, in song order.
var strikes: Array = []
## The song position the world has been played up to, or NAN while the song is not playing.
var _until := NAN
## Strikes played in at once because they came after their song: their pulse's end, due on the wall
## clock ([msec, song] each).
var _late_ends: Array = []


func _init() -> void:
	name = "ModularWorld"


func state() -> MixState:
	if state_source.is_valid():
		return state_source.call()
	return DAW.state


func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "valid": false}


func _weather() -> Weather:
	var w: Variant = weather.call() if weather.is_valid() else null
	return w as Weather if w is Weather and is_instance_valid(w) else null


func _marbles() -> MarbleRun:
	var m: Variant = marbles.call() if marbles.is_valid() else null
	return m as MarbleRun if m is MarbleRun and is_instance_valid(m) else null


## The sockets this venue has something behind: the weather or the drips, the venue's instrument, a
## ring for each of the looper's layers, and the marble run.
func present() -> Array[StringName]:
	var out: Array[StringName] = []
	var w := _weather()
	if w != null and not w.spec.is_empty():
		out.append(weather_socket(w.spec))
	if has_venue.is_valid() and has_venue.call():
		out.append(&"world:venue")
	var s := state()
	for i in mini(LooperRings.layers(s).size(), LooperRings.MOST):
		out.append(Modular.ring_socket(i + 1))
	if _marbles() != null:
		out.append(&"world:marbles")
	return out


## The socket a weather plays into: `world:drips` in the cave, `world:weather` everywhere else.
static func weather_socket(spec: Dictionary) -> StringName:
	return &"world:drips" if spec.get("kind", &"") == &"drips" else &"world:weather"


# --- what the world plays ------------------------------------------------------------------------

## Every event the world plays into its sockets from song position `from` up to, not including, `to`,
## in order: [song, Modular.Event.WORLD or TRIG, socket, value].
func events(from: float, to: float) -> Array:
	var out: Array = []
	var s := state()
	if s == null or to <= from:
		return out
	var w := _weather()
	if w != null and not w.spec.is_empty():
		out.append_array(weather_events(w.spec, w.seed, s, from, to))
	if has_venue.is_valid() and has_venue.call():
		_pulses(&"world:venue", strikes, from, to, out)
	out.append_array(ring_events(s, from, to))
	var m := _marbles()
	if m != null:
		var rung: Array = []
		for r: Dictionary in MarbleRun.rings(m.rows, m.balls, s, maxf(from - Modular.WORLD_GATE, 0.0), to):
			rung.append([float(r["song"]), int(r["velocity"])])
		_pulses(&"world:marbles", rung, from, to, out)
	return ordered(out)


## Where every level stands at song position `at`, as WORLD events there: what a take, or a voice,
## starts from. A gate is not a level: one open at `at` is not carried.
func levels_at(at: float) -> Array:
	var out: Array = []
	var s := state()
	if s == null:
		return out
	var w := _weather()
	if w != null and not w.spec.is_empty():
		var socket := weather_socket(w.spec)
		if socket == &"world:weather":
			out.append([at, Modular.Event.WORLD, socket, weather_level(w.spec, s, at)])
		else:
			var drops: Array = []
			for d: Dictionary in Weather.drops(w.spec, w.seed, s, maxf(at - Modular.WORLD_GATE, 0.0), at + 0.000001):
				drops.append([float(d["song"]), int(d["velocity"])])
			out.append([at, Modular.Event.WORLD, socket, pulse_at(drops, at)])
	if has_venue.is_valid() and has_venue.call():
		out.append([at, Modular.Event.WORLD, &"world:venue", pulse_at(strikes, at)])
	var layers := LooperRings.layers(s)
	for i in mini(layers.size(), LooperRings.MOST):
		out.append([at, Modular.Event.WORLD, Modular.ring_socket(i + 1), ring_level(s, int(layers[i]["index"]), at)])
	var m := _marbles()
	if m != null:
		var rung: Array = []
		for r: Dictionary in MarbleRun.rings(m.rows, m.balls, s, maxf(at - Modular.WORLD_GATE, 0.0), at + 0.000001):
			rung.append([float(r["song"]), int(r["velocity"])])
		out.append([at, Modular.Event.WORLD, &"world:marbles", pulse_at(rung, at)])
	return out


## What a take through the modular from `from` to `to` hears of the world: where the levels stood at
## its start, and everything after (ModularTakes, before it renders).
func for_take(from: float, to: float) -> Array:
	return levels_at(from) + events(from, to)


## `list` in song order, those at one song in the order they were made: the same on every machine.
static func ordered(list: Array) -> Array:
	var keyed: Array = []
	for i in list.size():
		keyed.append([float(list[i][0]), i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for k: Array in keyed:
		out.append(list[k[1]])
	return out


## The weather `spec` (with its venue's seed) from `from` up to `to` in the song `s`: on the glass, its
## density as `world:weather`'s level at every sixteenth and a gate each drop; in the cave a pulse each
## drip into `world:drips`.
static func weather_events(spec: Dictionary, venue_seed: int, s: MixState, from: float, to: float) -> Array:
	var out: Array = []
	if spec.is_empty() or s == null or to <= from:
		return out
	var socket := weather_socket(spec)
	if socket == &"world:drips":
		var drops: Array = []
		for d: Dictionary in Weather.drops(spec, venue_seed, s, maxf(from - Modular.WORLD_GATE, 0.0), to):
			drops.append([float(d["song"]), int(d["velocity"])])
		_pulses(socket, drops, from, to, out)
		return ordered(out)
	var first := s.beat_at(maxf(from, 0.0))
	var last := s.beat_at(maxf(to, 0.0))
	var n := ceili(first / SIXTEENTH - 0.000001)
	for i in MOST_STEPS:
		var beat := float(n + i) * SIXTEENTH
		if beat >= last:
			break
		if beat < first:
			continue
		var at := s.seconds_at_beat(beat)
		out.append([at, Modular.Event.WORLD, socket, Weather.level(spec, s.meter().bar_at(beat)) / WEATHER_TOP])
	for d: Dictionary in Weather.drops(spec, venue_seed, s, from, to):
		out.append([float(d["song"]), Modular.Event.TRIG, socket, float(d["velocity"]) / 127.0])
	return ordered(out)


## The weather's level at song position `at`: its density then, as a share of WEATHER_TOP.
static func weather_level(spec: Dictionary, s: MixState, at: float) -> float:
	var beat := floorf(s.beat_at(maxf(at, 0.0)) / SIXTEENTH + 0.000001) * SIXTEENTH
	return Weather.level(spec, s.meter().bar_at(beat)) / WEATHER_TOP


## A pulse into `socket` for each of `hits` ([song, velocity] each, in song order) that falls in `from`
## to `to`: its velocity as the level and its gate opened, and the level back to 0 Modular.WORLD_GATE
## later, unless the next has come by then. Into `out`.
static func _pulses(socket: StringName, hits: Array, from: float, to: float, out: Array) -> void:
	for i in hits.size():
		var at := float(hits[i][0])
		if at >= to:
			break
		var end := at + Modular.WORLD_GATE
		if end < from:
			continue
		if at >= from:
			out.append([at, Modular.Event.WORLD, socket, clampf(float(hits[i][1]) / 127.0, 0.0, 1.0)])
			out.append([at, Modular.Event.TRIG, socket, clampf(float(hits[i][1]) / 127.0, 0.0, 1.0)])
		var next_at := float(hits[i + 1][0]) if i + 1 < hits.size() else INF
		if end >= from and end < to and next_at > end:
			out.append([end, Modular.Event.WORLD, socket, 0.0])


## A pulse's level at `at` from `hits` ([song, velocity] each, in song order): the newest one's
## velocity while its WORLD_GATE lasts, else 0.
static func pulse_at(hits: Array, at: float) -> float:
	var level := 0.0
	for h: Array in hits:
		if float(h[0]) > at:
			break
		level = clampf(float(h[1]) / 127.0, 0.0, 1.0) if at < float(h[0]) + Modular.WORLD_GATE else 0.0
	return level


## The looper's layers from `from` up to `to` in `s`: each, lowest ring first, into its `world:ring_N`
## as its notes' level (`ring_level`) wherever that changes, and a gate each note begins.
static func ring_events(s: MixState, from: float, to: float) -> Array:
	var out: Array = []
	var layers := LooperRings.layers(s)
	for i in mini(layers.size(), LooperRings.MOST):
		var socket := Modular.ring_socket(i + 1)
		var notes := ring_notes(s, int(layers[i]["index"]))
		var edges: Array = []
		for n: Array in notes:
			if float(n[0]) >= from and float(n[0]) < to:
				edges.append(float(n[0]))
			if float(n[1]) >= from and float(n[1]) < to:
				edges.append(float(n[1]))
		edges.sort()
		var was := ring_level_of(notes, from - 0.000001) if not edges.is_empty() else 0.0
		var last := NAN
		for at: float in edges:
			if at == last:
				continue
			last = at
			var level := ring_level_of(notes, at)
			if level != was:
				out.append([at, Modular.Event.WORLD, socket, level])
				was = level
			for n: Array in notes:
				if float(n[0]) == at:
					out.append([at, Modular.Event.TRIG, socket, float(n[2])])
					break
	return out


## Layer track `track`'s notes in `s`, in song seconds: [on, off, velocity 0..1] each, its items' and
## within them, none where the track or the item is muted.
static func ring_notes(s: MixState, track: int) -> Array:
	var out: Array = []
	var t := s.track(track, false) if s != null else null
	if t == null or t.mute:
		return out
	for item: MixState.ItemState in t.items:
		if item.muted:
			continue
		var n := item.notes
		var end := item.start + item.length
		for k in range(0, n.size() - 4, 5):
			var on := item.start + float(n[k])
			var off := minf(item.start + float(n[k + 1]), end)
			if off > on and on < end:
				out.append([on, off, clampf(float(n[k + 3]) / 127.0, 0.0, 1.0)])
	return out


## A layer's level at `at`: the loudest of its notes sounding then, 0 between them.
static func ring_level(s: MixState, track: int, at: float) -> float:
	return ring_level_of(ring_notes(s, track), at)


static func ring_level_of(notes: Array, at: float) -> float:
	var level := 0.0
	for n: Array in notes:
		if float(n[0]) <= at and at < float(n[1]):
			level = maxf(level, float(n[2]))
	return level


# --- as the song plays here ------------------------------------------------------------------------

## A strike of the venue's instrument at song position `song` at `velocity`: kept, and played in at
## once where its song has gone by here (a bandmate's, arriving after it).
func strike(song: float, velocity: int) -> void:
	if not is_finite(song) or song < 0.0:
		return
	var at := strikes.size()
	while at > 0 and float(strikes[at - 1][0]) > song:
		at -= 1
	strikes.insert(at, [song, clampi(velocity, 1, 127)])
	while strikes.size() > MOST_STRIKES:
		strikes.pop_front()
	if not is_nan(_until) and song < _until:
		var v := clampf(float(velocity) / 127.0, 0.0, 1.0)
		fired.emit([[song, Modular.Event.WORLD, &"world:venue", v], [song, Modular.Event.TRIG, &"world:venue", v]])
		_late_ends.append([Time.get_ticks_msec() + roundi(Modular.WORLD_GATE * 1000.0), song])


func _process(_delta: float) -> void:
	follow(heard())
	var now := Time.get_ticks_msec()
	for e: Array in _late_ends.duplicate():
		if now >= int(e[0]):
			_late_ends.erase(e)
			# Its pulse ends, unless a strike came after it in the meantime.
			if not strikes.is_empty() and float(strikes[strikes.size() - 1][0]) <= float(e[1]):
				fired.emit([[float(e[1]) + Modular.WORLD_GATE, Modular.Event.WORLD, &"world:venue", 0.0]])


## One frame of the song as heard (`h`): every event since the last frame fired, in order. Starting, or
## after a jump (a seek, the loop going round), where every level stands now is fired first.
func follow(h: Dictionary) -> void:
	var now := float(h.get("seconds", 0.0))
	if not h.get("valid", false) or not h.get("playing", false):
		_until = NAN
		return
	if is_nan(_until) or now < _until or now - _until >= JUMP:
		_until = now
		fired.emit(levels_at(now))
		return
	if now > _until:
		var span := events(_until, now)
		_until = now
		if not span.is_empty():
			fired.emit(span)


## Every event of `list` played into `voice` now.
static func play_into(voice: ModularVoice, list: Array) -> void:
	for e: Array in list:
		if int(e[1]) == Modular.Event.WORLD:
			voice.world(e[2], float(e[3]))
		elif int(e[1]) == Modular.Event.TRIG:
			voice.trig(e[2])
