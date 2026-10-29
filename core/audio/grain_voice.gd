class_name GrainVoice
extends Node

## A sample played as a cloud of grains (docs/spatial_loop.md part two, slice 54; idea #24): the
## grain cloud's sound. What it plays is a sound (`source`, mono at RATE: a sample's file, a MIDI
## clip's render or a demo part's window, GrainCloud's), and how it plays it is told it as grain
## events, EVENT_HZ a second, never by the hand itself. So what it plays is exactly what a list of
## events renders (`render`), here or anywhere, which is what slice 55 sends to bandmates and keeps
## as a take.
##
## ON THE WIRE (slice 55). An event is fourteen bytes (`pack`, `unpack`): its tick and five numbers,
## each on a grid of its own fine enough to hear nothing of (a 60000th of the sound, ten
## microseconds of a grain, a thousandth of a grain a second, a hundred-thousandth of the spray,
## a cent of pitch). `event` puts every number on its grid as it makes one, so the event a player
## plays and the one their bandmates and the host unpack are the same numbers, and render the same
## samples.
##
## AN EVENT is six numbers (`event`): its tick (a count of EVENT_HZ windows, its time), where in the
## sound it plays from (`at`, 0 the start, 1 the end), how long each grain is (SHORTEST to LONGEST
## seconds), how many grains a second (SPARSEST to DENSEST), how wide the spray is (`spread`, a
## fraction of the sound either way, up to SPREAD_MOST) and how far it is pitched (semitones). Each
## event is a WINDOW of frames: the grains it starts begin inside it, at frames and places drawn from
## a random number generator seeded by its tick, so the same events always make the same grains.
## A grain is the sound read from its place for its length, at its pitch, under a Hann window (no
## click at either end), as loud as LEVEL over the root of how many overlap. At most MOST sound at
## once: a grain due while MOST are sounding is not started.
##
## It is heard by this player on the keys' bus (AudioPorts.MONITOR), through Godot's mixer: a texture
## one player makes, said on the cloud's tag at its figure (`latency_seconds`), never the mix and
## never the DAW (part two, "Every sound has a path and a budget"). With a `speaker` (slice 55) it is
## a bandmate's grains as they arrive, out of the air at the cloud on the room's gear bus
## (Foley.emitter), as a bandmate's modular is heard at the wall.

## The rate it plays and renders at. A texture of grains, not a mix: half the card's rate keeps a
## cloud of 32 grains in GDScript's reach.
const RATE := 24000
## Events a second, and the frames each one is.
const EVENT_HZ := 30
const WINDOW := RATE / EVENT_HZ
## The most grains sounding at once.
const MOST := 32
## A grain's length (s), shortest to longest; the grains a second, sparsest to densest; the widest
## spray, a fraction of the sound either way of where it plays from.
const SHORTEST := 0.02
const LONGEST := 0.2
const SPARSEST := 4.0
const DENSEST := 60.0
const SPREAD_MOST := 0.3
## How loud one grain is, before the root of the overlap divides it.
const LEVEL := 0.55
## The longest sound it plays from (s): longer is kept to its start.
const SOURCE_MOST := 30.0
## How much is queued ahead of the card before the first window (s), and how much the queue holds.
const PREROLL := 1.0 / EVENT_HZ
const BUFFER := 0.12
## The bus it plays on: the keys', what a personal mix calls this player's own.
const BUS := AudioPorts.MONITOR
## How long it rests silent before it lets its player go (s).
const IDLE := 0.5
## An event's numbers, in order.
enum { TICK, AT, LENGTH, DENSITY, SPREAD, PITCH, FIELDS }
## The grids an event's numbers lie on (steps in each unit: of the sound, of a second, of a grain a
## second, of the sound either way, of a semitone), and how many bytes it is on the wire.
const AT_STEPS := 60000.0
const LENGTH_STEPS := 100000.0
const DENSITY_STEPS := 1000.0
const SPREAD_STEPS := 100000.0
const PITCH_STEPS := 100.0
const PACKED := 14

## The Hann window, as a table read by a grain's progress through it.
const HANN_SIZE := 1024
static var _hann := PackedFloat32Array()

## Where a bandmate's grains come from (slice 55): with one, it plays out of the air there, at
## `speaker_at` in its frame, on the room's gear bus, `volume_db` down; without, on this player's
## MONITOR.
var speaker: Node3D = null
var speaker_at := Vector3.ZERO
var volume_db := 0.0
## What it plays from: mono at RATE.
var source := PackedFloat32Array()
## Every window it has played while `keeping`, end to end: what the player heard, for the suite and
## for slice 55's take.
var keeping := false
var kept := PackedFloat32Array()
## How many windows the card had no room for (its queue full): played to nobody.
var dropped := 0
## How many times PREROLL has been queued: once each time the player starts, and again whenever the
## card has played all it was given.
var prerolls := 0
## This player's own: what plays it on MONITOR; a bandmate's: the emitter at the speaker.
var player: AudioStreamPlayer
var emitter: AudioStreamPlayer3D
var _renderer := Renderer.new()
var _playback: AudioStreamGeneratorPlayback = null
var _idle := 0.0
## The card's queue empty: how many frames it has room for then.
var _room := 0


