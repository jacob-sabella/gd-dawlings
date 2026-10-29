class_name Platter
extends Node3D

## A DJ platter (docs/spatial_loop.md part two, slice 27, idea #17): a turntable on the leaf of the
## tape deck's cart, beside the deck, whose label turns with the song, a turn a bar. A station
## (Stations.ALL, `platter`): gone to by name, its plaque on the leaf's front.
##
## BARE, IT IS THE PLAYHEAD. Its angle is where the song is (`turns`, bars from the start, through
## the tempo's and the meter's changes). Take hold of it and the song stops (DAW.transport_stop,
## while held); turn it and the song position follows its angle (`seconds_of`), sounded where the
## DAW can by DAW.scrub (the built-in engine plays a short window of the mix at each place, Reaper
## takes OSC's scrub) and moved by quiet seeks where it cannot, which its card says; let go, and it
## plays on from there if it was playing. Held still, it is stopped and silent. Flicked backwards
## faster than BACKSPIN turns a second and let go, it spins back: free, slowing, the spin-back sound
## (Foley.spinback) once, and the playhead put back the bars it spun, onto a bar line, when it
## stops. The wheel (or the thumbstick) moves the playhead a beat a notch, a quarter beat fine.
##
## A CASSETTE IN ITS SLOT IS SCRATCHED. Stood in the slot (the room's holder `platter`, one slot),
## the platter is the cassette's: turned, its clip's render is read at the platter's speed and
## direction (Varispeed), for this player alone on MONITOR through Godot's mixer at the figure on
## the cassette's tag, and the playhead is untouched. The clip turns a turn a bar at the song's
## tempo. A scratch from grab to let-go is a path (Varispeed.path) the sampler can catch (`scratched`):
## the host renders it from its own copy of the clip, so a guest's scratch is kept as it heard it.
##
## A GUEST'S TURNS ARE SEEKS asked of the host, at most SEEK_HZ a second (the last always sent), and
## what it hears turning is its own: a needle's drag (Foley.needle_drag), as loud as it turns. The
## host's word on the song comes back as the playhead it then follows.
##
## Everything that moves by itself respects Ergonomics.motion_scale: at 0 the label steps a beat at
## a time, and a spin-back lands at once. Nothing is said by colour alone: the lettering along the
## plinth's front says what it is doing (HELD · STOPPED, SPIN BACK, SCRATCH).
##
## Its numbers are tools/blender/platter.py's, which builds the models. Origin the middle of its
## foot on the cart's leaf, its front +Z.

const MODEL := "res://assets/models/platter.glb"
const DISC_MODEL := "res://assets/models/platter_disc.glb"
## The room's holder its slot is (ItemRoom.holders), and the room verb a guest's scratch is sent to
## the host's sampler by: [the cassette's id, its path].
const HOLDER := &"platter"
const SCRATCH_VERB := &"scratch"
## The longest scratch path a guest may send, in steps (Varispeed.PATH_MOST).
const SCRATCH_MOST := Varispeed.PATH_MOST
## Where it stands on the deck's cart (the trolley's frame): on the leaf, the cart's front its front,
## a centimetre below the shelf the deck stands on.
const ON_CART := Transform3D(Basis.IDENTITY, Vector3(0.46, 0.87, 0.0))
## The leaf it stands on, (x, z) size, in the cart's frame centred under it, and how thick. It runs
## in under the shelf's end (to LEAF_FROM, the shelf ending at 0.28), so it reads as one piece with it.
const LEAF := Vector2(0.36, 0.40)
const LEAF_THICK := 0.04
const LEAF_FROM := 0.265
## The plinth's half size on the leaf and its top; the platter's axis on it, and the disc's top.
const PLINTH := Vector3(0.17, 0.05, 0.16)
const AXIS := Vector3(-0.04, 0.056, 0.0)
const RADIUS := 0.12
const DISC_TOP := 0.0135
## The cassette's slot: where one stands in it, upright, its label to the front (an item's -Z, as
## the rack's slots have it: CassetteRack.slot_pose).
const SLOT_POSE := Transform3D(Basis(Vector3.UP, PI), Vector3(0.115, 0.06, 0.10))
## The lettering along the plinth's front, and how wide it may run.
const READOUT_AT := Vector3(-0.02, 0.029, 0.1605)
const READOUT_WIDTH := 0.27
const READOUT_SIZE := 120
## Its plaque hangs by its top edge from the leaf's front, below the plinth, so from the seat it
## is under the record and the lettering, not in front of them.
const PLAQUE_TOP := -0.05
const PLAQUE_Z := 0.205
const PLAQUE_WIDTH := 0.4