func _ready() -> void:
	AudioPorts.ensure_buses()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = BUFFER
	if speaker != null:
		emitter = Foley.emitter(stream, volume_db)
		emitter.name = "GrainEmitter"
		emitter.position = speaker_at
		speaker.add_child(emitter)
		return
	player = AudioStreamPlayer.new()
	player.name = "GrainPlayer"
	player.bus = BUS
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)


func _exit_tree() -> void:
	if emitter != null and is_instance_valid(emitter):
		emitter.queue_free()
		emitter = null


## What it is heard through: its player, or a bandmate's emitter at the speaker.
func _out() -> Node:
	return emitter if emitter != null else player


## An event (see the header): its numbers kept inside their ranges, each on its grid.
static func event(tick: int, at: float, length: float, density: float, spread: float, pitch := 0.0) -> PackedFloat32Array:
	var e := PackedFloat32Array()
	e.resize(FIELDS)
	e[TICK] = float(maxi(tick, 0))
	e[AT] = _on_grid(clampf(at, 0.0, 1.0), AT_STEPS)
	e[LENGTH] = _on_grid(clampf(length, SHORTEST, LONGEST), LENGTH_STEPS)
	e[DENSITY] = _on_grid(clampf(density, SPARSEST, DENSEST), DENSITY_STEPS)
	e[SPREAD] = _on_grid(clampf(spread, 0.0, SPREAD_MOST), SPREAD_STEPS)
	e[PITCH] = _on_grid(clampf(pitch, -12.0, 12.0), PITCH_STEPS)
	return e


static func _on_grid(v: float, steps: float) -> float:
	return float(roundi(v * steps)) / steps