## A flick backwards faster than this (turns a second) and let go is a back-spin.
const BACKSPIN := 3.0
## How long a stretch of the hand's turning its speed is read over (s).
const SPEED_SPAN := 0.08
## The most seeks a guest's turning asks of the host a second.
const SEEK_HZ := 15.0
## A guest's platter stands where its seek put it until the host's song is there (within a beat of
## it), or this long (s) at most, rather than going back to where the host was before the seek.
const SEEK_WAIT := 1.0
## How hard a free spin slows (turns a second, a second): from BACKSPIN it spins a bar.
const SPIN_DRAG := 4.5
## The needle's drag, as loud as this at a song-second a second and quieter slower.
const NEEDLE_DB := -14.0

## A hand here scratched `cassette`: its whole path, for the sampler to catch (studio's to send).
signal scratched(cassette: CassetteItem, path: PackedFloat32Array)

## The room whose cassette its slot holds.
var items: ItemRoom = null
## Whether this machine's word is the song's (Session.is_authority): its turns scrub, a guest's seek.
var authority: Callable = Callable()
## Where this machine has file `source` (a clip's audio), "" where it has none; a guest's begins a
## fetch of it. And whether a fetch of it is still under way.
var find_file: Callable = Callable()
var fetching: Callable = Callable()
## Where the platter is turned to: bars from the song's start, clockwise from above. Bare and let be,
## it is where the song is.
var turns := 0.0
## How many spin-backs it has played, seeks it has asked and scratches it has rendered (for the
## sampler, `rendered_scratch`), for the suite.
var spins := 0
var seeks_sent := 0
var scratches_rendered := 0
var disc: Disc
var slot: Slot
var scratch: Varispeed
var readout: Label3D

## Held: by whom, where it was taken at, whether the song was playing then.
var _held := false
var _wanted := 0.0
var was_playing := false
var _history: Array = []
var _clock := 0.0
var _last_seconds := 0.0
## A guest's seek waiting for its turn (seconds, or -1), the time since the last, and whether to
## play once it has gone.
var _want_seek := -1.0
var _since_seek := INF
var _resume_after_seek := false
## A guest's last seek sent (seconds, or -1) that its platter stands at until the host's song
## arrives there (SEEK_WAIT).
var _awaiting_seek := -1.0
## A free spin-back: its speed (turns a second), how hard it slows, and where it lands.
var _spinning := false
var _spin_speed := 0.0
var _spin_drag := 0.0
var _spin_to := 0.0
## A notch's beat played forwards or back on a cassette: turns to go, and how fast.
var _auto_left := 0.0
var _auto_rate := 0.0
## The cassette in the slot, what its clip's render is, and how getting it is going.
var cassette: CassetteItem = null
enum Source { NONE, RENDERING, FETCHING, MISSING, EMPTY, READY }
var source := Source.NONE
## The turns the cassette's clip is at, kept while it is in.
var clip_turns := 0.0
var _source_key := ""
## Rendered clips, {key: [frames, rate]}, the newest last; and renders under way {key: [task, result]}.
var _sources := {}
var _tasks := {}
const KEPT := 4
## Scratches the sampler wants rendered once their clip's render is here: [[key, path, callable]].
var _pending: Array = []
var _spin_player: AudioStreamPlayer3D
var _needle: AudioStreamPlayer3D
var _spin_node: Node3D
var _since_shown := 0.0
const SHOW_EVERY := 0.1
## How often a fetch under way is looked at.
var _fetch_looked := 0.0
const FETCH_EVERY := 0.25


func _init() -> void:
	name = "Platter"


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_spin_node = Node3D.new()
	_spin_node.name = "Spin"
	_spin_node.position = AXIS
	add_child(_spin_node)
	var turning := (load(DISC_MODEL) as PackedScene).instantiate() as Node3D
	turning.name = "Disc"
	_spin_node.add_child(turning)
	disc = Disc.new()
	disc.platter = self
	disc.name = "Grip"
	# The control's plane is the record's face, its +Z up, so a held ray stays on the record
	# (Interactor._plane_point).
	disc.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), AXIS + Vector3(0, DISC_TOP, 0))
	add_child(disc)
	slot = Slot.new()
	slot.platter = self
	slot.name = "Slot"
	slot.position = SLOT_POSE.origin
	add_child(slot)
	readout = Label3D.new()
	readout.name = "Readout"
	readout.pixel_size = 0.0002
	readout.font_size = READOUT_SIZE
	readout.outline_size = 0
	readout.modulate = Color(0.92, 0.88, 0.78)
	readout.shaded = false
	readout.double_sided = false
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout.position = READOUT_AT
	Lettering.range_to_legibility(readout)
	add_child(readout)
	var plaque := Stations.plaque(&"platter", PLAQUE_WIDTH)
	plaque.position = Vector3(0, PLAQUE_TOP - float(plaque.get_meta(&"plaque_tall")) * 0.5, PLAQUE_Z)
	add_child(plaque)
	scratch = Varispeed.new()
	scratch.name = "Scratch"
	add_child(scratch)
	_spin_player = Foley.emitter(Foley.spinback())
	_spin_player.name = "SpinBack"
	_spin_player.position = AXIS
	add_child(_spin_player)
	_needle = Foley.emitter(Foley.needle_drag(), -80.0)
	_needle.name = "Needle"
	_needle.position = AXIS
	add_child(_needle)
	turns = bars_at(DAW.state.position_seconds) if DAW.state != null else 0.0
	_show()


## The slot's pose in the platter's parent frame: what the room's holder is, laid by the studio.
func slot_in(frame: Transform3D) -> Transform3D:
	return frame * SLOT_POSE


func _is_authority() -> bool:
	return bool(authority.call()) if authority.is_valid() else true


# --- the song and the platter's angle --------------------------------------------------------

## Bars from the song's start at `seconds`: the turns the platter stands at there.
static func bars_at(seconds: float) -> float:
	return DAW.state.bar_at(maxf(seconds, 0.0)) if DAW.state != null else 0.0


## The song position the platter at `at_turns` stands for (never before the start).
static func seconds_of(at_turns: float) -> float:
	return DAW.state.bar_to_seconds(maxf(at_turns, 0.0) + 1.0) if DAW.state != null else 0.0


## How long a bar is at the song's start: how much of a cassette's clip a turn reads.
static func bar_seconds() -> float:
	if DAW.state == null:
		return 2.0
	return maxf(DAW.state.bar_to_seconds(2.0) - DAW.state.bar_to_seconds(1.0), 0.01)


## How fast the hand has the platter turning (turns a second, forwards positive), over the last
## SPEED_SPAN of its turning.
func speed() -> float:
	if _history.size() < 2:
		return 0.0
	var first: Array = _history[0]
	var last: Array = _history[-1]
	var span: float = last[0] - first[0]
	return (float(last[1]) - float(first[1])) / span if span > 0.0 else 0.0


# --- a hand on it -----------------------------------------------------------------------------