## Event `e` in PACKED bytes for the wire: its tick (32 bits) and its numbers on their grids (16 bits
## each, the pitch signed). Empty for what is not an event.
static func pack(e: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	if not is_event(e):
		return out
	out.resize(PACKED)
	out.encode_u32(0, int(e[TICK]))
	out.encode_u16(4, roundi(e[AT] * AT_STEPS))
	out.encode_u16(6, roundi(e[LENGTH] * LENGTH_STEPS))
	out.encode_u16(8, roundi(e[DENSITY] * DENSITY_STEPS))
	out.encode_u16(10, roundi(e[SPREAD] * SPREAD_STEPS))
	out.encode_s16(12, roundi(e[PITCH] * PITCH_STEPS))
	return out


## The event `bytes` carry (`pack`'s), the same numbers it was made with; empty for bytes that are not
## one (the wrong size, or a number outside its range: a bandmate's word is checked, not trusted).
static func unpack(bytes: PackedByteArray) -> PackedFloat32Array:
	if bytes.size() != PACKED:
		return PackedFloat32Array()
	var e := PackedFloat32Array()
	e.resize(FIELDS)
	e[TICK] = float(bytes.decode_u32(0))
	e[AT] = float(bytes.decode_u16(4)) / AT_STEPS
	e[LENGTH] = float(bytes.decode_u16(6)) / LENGTH_STEPS
	e[DENSITY] = float(bytes.decode_u16(8)) / DENSITY_STEPS
	e[SPREAD] = float(bytes.decode_u16(10)) / SPREAD_STEPS
	e[PITCH] = float(bytes.decode_s16(12)) / PITCH_STEPS
	return e if is_event(e) else PackedFloat32Array()


## Whether `e` is an event as `event` makes one: six finite numbers inside their ranges, a whole tick.
static func is_event(e: Variant) -> bool:
	if not e is PackedFloat32Array or (e as PackedFloat32Array).size() != FIELDS:
		return false
	var p := e as PackedFloat32Array
	for v in p:
		if not is_finite(v):
			return false
	return p[TICK] >= 0.0 and p[TICK] == floorf(p[TICK]) and p == event(int(p[TICK]), p[AT], p[LENGTH], p[DENSITY], p[SPREAD], p[PITCH])


## The sound it plays from now on: mono at RATE (`mono_of`). Grains still sounding from the last one
## go on reading it, so a cassette swapped mid-cloud does not click.
func use(sound: PackedFloat32Array) -> void:
	source = sound
	_renderer.source = sound


## Plays event `e`: its window rendered and queued for the card. The first after a rest starts the
## player and queues PREROLL of silence ahead of it, so the queue never runs dry between events; and
## so does one that finds the card's queue run dry (a long frame), so the figure on the tag holds.
func play(e: PackedFloat32Array) -> void:
	_idle = 0.0
	_queue(_renderer.window(e))


## A window with no event in it: the grains still sounding rung on, and once there are none, silent
## windows fed to the card (not kept: nothing was played) until IDLE has passed, then the player let
## go. Fed, the card's queue stays as deep as PREROLL, so a hand back within IDLE (a button let go and
## pressed again, a hand slipping past the cloud's edge and back) is heard without a gap.
func rest() -> void:
	if _renderer.sounding():
		_queue(_renderer.window(PackedFloat32Array()))
		return
	if not is_playing():
		return
	_idle += 1.0 / EVENT_HZ
	if _idle >= IDLE:
		stop()
		return
	var quiet := PackedFloat32Array()
	quiet.resize(WINDOW)
	_feed(quiet)


## Silent at once: the grains dropped and the player let go.
func stop() -> void:
	_renderer.clear()
	_idle = 0.0
	var out: Variant = _out()
	if out != null and out.playing:
		out.stop()
	_playback = null


func is_playing() -> bool:
	var out: Variant = _out()
	return out != null and out.playing


## Grains sounding now.
func sounding() -> int:
	return _renderer.grains.size()


## Where in the sound (0 to 1) the grains the last window started play from: what the cloud lights.
func last_born() -> PackedFloat32Array:
	return _renderer.born


func _queue(mono: PackedFloat32Array) -> void:
	if keeping:
		kept.append_array(mono)
	_feed(mono)


## `mono` pushed to the card, the player started first if it rests. Started, or found with nothing
## left queued, PREROLL of silence goes ahead of it.
func _feed(mono: PackedFloat32Array) -> void:
	var out: Variant = _out()
	if out == null:
		return
	if not out.playing:
		out.play()
		_playback = out.get_stream_playback() as AudioStreamGeneratorPlayback
		_room = _playback.get_frames_available() if _playback != null else 0
		_preroll()
	elif _playback != null and _room > 0 and _playback.get_frames_available() >= _room:
		_preroll()
	if _playback == null:
		return
	if _playback.get_frames_available() < mono.size():
		dropped += 1
		return
	var frames := PackedVector2Array()
	frames.resize(mono.size())
	for i in mono.size():
		var s := clampf(mono[i], -1.0, 1.0)
		frames[i] = Vector2(s, s)
	_playback.push_buffer(frames)


func _preroll() -> void:
	if _playback == null:
		return
	var quiet := PackedVector2Array()
	quiet.resize(roundi(PREROLL * RATE))
	_playback.push_buffer(quiet)
	prerolls += 1


## The figure on the cloud's tag: how late what the hand does is heard (s): an event's window, the
## silence queued ahead of it, and the card's own.
static func latency_seconds() -> float:
	return 1.0 / EVENT_HZ + PREROLL + AudioServer.get_output_latency()


## `events` (each as `event` makes one), rendered from the first one's tick to the last's and on
## until the last grain has rung: mono at RATE, a window an event, silent where no event was. The
## live voice is this, a window at a time. Pure, and safe off the main thread.
static func render(sound: PackedFloat32Array, events: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if events.is_empty():
		return out
	var by_tick := {}
	var first := INF
	var last := -INF
	for e: PackedFloat32Array in events:
		by_tick[int(e[TICK])] = e
		first = minf(first, e[TICK])
		last = maxf(last, e[TICK])
	var r := Renderer.new()
	r.source = sound
	for tick in range(int(first), int(last) + 1):
		out.append_array(r.window(by_tick.get(tick, PackedFloat32Array())))
	while r.sounding():
		out.append_array(r.window(PackedFloat32Array()))
	return out


## `frames` (stereo at `rate`) as the cloud plays them: mono at RATE, read in a straight line between
## samples, SOURCE_MOST at most. Safe off the main thread.
static func mono_of(frames: PackedVector2Array, rate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if frames.is_empty() or rate <= 0:
		return out
	var seconds := minf(float(frames.size()) / float(rate), SOURCE_MOST)
	out.resize(maxi(roundi(seconds * RATE), 1))
	var step := float(rate) / float(RATE)
	var last := frames.size() - 1
	for i in out.size():
		var at := float(i) * step
		var j := mini(int(at), last)
		var k := mini(j + 1, last)
		var a := (frames[j].x + frames[j].y) * 0.5
		var b := (frames[k].x + frames[k].y) * 0.5
		out[i] = lerpf(a, b, at - float(j))
	return out


## How loud `sound` is across its length, in `bins` from its start to its end: each the loudest of its
## stretch, over the loudest of all (1 the loudest bin; all 0 for silence).
static func envelope_of(sound: PackedFloat32Array, bins: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(bins, 0))
	if sound.is_empty() or bins <= 0:
		return out
	var peak := 0.0
	for b in bins:
		var from := int(float(b) / bins * sound.size())
		var to := maxi(int(float(b + 1) / bins * sound.size()), from + 1)
		var loud := 0.0
		for i in range(from, mini(to, sound.size())):
			loud = maxf(loud, absf(sound[i]))
		out[b] = loud
		peak = maxf(peak, loud)
	if peak > 0.0:
		for b in bins:
			out[b] /= peak
	return out


static func _window_table() -> PackedFloat32Array:
	if _hann.is_empty():
		_hann.resize(HANN_SIZE)
		for i in HANN_SIZE:
			_hann[i] = 0.5 - 0.5 * cos(TAU * float(i) / float(HANN_SIZE - 1))
	return _hann


## The arithmetic, a window at a time: the grains sounding, carried from one window to the next.
## The live voice and `render` both are one of these.
class Renderer extends RefCounted:
	var source := PackedFloat32Array()
	## Each grain sounding: [where it reads now (frames of the source), how far it reads a frame,
	## frames into it, how long it is (frames), how loud].
	var grains: Array[PackedFloat64Array] = []
	## Where in the sound (0 to 1) the grains the last window started play from.
	var born := PackedFloat32Array()

	func sounding() -> bool:
		return not grains.is_empty()

	func clear() -> void:
		grains.clear()
		born = PackedFloat32Array()

	## One WINDOW of mono at RATE: the grains sounding rung on, and event `e`'s grains started in it
	## (none for an empty `e`).
	func window(e: PackedFloat32Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(WINDOW)
		born = PackedFloat32Array()
		var onsets: Array = []
		if e.size() == FIELDS and source.size() > 1:
			onsets = _onsets(e)
		var hann := GrainVoice._window_table()
		var next := 0
		# Grains begin at their onsets in order: each only if fewer than MOST sound at that frame.
		var starts: Array[PackedFloat64Array] = []
		for o: Array in onsets:
			var frame: int = o[0]
			var alive := 0
			for g in grains:
				if g[3] - g[2] > frame:
					alive += 1
			for s in starts:
				if s[5] <= frame and s[5] + s[3] > frame:
					alive += 1
			if alive >= MOST:
				continue
			var g: PackedFloat64Array = o[1]
			starts.append(g)
			born.append(float(o[2]))
		for g in starts:
			grains.append(g)
		var last := source.size() - 1
		var scale := float(HANN_SIZE - 1)
		var keep: Array[PackedFloat64Array] = []
		for g in grains:
			var read := g[0]
			var step := g[1]
			var i := int(g[2])
			var n := int(g[3])
			var amp := g[4]
			var from := int(g[5]) if g.size() > 5 else 0
			var span := float(maxi(n - 1, 1))
			var f := from
			while f < WINDOW and i < n:
				var j := int(read)
				var k := mini(j + 1, last)
				var s := source[mini(j, last)]
				s += (source[k] - s) * (read - float(j))
				out[f] += s * hann[int(float(i) / span * scale)] * amp
				read += step
				i += 1
				f += 1
			if i < n:
				keep.append(PackedFloat64Array([read, step, i, n, amp]))
		grains = keep
		return out

	## Event `e`'s grains, drawn from its tick: [[frame in the window, grain, where it plays from]],
	## in order of frame. A grain is [read, step, 0, length, level, onset frame].
	func _onsets(e: PackedFloat32Array) -> Array:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(int(e[TICK]))
		var per := e[DENSITY] / float(EVENT_HZ)
		var count := floori(per) + (1 if rng.randf() < per - floorf(per) else 0)
		var n := maxi(roundi(e[LENGTH] * RATE), 2)
		var step := pow(2.0, e[PITCH] / 12.0)
		var amp := LEVEL / sqrt(maxf(1.0, e[DENSITY] * e[LENGTH]))
		var long := float(source.size())
		var out: Array = []
		for c in count:
			var frame := rng.randi_range(0, WINDOW - 1)
			var place := clampf(e[AT] + e[SPREAD] * (rng.randf() * 2.0 - 1.0), 0.0, 1.0)
			# The grain is centred on its place, and kept inside the sound.
			var read := clampf(place * long - float(n) * step * 0.5, 0.0, maxf(long - 1.0 - float(n) * step, 0.0))
			out.append([frame, PackedFloat64Array([read, step, 0, n, amp, frame]), place])
		out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		return out