## A hand took hold of it. Bare: the song stops while held. With a cassette: its scratch begins.
func hold() -> void:
	var spun := _spinning
	if _spinning:
		# Caught mid-spin: it lands where it was going, and the hand has it from there.
		_land(false)
	_held = true
	_auto_left = 0.0
	if cassette != null:
		_wanted = clip_turns
		turns = clip_turns
		_history = [[_clock, turns]]
		if source == Source.READY:
			scratch.head = scratch.wrapped(clip_turns * bar_seconds())
			scratch.start(true)
		return
	if not _predicting():
		turns = bars_at(DAW.state.position_seconds)
	_wanted = turns
	_history = [[_clock, turns]]
	_last_seconds = seconds_of(turns)
	if spun:
		return
	was_playing = DAW.state.playing
	if was_playing:
		DAW.transport_stop()


## The hand has it at `to` turns now (from where it took it, however far round).
func turn_to(to: float) -> void:
	if _held:
		_wanted = to if cassette != null else maxf(to, 0.0)


## The hand let go: a scratch ends (and is the sampler's to catch), a flick backwards spins back,
## and otherwise the song plays on from where it is if it was playing.
func let_go() -> void:
	if not _held:
		return
	_held = false
	var v := speed()
	_needle.volume_db = -80.0
	if cassette != null:
		clip_turns = turns
		var path := scratch.path
		var moved := false
		if scratch.recording:
			for n in range(3, path.size(), 2):
				moved = moved or absf(path[n] - path[1]) > 0.001
		scratch.stop()
		if moved:
			scratched.emit(cassette, path)
		return
	if v <= -BACKSPIN:
		_spin_back(v)
		return
	_play_on()


## The playhead's last place sent (a guest's, when its turn comes), then playing again if it was.
func _play_on() -> void:
	if _is_authority():
		if was_playing:
			DAW.transport_play()
		was_playing = false
		return
	_resume_after_seek = was_playing
	was_playing = false
	if _want_seek < 0.0 and _resume_after_seek:
		_resume_after_seek = false
		DAW.transport_play()


## Let go spinning backwards at `v` turns a second: it spins free, slowing, the spin-back sound
## once, and lands on the bar line about the bars it spins back from where it was let go.
func _spin_back(v: float) -> void:
	var bars := maxi(1, roundi(v * v / (2.0 * SPIN_DRAG)))
	_spin_to = maxf(0.0, roundf(turns) - float(bars))
	var far := turns - _spin_to
	spins += 1
	if _spin_player.is_inside_tree():
		_spin_player.play()
	if far <= 0.001 or Ergonomics.current.motion_scale <= 0.0:
		_land()
		return
	_spinning = true
	_spin_speed = v
	_spin_drag = v * v / (2.0 * far)


## Where a spin-back stops: the playhead put there, and playing on if it was (`resume`).
func _land(resume := true) -> void:
	_spinning = false
	turns = _spin_to
	if _is_authority():
		DAW.seek(seconds_of(turns))
	else:
		_want_seek = seconds_of(turns)
		_since_seek = INF
		_send_seek_if_due()
	if resume:
		_play_on()


## A guest's seek, sent when a SEEK_HZ'th of a second has passed since the last.
func _send_seek_if_due() -> void:
	if _want_seek < 0.0 or _since_seek < 1.0 / SEEK_HZ - 0.0001:
		return
	DAW.seek(_want_seek)
	seeks_sent += 1
	_awaiting_seek = _want_seek
	_want_seek = -1.0
	_since_seek = 0.0
	if _resume_after_seek and not _held:
		_resume_after_seek = false
		DAW.transport_play()


## The wheel: the playhead a beat on or back a notch (a quarter beat fine); with a cassette in, a
## beat of its clip played forwards or back.
func nudge(notches: int, fine: bool) -> void:
	var beats := float(notches) * (0.25 if fine else 1.0)
	if cassette != null:
		if source != Source.READY or _held:
			return
		# A beat of it at its own speed: a turn a bar, so a bar's seconds for a turn.
		var beat_turns := beats / maxf(float(DAW.state.beats_per_bar), 1.0)
		_auto_left = absf(beat_turns)
		_auto_rate = signf(beat_turns) / bar_seconds()
		scratch.head = scratch.wrapped(clip_turns * bar_seconds())
		scratch.start(false)
		return
	var beat := DAW.state.beat_at(seconds_of(turns) if _predicting() else DAW.state.position_seconds) + beats
	var to := DAW.state.seconds_at_beat(maxf(beat, 0.0))
	DAW.seek(to)
	if not _is_authority():
		_awaiting_seek = to
		_since_seek = 0.0
		turns = bars_at(to)


# --- every frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


## A frame `delta` long: the slot looked at, the hand's turning scrubbed, sought or scratched, a
## spin-back turned on, or the label following the song.
func step(delta: float) -> void:
	_clock += delta
	_since_seek += delta
	_watch_slot()
	_collect()
	if _held:
		turns = _wanted
		_history.append([_clock, turns])
		while _history.size() > 2 and _clock - float(_history[0][0]) > SPEED_SPAN:
			_history.pop_front()
		if cassette != null:
			clip_turns = turns
			if source == Source.READY:
				if not scratch.is_playing():
					scratch.start(true)
				scratch.follow(clip_turns * bar_seconds(), delta)
		else:
			_scrub(delta)
	elif _spinning:
		_spin_speed = minf(0.0, _spin_speed + _spin_drag * delta)
		turns += _spin_speed * delta
		if turns <= _spin_to or _spin_speed >= 0.0:
			_land()
	elif cassette != null:
		if _auto_left > 0.0:
			var by := minf(absf(_auto_rate) * delta, _auto_left)
			_auto_left -= by
			clip_turns += by * signf(_auto_rate)
			scratch.follow(clip_turns * bar_seconds(), delta)
			if _auto_left <= 0.0:
				scratch.stop()
		turns = clip_turns
	elif not _predicting():
		turns = bars_at(DAW.state.position_seconds)
	_send_seek_if_due()
	_turn_the_label()
	_since_shown += delta
	if _since_shown >= SHOW_EVERY:
		_show()


## Whether a guest's platter, let go, still stands where it asked the song to go: a seek waiting
## for its turn, or one sent that the host's song is not yet within a beat of (and SEEK_WAIT has not
## passed). Then it shows its own word, not the host's old place.
func _predicting() -> bool:
	if _is_authority():
		_awaiting_seek = -1.0
		return false
	if _want_seek >= 0.0:
		return true
	if _awaiting_seek < 0.0:
		return false
	var beat := bar_seconds() / maxf(float(DAW.state.beats_per_bar), 1.0)
	if absf(DAW.state.position_seconds - _awaiting_seek) <= beat or _since_seek >= SEEK_WAIT:
		_awaiting_seek = -1.0
		return false
	return true


## The hand's turning, bare: the song scrubbed there on the host, a seek asked of it on a guest.
func _scrub(delta: float) -> void:
	var at := seconds_of(turns)
	var moving := not is_equal_approx(at, _last_seconds)
	var song_speed := (at - _last_seconds) / maxf(delta, 0.0001)
	_last_seconds = at
	if _is_authority():
		if moving:
			DAW.scrub(at, song_speed)
		return
	if moving:
		_want_seek = at
	var loud := clampf(absf(song_speed), 0.0, 1.5)
	_needle.volume_db = NEEDLE_DB + linear_to_db(maxf(loud, 0.001)) if loud > 0.02 else -80.0
	_needle.pitch_scale = clampf(0.6 + loud * 0.4, 0.6, 1.4)
	if loud > 0.02 and not _needle.playing and _needle.is_inside_tree():
		_needle.play()


## The disc turned to its angle: clockwise from above. With no motion wanted, a beat at a time.
func _turn_the_label() -> void:
	if _spin_node == null:
		return
	var shown := turns
	if Ergonomics.current.motion_scale <= 0.0 and not _held:
		var per := maxf(float(DAW.state.beats_per_bar), 1.0)
		shown = floorf(turns * per) / per
	_spin_node.rotation.y = -fposmod(shown, 1.0) * TAU


# --- the cassette in the slot ------------------------------------------------------------------

## The cassette in the room's slot here now: a new one's render begun, a gone one's tag cleared.
func _watch_slot() -> void:
	var now: CassetteItem = null
	if items != null and items.holders.has(HOLDER):
		now = items.in_slot(HOLDER, 0) as CassetteItem
	if now != null and not is_instance_valid(now):
		now = null
	if now == cassette:
		return
	if _held:
		let_go()
	if cassette != null and is_instance_valid(cassette):
		cassette.hearing = ""
	scratch.stop()
	cassette = now
	clip_turns = 0.0
	source = Source.NONE
	_source_key = ""
	if cassette != null:
		_load()
	_show()


## What the cassette in the slot is heard as: its clip's render, kept, or begun on a worker.
func _load() -> void:
	var clip := cassette.clip
	var key := key_of(clip)
	_source_key = key
	if _sources.has(key):
		_ready_with(key)
		return
	var item := MixWire.unpack_item(clip)
	if item == null:
		_mark(Source.EMPTY)
		return
	if not item.notes.is_empty() or not item.part.is_empty():
		_render(key, item)
		return
	if item.source.is_empty():
		_mark(Source.EMPTY)
		return
	var path := str(find_file.call(item.source)) if find_file.is_valid() else ""
	if path.is_empty():
		var waiting := bool(fetching.call(item.source)) if fetching.is_valid() else false
		_mark(Source.FETCHING if waiting else Source.MISSING)
		return
	var wav := AudioStreamWAV.load_from_file(path)
	var frames := Varispeed.frames_of(wav, item.source_offset, item.length, item.reversed)
	if frames.is_empty():
		_mark(Source.EMPTY)
		return
	_keep(key, [frames, wav.mix_rate])
	_ready_with(key)


## What a clip's render is kept by.
static func key_of(clip: Dictionary) -> String:
	return str(hash(var_to_bytes(clip)))


## A MIDI clip through the built-in instrument, or a demo part as the song plays it there, on a
## worker (EarCue's own renders), stereo frames at Varispeed.RATE or DemoSong.RATE.
func _render(key: String, item: MixState.ItemState) -> void:
	_mark(Source.RENDERING)
	if _tasks.has(key):
		return
	var result := [null]
	var sound := CassetteItem.sound_work(item, Varispeed.RATE)
	var work := func() -> void:
		result[0] = sound.call()
	_tasks[key] = [WorkerThreadPool.add_task(work, false, "render a cassette for the platter"), result]


## Renders done, kept; the slot's, used; a fetch arrived, loaded.
func _collect() -> void:
	for key: String in _tasks.keys():
		var running: Array = _tasks[key]
		if not WorkerThreadPool.is_task_completed(running[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(running[0])
		_tasks.erase(key)
		var made: Variant = running[1][0]
		if made is Array and not (made[0] as PackedVector2Array).is_empty():
			_keep(key, made)
	if cassette != null and source == Source.RENDERING and _sources.has(_source_key):
		_ready_with(_source_key)
	elif cassette != null and source == Source.RENDERING and not _tasks.has(_source_key):
		_mark(Source.EMPTY)
	elif cassette != null and source == Source.FETCHING and _clock - _fetch_looked >= FETCH_EVERY:
		_fetch_looked = _clock
		_load()
	for n in range(_pending.size() - 1, -1, -1):
		var p: Array = _pending[n]
		if _sources.has(p[0]):
			_pending.remove_at(n)
			(p[2] as Callable).call(rendered_scratch(p[0], p[1]))


func _keep(key: String, made: Array) -> void:
	_sources.erase(key)
	_sources[key] = made
	while _sources.size() > KEPT:
		_sources.erase(_sources.keys()[0])


func _ready_with(key: String) -> void:
	var made: Array = _sources[key]
	scratch.use(made[0], made[1], clip_turns * bar_seconds())
	_mark(Source.READY)


func _mark(s: Source) -> void:
	source = s
	if cassette != null and is_instance_valid(cassette):
		cassette.hearing = tag()
	_show()


## The cassette's tag on the platter: how its scratch is heard, at its figure, or why it is not.
func tag() -> String:
	match source:
		Source.READY:
			return "SCRATCH · MONITOR %d ms" % roundi(Varispeed.latency_seconds() * 1000.0)
		Source.RENDERING:
			return "RENDERING"
		Source.FETCHING:
			return "FETCHING"
		Source.MISSING:
			return "not on this machine"
		Source.EMPTY:
			return "nothing to scratch"
	return ""


## A scratch `path` of the clip kept as `key`, as it was heard: a 16-bit mono stream the sampler
## writes (Varispeed.render), or null where this machine has not that clip's render.
func rendered_scratch(key: String, path: PackedFloat32Array) -> AudioStreamWAV:
	if not _sources.has(key) or path.size() < 4:
		return null
	var made: Array = _sources[key]
	scratches_rendered += 1
	return Varispeed.wav_of(Varispeed.render(made[0], made[1], path))


## For the host's sampler: `cassette`'s scratch `path` rendered and given to `done` (an
## AudioStreamWAV, or null), now if its clip's render is here, once it is if it is being made.
func render_scratch(of: CassetteItem, path: PackedFloat32Array, done: Callable) -> void:
	var key := key_of(of.clip)
	if _sources.has(key) or of != cassette or source != Source.RENDERING:
		done.call(rendered_scratch(key, path))
		return
	_pending.append([key, path, done])


func _exit_tree() -> void:
	for running: Array in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(running[0])
	_tasks.clear()


# --- what it says -----------------------------------------------------------------------------

## The lettering along the plinth's front, in words: what the platter is doing now.
func readout_text() -> String:
	if cassette != null:
		var what := cassette.clip_name()
		match source:
			Source.READY:
				return "SCRATCH · %s" % what
			Source.RENDERING:
				return "RENDERING · %s" % what
			Source.FETCHING:
				return "FETCHING · %s" % what
		return "CANNOT SCRATCH · %s" % what
	if _spinning:
		return "SPIN BACK"
	if _held:
		return "HELD · STOPPED · BAR %s" % DAW.state.bar_beat(seconds_of(turns)).get_slice(".", 0)
	var at := seconds_of(turns) if _predicting() else DAW.state.position_seconds
	return "BAR %s · %s" % [DAW.state.bar_beat(at).get_slice(".", 0),
			"PLAYING" if DAW.state.playing else "STOPPED"]


## What a turn of it does on this machine's DAW, for its card: heard where it is turned, a quiet
## seek, or a guest's seeks asked of the host. `can` is DAW.can(SCRUB) on the host; `reaper`
## whether the DAW is Reaper.
static func scrub_words(host: bool, can: bool, reaper := false) -> String:
	if not host:
		return "your turns move the host's playhead, %d seeks a second at most; the needle you hear is your own" % roundi(SEEK_HZ)
	if not can:
		return "quiet seeks: this DAW cannot scrub, so the song is not heard turning"
	if reaper:
		return "Reaper scrubs the song where you turn it"
	return "the built-in engine plays the song where you turn it"


## The card's line: where the song is and what a turn does, or the cassette's scratch and its figure.
func card_text() -> String:
	if cassette != null:
		if source == Source.READY:
			return "scratching %s, in your ears alone: on MONITOR through Godot, %d ms" % [cassette.clip_name(),
					roundi(Varispeed.latency_seconds() * 1000.0)]
		return "%s: %s" % [cassette.clip_name(), tag()]
	return "bar %s · %s" % [DAW.state.bar_beat(DAW.state.position_seconds),
			scrub_words(_is_authority(), DAW.can(DAWBackend.Capability.SCRUB), DAW.backend is ReaperBackend)]


func _show() -> void:
	_since_shown = 0.0
	if readout == null:
		return
	var said := readout_text()
	if said != readout.text:
		readout.text = said
		Lettering.fit(readout, READOUT_WIDTH, READOUT_SIZE, 60)


## The record's face: taken hold of and turned, a mouse or a fingertip by going round its middle,
## a controller by twisting. A hand's own, but one at a time across the room: the song has one
## playhead.
class Disc extends ControlAffordance:
	var platter: Platter
	var _grab_twist := NAN
	var _grab_angle := 0.0
	var _from := 0.0
	var _turned := 0.0

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = RADIUS + 0.006
		cylinder.height = 0.03
		shape.shape = cylinder
		# The cylinder's axis is its Y; the control's is its Z, up out of the record.
		shape.rotation.x = PI * 0.5
		add_child(shape)

	func network_key() -> String:
		return "PLATTER"

	func _default_title() -> String:
		return "PLATTER  SCRATCH" if platter != null and platter.cassette != null else "PLATTER  PLAYHEAD"

	func _default_readout() -> String:
		return platter.card_text() if platter != null else ""

	func hint() -> String:
		if platter != null and platter.cassette != null:
			return "drag round to scratch it, forwards or back, a turn a bar · wheel: a beat of it · take the cassette out to scrub the song again"
		return "drag round to scrub, a turn a bar · hold still to stop, let go to play on · flick it back fast and let go to spin back · wheel: a beat · click a cassette into the slot to scratch it"

	func _on_grab_begin(at: Vector3) -> void:
		if platter == null:
			return
		platter.hold()
		_from = platter.turns
		_turned = 0.0
		_grab_twist = NAN
		_grab_angle = _angle_at(at)
		if held_by is Interactor and not (held_by as Interactor).touches_directly():
			_grab_twist = (held_by as Interactor).twist()

	## Turned by turning the hand, or by going round the middle, however many times round.
	func _on_grab_move(at: Vector3) -> void:
		if platter == null:
			return
		if not is_nan(_grab_twist):
			_turned = (held_by as Interactor).twist() - _grab_twist
		else:
			var angle := _angle_at(at)
			_turned += wrapf(angle - _grab_angle, -PI, PI)
			_grab_angle = angle
		platter.turn_to(_from + _turned / TAU)

	func _on_grab_end() -> void:
		if platter != null:
			platter.let_go()

	## Where `at` is round the middle, clockwise from the back, as somebody looking down sees it.
	func _angle_at(at: Vector3) -> float:
		var p := to_local(at)
		return atan2(p.x, p.y)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if platter == null:
			return false
		platter.nudge(notches, fine)
		return true


## The cassette's slot: a click with a cassette in the hand stands it there; a cassette standing in
## it is taken by clicking the cassette itself.
class Slot extends ControlAffordance:
	var platter: Platter

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.11, 0.03, 0.03)
		shape.shape = box
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "PLATTER  SLOT"

	func _default_readout() -> String:
		if platter == null or platter.cassette == null:
			return "empty: a cassette stood here is scratched by turning the platter"
		return "%s: %s" % [platter.cassette.clip_name(), platter.tag()]

	func hint() -> String:
		return "with a cassette in your hand, click to stand it here and scratch it · click the cassette to take it out"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		var item := CassetteRack.made_in(hand)
		if item == null or platter == null or platter.items == null:
			return
		platter.items.slot_item(item, HOLDER, 0)
