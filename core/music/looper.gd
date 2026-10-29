class_name Looper
extends Node3D

## A looper, by hand (docs/spatial_loop.md part two, slice 45, idea #21, its first half): a pad on a
## stand at the drum riser's front corner. Slap the pad to loop. Recording starts at the next bar,
## after that bar's count shown as dots on its screen, and lasts LENGTH bars (1, 2, 4 or 8, its
## LENGTH key's), or the loop range's bars where a loop is set. It takes everything the player who
## slapped it plays: their keys from every source (GuestMidi.sends, the keytar, the harp, the
## fingertips, a cable, a hardware keyboard) and their hits (the studio's `hit`, every instrument
## they shake or strike). With the transport stopped a slap starts it (`answer`: transport_play) from
## the start of the bar the playhead is in, and that first bar played is the count. Slap again while
## the loop plays and another layer is stacked from the loop's start, the pass after this one.
##
## Who is recording, from which bar and for how long is the room's row `looper` [peer, from_bar,
## bars] (`row`; [] for nobody), asked of the host and predicted (Session.ROOM_VERBS), so every pad
## shows it, and a slap by somebody else while it is set is refused with `ADA is looping`
## (`refusal`). Anyone can use the looper, one at a time.
##
## Each layer is a MIDI item on a track of its own, named for its player (`ADA LOOP 1`, `ADA LOOP 2`),
## in a LOOPER folder at the end of the project (`write_layer`: add_track, move_track into the folder,
## insert_midi_take), so the hits in it play back as hits (slice 16: channel 9 rung by ItemVoices) and
## the keys as notes. The first layer, made with no loop set, sets the transport's loop range to its
## span and turns looping on as it is armed (`answer`), so the playhead goes round from its last bar to
## its first and the player hears what they played at once.
##
## A layer is taken down on the machine of whoever plays it, by the song position they heard
## (`follow`, `key`, `hit`), as their keys' takes are (GuestMidi), and is written on the host: the
## host's own at once, a guest's sent whole as the room's `looper_layer` [start, end, notes], which
## the host writes as that guest's tracks (`write_layer`, DAW.on_behalf_of).
##
## The screen says what it is doing in words and by shape, never by colour alone (`display`): REC
## beside a round mark, PLAY beside a triangle, COUNT with the beats left to the first bar as large
## dots, READY beside a square; the bar it is on and of how many; and the beat, as a row of dots
## where the beats gone by this bar are large. Nothing on it moves but by a beat at a time, so it is
## the same at Ergonomics motion 0.
##
## Every layer it has made is a ring on a post over its stand (LooperRings, slice 46, `rings`): a grab
## mutes it, a pull deletes it, and the LAYERS list over the screen does the same at a desk.
##
## The pad is a fixed instrument (InstrumentItem with `Item.fixed`, `Pad`), struck through Strike by
## a hand or a controller (never a foot) and by a click at a desk (`struck_by`). It is the looper's
## own, not one of the room's items: a slap is not a hit to record or to send, only to loop.
##
## Its numbers are tools/blender/looper.py's, which builds the stand and the case. Origin the middle
## of the stand's feet, on the riser's top; its front (+Z) toward the ring of drums' front.

## The station, the room's row and the verbs that ask for it (Session.ROOM_VERBS).
const STATION := &"looper"
const VERB := &"looper"
const LAYER_VERB := &"looper_layer"
## The folder every layer goes in, at the end of the project.
const FOLDER := "LOOPER"
## The lengths LENGTH steps through, in bars, and the one it starts on.
const LENGTHS: Array[int] = [1, 2, 4, 8]
const LENGTH_DEFAULT := 2
## The most bars a layer may be, whatever a loop range says.
const MOST_BARS := 32
## How early (s) before a layer's first bar a note may be played and still be its downbeat, and how
## late after its last bar a note on is the loop's top again rather than nothing.
const EARLY := 0.08
## A jump back of more than this (s) is the loop going round, or a seek: a count arrives, a layer ends.
const WRAP := 0.25
## How near a bar line the playhead has to be to be on it (s).
const ON_THE_LINE := 0.0005

const MODEL := "res://assets/models/looper.glb"
## The stand: its feet's radius on the riser (its walker footprint's half, Venue.looper_solid) and
## how high the case's deck is over them, tipped toward whoever stands in front by TILT (radians).
const STAND_FOOT := 0.2
const PAD_Y := 0.72
const TILT := 0.4
## The case, in the deck's own frame (`deck_frame`: the deck's top at y 0, x across, z toward the
## front): half its width, its thickness and half its depth.
const CASE := Vector3(0.21, 0.05, 0.16)
## The pad set into the deck: half its width and depth, how far in front of the deck's middle it is,
## and how proud of the deck it stands.
const PAD_HALF := Vector2(0.15, 0.08)
const PAD_Z := 0.05
const PAD_TALL := 0.012
## The screen and the LENGTH key behind the pad: hinged up off the deck along HINGE_Z, leant back
## SCREEN_LEAN (radians) from standing straight up off it, each its width and height, and where across
## its middle is.
const HINGE_Z := -0.07
const SCREEN_LEAN := 0.6
const SCREEN := Vector2(0.26, 0.085)
const SCREEN_X := -0.065
const KEY := Vector2(0.11, 0.085)
const KEY_X := 0.135
## The top of it all, in its frame: the screen's top edge (for Stations' frame).
const TOP := 0.83
## The LAYERS list's top edge's middle over the screen (LooperRings.list_top), the top of the keys a
## desk plays here (slice 46). The rings stand over it, on their post, and the last of them is
## Stations' frame's top (LooperRings.STACK_TOP).
const LIST_TOP := Vector3(0, 0.9365, -0.1824)
## Its plaque, on an arm off the stand's pole (PLAQUE_ARM, its height): out in front of the case and
## below it, leant back PLAQUE_TILT (radians) like a lectern's so it reads from above. All of it is
## in front of the case's front face, so nothing of the looper stands between it and a player's eye
## over the pad, at a desk or in a headset. PLAQUE is its
## lettering's middle; PLAQUE_WIDTH how wide it is (its hands line, with the rings', in seven lines);
## PLAQUE_FOOT its plate's lowest point opened, for Stations' frame.
const PLAQUE := Vector3(0, 0.3818, 0.2569)
const PLAQUE_TILT := 0.5
const PLAQUE_WIDTH := 0.5
const PLAQUE_FOOT := Vector3(0, 0.112, 0.402)
const PLAQUE_ARM := 0.47
## The most beats a bar shows as dots.
const MOST_DOTS := 12
## The screen's lettering: its word (REC, PLAY) and the line under it, as Label3D font sizes at
## 0.2 mm a pixel: about 17 mm and 8 mm capitals.
const WORD_SIZE := 120
const LINE_SIZE := 60
const DOT := 0.0065
const DOT_SMALL := 0.0028

enum Phase { IDLE, COUNT, REC, DONE }

## A hand here slapped the pad: for the studio to arm, or ask to (`plan`, `answer`).
signal slapped()
## LENGTH was stepped here, to `bars`.
signal length_changed(bars: int)
## This player's layer is taken down, from `start` to `end` (song seconds), its notes [on, off,
## pitch, velocity, channel] in song seconds: for the studio to write, or send to the host.
signal layer_done(start: float, end: float, notes: Array)
## This player's count or recording was cut short by the transport stopping: for the studio to clear
## the row, or ask to.
signal called_off()

## The room's row `looper`: [peer, from_bar (1-based; -1 while a guest's ask to start the transport
## is on its way), bars], or [] for nobody.
var row: Array = []:
	set(v):
		var was := row
		row = v.duplicate()
		_row_changed(was)
## How many bars this player's next loop is (LENGTH), where no loop range is set.
var length := LENGTH_DEFAULT:
	set(v):
		length = v if LENGTHS.has(v) else LENGTH_DEFAULT
		_show_key()
## Where the song is, here: {seconds, playing, valid}. GuestMidi.heard by default; the suite gives
## its own.
var heard_source: Callable = Callable()
## This machine's player (Session.local_peer_id by default) and anyone's name, for the screen.
var local_peer: Callable = Callable()
var name_of: Callable = Callable()
## Where the row is now, here.
var phase := Phase.IDLE
var pad: Pad = null
var length_key: LengthKey = null
## Its layers' rings and the LAYERS list (LooperRings).
var rings: LooperRings = null
## How many notes the running layer has taken, for the screen and the suite.
var taken := 0

var _take: MidiTake = null
## Begun on a note played a hair before the layer's first bar, whose arrival has not been heard yet.
var _early := false
## The song position the last frame heard, or NAN while it did not play.
var _was := NAN
## Whether the transport has been heard playing since the row was set: a stop after that calls it off.
var _seen_playing := false
var _word: Label3D = null
var _line: Label3D = null
var _marks := {}
var _dots: Array[MeshInstance3D] = []
var _shown := {}


func _init() -> void:
	name = "Looper"


func _ready() -> void:
	var scene := load(MODEL) as PackedScene
	if scene != null:
		var model := scene.instantiate() as Node3D
		model.name = "Model"
		add_child(model)
	pad = Pad.new()
	pad.looper = self
	pad.name = "Pad"
	pad.transform = deck_frame() * Transform3D(Basis.IDENTITY, Vector3(0, 0, PAD_Z))
	pad.home = pad.transform
	pad.played.connect(_on_pad_played)
	add_child(pad)
	_build_screen()
	length_key = LengthKey.new()
	length_key.looper = self
	length_key.name = "Length"
	length_key.transform = panel_frame(KEY_X, KEY)
	add_child(length_key)
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	plaque.transform = Transform3D(Basis(Vector3.RIGHT, -PLAQUE_TILT), PLAQUE)
	add_child(plaque)
	add_child(_plaque_arm())
	rings = LooperRings.new()
	rings.looper = self
	add_child(rings)
	_show_key()
	_show(heard())


# --- where things are -------------------------------------------------------------------------

## A slim steel rod out of the pole at PLAQUE_ARM to the plaque's back, so it is held rather than
## hanging in the air. Named "PlaqueArm".
static func _plaque_arm() -> MeshInstance3D:
	var arm := MeshInstance3D.new()
	arm.name = "PlaqueArm"
	var rod := CylinderMesh.new()
	rod.top_radius = 0.008
	rod.bottom_radius = 0.008
	# From the pole's middle to where the plate's back crosses the arm's height.
	var back := Basis(Vector3.RIGHT, -PLAQUE_TILT)
	var up := back * Vector3.UP
	var out := back * Vector3.BACK
	var along := (PLAQUE_ARM - PLAQUE.y + out.y * 0.008) / up.y
	var reach := PLAQUE.z + up.z * along - out.z * 0.008
	rod.height = reach
	arm.mesh = rod
	arm.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, PLAQUE_ARM, reach * 0.5))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.4
	metal.metallic = 0.8
	arm.material_override = metal
	return arm


## The deck's frame, in the looper's: its top's middle PAD_Y over the feet, tipped toward the front.
static func deck_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, TILT), Vector3(0, PAD_Y, 0))


## A panel hinged up off the deck behind the pad (the screen, the LENGTH key), `size` big, its middle
## `x` across: its frame in the looper's, +Z out of its face toward whoever stands in front, +Y up it.
static func panel_frame(x: float, size: Vector2) -> Transform3D:
	var lean := Basis(Vector3.RIGHT, -PI * 0.5 + SCREEN_LEAN)
	var up := lean * Vector3.UP
	var out := lean * Vector3.BACK
	return deck_frame() * Transform3D(lean, Vector3(x, 0, HINGE_Z) + up * size.y * 0.5 + out * 0.003)


## Where a headset player's hand meets the pad, in the looper's frame: its face's middle.
static func pad_point() -> Vector3:
	return deck_frame() * Vector3(0, PAD_TALL, PAD_Z)


# --- the row: what a slap asks for, and the host's answer --------------------------------------

## Whether `state` has a loop to stack on: looping, round a range.
static func loop_set(state: MixState) -> bool:
	return state != null and state.looping and state.has_loop_range()


## The loop range as bars: [its first bar (1-based), how many], the nearest bar lines to its ends.
static func loop_bars(state: MixState) -> Array:
	var from := roundi(state.bar_at(state.loop_start)) + 1
	var to := roundi(state.bar_at(state.loop_end)) + 1
	return [maxi(from, 1), clampi(to - from, 1, MOST_BARS)]


## The span a row records, [start, end] in song seconds, or [] while it has no bar yet.
static func span_of(given: Array, state: MixState) -> Array:
	if given.size() < 3 or int(given[1]) < 1 or state == null:
		return []
	return [state.bar_to_seconds(int(given[1])), state.bar_to_seconds(int(given[1]) + int(given[2]))]


## What a slap now asks for, [from_bar, bars], from what is heard here (`h`: {seconds, playing,
## valid}): with a loop set, the loop's own bars from its start; with none, the next bar for `bars`
## (LENGTH). From -1 while the transport is stopped: the host starts it, and picks the bar.
static func plan(state: MixState, h: Dictionary, bars: int) -> Array:
	var playing: bool = h.get("valid", false) and h.get("playing", false)
	if loop_set(state):
		var looped := loop_bars(state)
		return [looped[0] if playing else -1, looped[1]]
	if not playing:
		return [-1, bars]
	return [floori(state.bar_at(float(h.get("seconds", 0.0)))) + 2, bars]


## Why `peer` may not slap the looper now, in words, or "": somebody else's row (`row`) is set.
## `names` (a peer -> String) names them.
static func refusal(given: Array, peer: int, names: Callable) -> String:
	if given.is_empty() or int(given[0]) == peer:
		return ""
	var who := str(names.call(int(given[0]))) if names.is_valid() else "someone"
	return looping_text(who)


static func looping_text(who: String) -> String:
	return "%s is looping" % who


## Host: `peer`'s ask (the room's `looper` [from_bar, bars]) against the room's row `given`. Returns
## {"row": the row now, "said": what to tell them, "refused": whether it was}:
## - somebody else's row is set: refused, `ADA is looping`;
## - `bars` 0: their own row cleared (a count called off, a layer with nothing in it);
## - otherwise armed. With a loop set, its bars from its start (the pass after this one). With none,
##   from the bar they asked for (the next one, as they hear it; the host's own next where theirs has
##   gone by here) for `bars` bars, and that span is now the loop range, looping. With the transport
##   stopped (`from_bar` -1, or not playing here), it is started from the start of the bar the
##   playhead is in (with a loop set, the bar before it), and the first bar played is the count.
## Every DAW write is the host's to make (DAW: on the host, at once).
static func answer(given: Array, from_bar: int, bars: int, peer: int, names := Callable()) -> Dictionary:
	var why := refusal(given, peer, names)
	if why != "":
		return {"row": given, "said": why + ".", "refused": true}
	if bars <= 0:
		return {"row": [], "said": "", "refused": false}
	if not given.is_empty():
		return {"row": given, "said": "", "refused": false}
	var state := DAW.state
	bars = clampi(bars, 1, MOST_BARS)
	var looped := loop_set(state)
	var from := from_bar
	if looped:
		var lb := loop_bars(state)
		from = int(lb[0])
		bars = int(lb[1])
	var here := floori(state.bar_at(state.position_seconds)) + 1
	if from_bar < 1 or not state.playing:
		if looped:
			DAW.seek(state.bar_to_seconds(from - 1) if from > 1 else state.loop_start)
		else:
			DAW.seek(state.bar_to_seconds(here))
			from = here + 1
		DAW.transport_play()
	elif not looped and (from < here or from > here + 2):
		from = here + 1
	if not looped:
		DAW.set_loop_range(state.bar_to_seconds(from), state.bar_to_seconds(from + bars))
		DAW.set_looping(true)
	return {"row": [peer, from, bars], "said": "", "refused": false}


# --- the layers' tracks -----------------------------------------------------------------------

## How many tracks the project has: the bank's, or Reaper's whole project's where it is bigger.
static func track_count(state: MixState) -> int:
	return maxi(state.project_track_count, state.track_indices().size())


## The LOOPER folder's track, or 0 for none yet.
static func folder_of(state: MixState) -> int:
	for i in state.track_indices():
		if (state.tracks[i] as MixState.TrackState).name == FOLDER:
			return int(i)
	return 0


## The last track in folder `folder` (the folder itself while it has none).
static func folder_end(state: MixState, folder: int) -> int:
	var level := state.folder_level(folder)
	var last := folder
	if (state.tracks[folder] as MixState.TrackState).folder_depth <= 0:
		return last
	for i in state.track_indices():
		if int(i) <= folder:
			continue
		if state.folder_level(int(i)) <= level:
			break
		last = int(i)
	return last


## A layer's track's name: its player's, upper case, and its number: `ADA LOOP 2`.
static func layer_name(player: String, number: int) -> String:
	return "%s LOOP %d" % [player.to_upper(), number]


## The number `player`'s next layer takes: one past the highest of theirs in the project.
static func next_number(state: MixState, player: String) -> int:
	var prefix := "%s LOOP " % player.to_upper()
	var most := 0
	for t: MixState.TrackState in state.tracks.values():
		if t.name.begins_with(prefix) and t.name.substr(prefix.length()).is_valid_int():
			most = maxi(most, int(t.name.substr(prefix.length())))
	return most + 1


## The track named `track_name`, or 0.
static func track_named(state: MixState, track_name: String) -> int:
	for i in state.track_indices():
		if (state.tracks[i] as MixState.TrackState).name == track_name:
			return int(i)
	return 0


## Of a layer's `notes` [on, off, pitch, velocity, channel] (as a guest sent them), those that begin
## inside `span` [start, end], each let go by its end: so the host's track holds only what was
## played in the row's own bars, whatever span the layer came with.
static func inside(notes: Array, span: Array) -> Array:
	var out: Array = []
	if span.size() < 2:
		return out
	var start: float = span[0]
	var end: float = span[1]
	for n: Variant in notes:
		if not n is Array or (n as Array).size() < 5:
			continue
		var on := float(n[0])
		if is_nan(on) or on < start - ON_THE_LINE or on >= end:
			continue
		var kept: Array = (n as Array).duplicate()
		kept[0] = maxf(on, start)
		kept[1] = clampf(float(n[1]), float(kept[0]), end)
		out.append(kept)
	return out


## Host: `player`'s layer onto a track of its own in the LOOPER folder (made at the end of the project
## the first time): `ADA LOOP n`, its notes one MIDI item from `start` to `end`. Returns {"track",
## "name", "number"}; "track" 0 where the backend has not shown the new track yet (Reaper's, with the
## project wider than its bank).
static func write_layer(player: String, start: float, end: float, notes: Array) -> Dictionary:
	var state := DAW.state
	var folder := folder_of(state)
	if folder == 0:
		DAW.add_track(track_count(state) + 1, FOLDER)
		folder = folder_of(state)
	var number := next_number(state, player)
	var named := layer_name(player, number)
	if folder == 0:
		return {"track": 0, "name": named, "number": number}
	var at := folder_end(state, folder) + 1
	DAW.add_track(at, named)
	DAW.move_track(at, at, folder)
	var index := track_named(state, named)
	if index > 0:
		DAW.insert_midi_take(index, start, end, notes, named)
	return {"track": index, "name": named, "number": number}


# --- following the song -------------------------------------------------------------------------

func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "valid": false}


func _me() -> int:
	return int(local_peer.call()) if local_peer.is_valid() else Session.local_peer_id


## Whether the row is this player's.
func mine() -> bool:
	return not row.is_empty() and int(row[0]) == _me()


func _who(peer: int) -> String:
	if name_of.is_valid():
		return str(name_of.call(peer))
	return Session.name_of(peer)


## Where `other` (the looper of the venue this one replaces) was with the same row: its count or its
## layer under way, carried on here.
func take_over(other: Looper) -> void:
	if other == null or other.row != row:
		return
	phase = other.phase
	_take = other._take
	_early = other._early
	_was = other._was
	_seen_playing = other._seen_playing
	taken = other.taken


func _row_changed(was: Array) -> void:
	if row.is_empty():
		phase = Phase.IDLE
		_take = null
		_early = false
	elif phase == Phase.IDLE or phase == Phase.DONE or was.is_empty() or int(was[0]) != int(row[0]):
		phase = Phase.COUNT
		_take = null
		_early = false
		_seen_playing = false
		taken = 0
	if is_inside_tree():
		_show(heard())


func _process(_delta: float) -> void:
	follow(heard())


## One frame of the song as heard (`h`): a count that arrives at its first bar (the playhead crossing
## it, or the loop going round to it) begins the layer; a layer that reaches its last bar's end (or
## goes round) is done, and this player's is said (`layer_done`). The transport stopping, once heard
## playing, calls it off. A count first heard playing a moment past its first bar (less than WRAP:
## the frame after a stall, or the song just started) begins at once, not a whole pass later.
func follow(h: Dictionary) -> void:
	var now := float(h.get("seconds", 0.0))
	var playing: bool = h.get("valid", false) and h.get("playing", false)
	if not row.is_empty() and (phase == Phase.COUNT or phase == Phase.REC):
		if playing:
			_seen_playing = true
		elif _seen_playing:
			_stopped()
		var span := span_of(row, DAW.state)
		if playing and phase == Phase.COUNT and not span.is_empty() and is_nan(_was) \
				and now >= float(span[0]) - ON_THE_LINE and now < float(span[0]) + WRAP:
			_begin(span)
		elif playing and not span.is_empty() and not is_nan(_was):
			if phase == Phase.COUNT and _arrives(_was, now, span):
				_begin(span)
			elif phase == Phase.REC and _early:
				if _arrives(_was, now, span):
					_early = false
			elif phase == Phase.REC and _ends(_was, now, span):
				_end(span)
	_was = now if playing else NAN
	_show(h)


## Whether the song going from `was` to `now` arrives at `span`'s first bar: across it, or round the
## loop back to it.
static func _arrives(was: float, now: float, span: Array) -> bool:
	var s: float = span[0]
	var e: float = span[1]
	if now < s - ON_THE_LINE or now >= e:
		return false
	return was < s - ON_THE_LINE or now < was - WRAP


## Whether it reaches `span`'s end: past its last bar, or round the loop (or back by a seek).
static func _ends(was: float, now: float, span: Array) -> bool:
	return now >= float(span[1]) - ON_THE_LINE or now < was - WRAP


func _begin(span: Array) -> void:
	phase = Phase.REC
	if mine() and _take == null:
		_take = MidiTake.new()
		_take.begin(span[0])


func _end(span: Array) -> void:
	phase = Phase.DONE
	_early = false
	if not mine():
		return
	var take := _take
	_take = null
	if take == null:
		take = MidiTake.new()
		take.begin(span[0])
	take.reach(span[1])
	var done := take.finish(span[1])
	layer_done.emit(float(span[0]), float(span[1]), done["notes"])


func _stopped() -> void:
	phase = Phase.DONE
	_take = null
	_early = false
	if mine():
		called_off.emit()


# --- what this player plays -------------------------------------------------------------------

## The running layer for something this player played to song position `song`: the layer under way,
## or one begun now for a note a hair before its first bar that its arrival has not caught up with
## (`_early`). Null for none.
func _taking(song: float) -> MidiTake:
	if not mine() or song < 0.0:
		return null
	if phase == Phase.REC:
		return _take
	if phase != Phase.COUNT:
		return null
	var span := span_of(row, DAW.state)
	if span.is_empty():
		return null
	var s: float = span[0]
	var e: float = span[1]
	var before: bool = is_nan(_was) or _was < s
	if (before and song >= s - EARLY and song < e) or (not before and song >= e - EARLY):
		_begin(span)
		_early = true
		return _take
	return null


## Where a note on played to song position `song` lands in the layer: inside it, where it was played;
## a hair before its first bar (on the count, or the pass before), on that bar; a hair past its last
## bar, round at the loop's top again; NAN for outside it.
func _placed(song: float) -> float:
	var span := span_of(row, DAW.state)
	if span.is_empty():
		return NAN
	var s: float = span[0]
	var e: float = span[1]
	if _early and (is_nan(_was) or _was >= s) and song >= e - EARLY:
		return s + maxf(song - e, 0.0)
	if song >= e:
		return s + (song - e) if song - e < EARLY else NAN
	if song < s:
		return s if song >= s - EARLY else NAN
	return song


## A key of this player's, as GuestMidi sends it (`sends`): `kind` Session.Note's, at song position
## `song` (-1 while the song was not playing), on `channel`. Into the layer while it records.
func key(kind: int, pitch: int, velocity: int, song: float, channel := 0) -> void:
	# Only a key going down begins a layer a hair early: a let-go or the pedal goes into one under way.
	if kind != Session.Note.ON and phase != Phase.REC:
		return
	var take := _taking(song)
	var span := span_of(row, DAW.state)
	if take == null or span.is_empty():
		return
	match kind:
		Session.Note.ON:
			var at := _placed(song)
			if is_nan(at) or take.notes.size() >= MidiTake.MAX_NOTES:
				return
			take.note_on(pitch, velocity, channel, at)
			taken += 1
		Session.Note.OFF:
			take.note_off(pitch, channel, clampf(song, float(span[0]), float(span[1])))
		Session.Note.PEDAL_DOWN, Session.Note.PEDAL_UP:
			take.sustain(kind == Session.Note.PEDAL_DOWN, channel, clampf(song, float(span[0]), float(span[1])))
	take.reach(clampf(song, float(span[0]), float(span[1])))


## A hit of this player's (the studio's, from every instrument they play): `item` at `velocity`,
## played to song position `at`, struck on `zone`. Into the layer while it records, as HitRecorder
## would take it down: its zone's note on its channel, as long as it says, snapped gently where this
## player snaps hand percussion.
func hit(item: InstrumentItem, velocity: int, at: float, zone := &"") -> void:
	if item == null or item == pad:
		return
	var when := at
	if HitRecorder.snaps() and not item.pitched():
		when = HitRecorder.snapped_at(at, DAW.state)
	var take := _taking(when)
	if take == null:
		return
	var placed := _placed(when)
	if is_nan(placed) or take.notes.size() >= MidiTake.MAX_NOTES:
		return
	var note := item.zone_note(zone, at)
	take.note_on(note, clampi(velocity, 1, 127), item.channel(), placed)
	take.note_off(note, item.channel(), placed + item.note_seconds())
	take.reach(placed + item.note_seconds())
	taken += 1


func _on_pad_played(_velocity: int, _struck: bool, _at: float, _zone: StringName) -> void:
	slapped.emit()


# --- LENGTH -------------------------------------------------------------------------------------

## LENGTH stepped `way` (1 on, -1 back) through LENGTHS, round: said, for the studio to keep.
func step_length(way: int) -> void:
	var at := LENGTHS.find(length)
	length = LENGTHS[posmod(at + signi(way), LENGTHS.size())]
	length_changed.emit(length)


## What LENGTH says: its bars, or the loop's where a loop range is set.
func length_text() -> String:
	if loop_set(DAW.state):
		var looped := loop_bars(DAW.state)
		return "THE LOOP\n%d BAR%s" % [looped[1], "" if looped[1] == 1 else "S"]
	return "LENGTH\n%d BAR%s" % [length, "" if length == 1 else "S"]


func _show_key() -> void:
	if length_key == null or length_key.legend == null:
		return
	var said := length_text()
	if length_key.legend.text != said:
		length_key.legend.text = said


# --- the screen -------------------------------------------------------------------------------

## What the screen shows for what is heard (`h`): {"word": REC, COUNT, PLAY or READY; "mark": its
## shape, &"rec" (round), &"play" (a triangle), &"count" (none: the dots are the count) or &"ready" (a
## square); "line": who and which bar, in words; "said": the same as a sentence, for the pad's card;
## "dots": how many beats a bar has (at most MOST_DOTS); "big": which of them are large}. While
## counting, the large dots are the beats left before the first bar; otherwise the beats of this bar
## gone by, the one now among them.
func display(h: Dictionary) -> Dictionary:
	var state := DAW.state
	var now := float(h.get("seconds", 0.0))
	var playing: bool = h.get("valid", false) and h.get("playing", false)
	var out := {"word": "READY", "mark": &"ready", "line": "", "said": "", "dots": 0, "big": []}
	if state == null:
		return out
	var beat := state.beat_at(maxf(now, 0.0))
	var meter := state.meter()
	var per := clampi(meter.signature_at(beat).x, 1, MOST_DOTS)
	var at: Array = meter.position(beat)
	out["dots"] = per
	var gone: Array = []
	for n in per:
		gone.append(playing and n < int(at[1]))
	out["big"] = gone
	var span := span_of(row, state)
	var who := _who(int(row[0])).to_upper() if not row.is_empty() else ""
	if not row.is_empty() and phase == Phase.COUNT:
		out["word"] = "COUNT"
		out["mark"] = &"count"
		if span.is_empty():
			out["line"] = "%s · STARTING" % who
			out["said"] = "COUNT: %s, starting the song" % who
			out["big"] = []
			return out
		var until: float = span[0] if now < float(span[0]) else span[1]
		var left := ceili((state.beat_at(until) - beat) / meter.count_beats(beat) - 0.0001) if playing else per
		var big: Array = []
		for n in per:
			big.append(n < clampi(left, 0, per))
		out["big"] = big
		out["line"] = "%s · FROM BAR %d" % [who, int(row[1])]
		out["said"] = "COUNT: %s, recording from bar %d for %d bar%s" % [who, int(row[1]), int(row[2]),
				"" if int(row[2]) == 1 else "s"]
		return out
	if not row.is_empty() and phase == Phase.REC:
		out["word"] = "REC"
		out["mark"] = &"rec"
		var into := clampi(floori(state.bar_at(now)) + 1 - int(row[1]) + 1, 1, int(row[2]))
		out["line"] = "%s · BAR %d OF %d" % [who, into, int(row[2])]
		out["said"] = "REC: %s, bar %d of %d" % [who, into, int(row[2])]
		return out
	if loop_set(state) and playing:
		var looped := loop_bars(state)
		var into := clampi(floori(state.bar_at(now)) + 1 - int(looped[0]) + 1, 1, int(looped[1]))
		out["word"] = "PLAY"
		out["mark"] = &"play"
		out["line"] = "LOOP · BAR %d OF %d" % [into, int(looped[1])]
		out["said"] = "PLAY: the loop, bar %d of %d · slap to stack a layer" % [into, int(looped[1])]
		return out
	if loop_set(state):
		out["line"] = "SLAP TO STACK A LAYER"
		out["said"] = "READY: a slap stacks a layer on the loop"
	else:
		out["line"] = "SLAP TO LOOP %d BAR%s" % [length, "" if length == 1 else "S"]
		out["said"] = "READY: a slap loops the next %d bar%s" % [length, "" if length == 1 else "s"]
	return out


## What the pad's card says it is doing: the screen's, as a sentence.
func state_words() -> String:
	return str(display(heard())["said"])


func _build_screen() -> void:
	var frame := panel_frame(SCREEN_X, SCREEN)
	var screen := Node3D.new()
	screen.name = "Screen"
	screen.transform = frame
	add_child(screen)
	_word = _label("Word", WORD_SIZE, Vector3(-SCREEN.x * 0.5 + 0.04, 0.026, 0.0))
	screen.add_child(_word)
	_line = _label("Line", LINE_SIZE, Vector3(-SCREEN.x * 0.5 + 0.012, -0.002, 0.0))
	screen.add_child(_line)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var pane := BoxMesh.new()
	pane.size = Vector3(SCREEN.x, SCREEN.y, 0.002)
	glass.mesh = pane
	glass.position = Vector3(0, 0, -0.001)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.04, 0.04)
	dark.roughness = 0.45
	dark.metallic = 0.2
	glass.material_override = dark
	screen.add_child(glass)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	ink.albedo_color = Color(0.92, 0.95, 0.88)
	var mark_at := Vector3(-SCREEN.x * 0.5 + 0.022, 0.026, 0.0005)
	# REC: a round mark; PLAY: a triangle pointing on; READY: a square. Words beside each.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.009
	disc.bottom_radius = 0.009
	disc.height = 0.001
	disc.radial_segments = 24
	_marks[&"rec"] = _mark("RecMark", disc, ink, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), mark_at), screen)
	var tri := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.008, -0.009, 0), Vector3(0.01, 0, 0), Vector3(-0.008, 0.009, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	tri.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_marks[&"play"] = _mark("PlayMark", tri, ink, Transform3D(Basis.IDENTITY, mark_at), screen)
	var square := BoxMesh.new()
	square.size = Vector3(0.015, 0.015, 0.001)
	_marks[&"ready"] = _mark("ReadyMark", square, ink, Transform3D(Basis.IDENTITY, mark_at), screen)
	var dot := CylinderMesh.new()
	dot.top_radius = 1.0
	dot.bottom_radius = 1.0
	dot.height = 0.001
	dot.radial_segments = 16
	for n in MOST_DOTS:
		var d := MeshInstance3D.new()
		d.name = "Beat%d" % n
		d.mesh = dot
		d.material_override = ink
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-SCREEN.x * 0.5 + 0.016 + n * 0.02, -0.027, 0.0005))
		d.visible = false
		screen.add_child(d)
		_dots.append(d)


func _label(named: String, size: int, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.name = named
	l.pixel_size = 0.0002
	l.font_size = size
	l.outline_size = 0
	l.modulate = Color(0.92, 0.95, 0.88)
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = at + Vector3(0, 0, 0.0008)
	Lettering.range_to_legibility(l)
	return l


func _mark(named: String, mesh: Mesh, ink: Material, at: Transform3D, under: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = named
	m.mesh = mesh
	m.material_override = ink
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.transform = at
	m.visible = false
	under.add_child(m)
	return m


func _show(h: Dictionary) -> void:
	_show_key()
	if _word == null:
		return
	var d := display(h)
	if d == _shown:
		return
	_shown = d
	_word.text = str(d["word"])
	_line.text = str(d["line"])
	Lettering.fit(_line, SCREEN.x - 0.024, LINE_SIZE, 30)
	for mark: StringName in _marks:
		(_marks[mark] as MeshInstance3D).visible = mark == d["mark"]
	var big: Array = d["big"]
	for n in _dots.size():
		var dot := _dots[n]
		dot.visible = n < int(d["dots"])
		var r := DOT if n < big.size() and bool(big[n]) else DOT_SMALL
		dot.scale = Vector3(r, 1.0, r)


## The pad set into the deck: a fixed instrument, slapped by a hand or a controller (Strike) or clicked.
## Its strike is the looper's (`slapped`), never a hit for the room or the take.
class Pad extends InstrumentItem:
	var looper: Looper

	func _init() -> void:
		id = &"looper_pad"
		fixed = true
		own_home = true
		super()

	func item_title() -> String:
		return "LOOPER"

	func sound_kind(_struck: bool) -> StringName:
		return &"pad"

	func has_own_jack() -> bool:
		return false

	## Its shelf tag says nothing: the screen behind it says what it is doing.
	func tag_text() -> String:
		return ""

	func faces() -> Array:
		return [{"frame": global_transform * Transform3D(Basis.IDENTITY, Vector3.UP * PAD_TALL), "half": PAD_HALF}]

	func centre_height() -> float:
		return PAD_TALL * 0.5

	func readout() -> String:
		return looper.state_words() if looper != null else "a looper"

	func hint() -> String:
		var bars := looper.length if looper != null else LENGTH_DEFAULT
		var to := "the loop's bars" if Looper.loop_set(DAW.state) else "%d bar%s (LENGTH)" % [bars, "" if bars == 1 else "s"]
		if hands_hint:
			return "slap it: a bar's count, then everything you play for %s is a layer of its own · slap again while it loops to stack another · each layer is a ring on the post: grab one to mute it, pull it away to delete it" % to
		return "click to loop: a bar's count, then everything you play for %s is a layer on a track of your own · click again while it loops to stack another · each layer is a ring on the post: click one to mute it; the LAYERS list has MUTE and X" % to

	func _grip_shape() -> Shape3D:
		var s := BoxShape3D.new()
		s.size = Vector3(PAD_HALF.x * 2.0 + 0.02, 0.04, PAD_HALF.y * 2.0 + 0.02)
		return s

	func _build_body() -> Node3D:
		var root := Node3D.new()
		var face := MeshInstance3D.new()
		face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(PAD_HALF.x * 2.0, PAD_TALL, PAD_HALF.y * 2.0)
		face.mesh = slab
		face.position = Vector3(0, PAD_TALL * 0.5, 0)
		var rubber := StandardMaterial3D.new()
		rubber.albedo_color = Color(0.16, 0.16, 0.17)
		rubber.roughness = 0.95
		face.material_override = rubber
		root.add_child(face)
		# Lettered on its face, as a sample pad is: what it is for, read from where you stand.
		var said := Label3D.new()
		said.name = "Slap"
		said.text = "SLAP TO LOOP"
		said.pixel_size = 0.0002
		said.font_size = 110
		said.outline_size = 0
		said.modulate = Color(0.6, 0.6, 0.58)
		said.shaded = false
		said.double_sided = false
		said.rotation.x = -PI * 0.5
		said.position = Vector3(0, PAD_TALL + 0.0006, PAD_HALF.y - 0.02)
		Lettering.range_to_legibility(said)
		root.add_child(said)
		return root


## LENGTH, on a key of its own beside the screen: a press steps 1, 2, 4, 8 bars, round, and the wheel
## or a thumbstick steps it either way. Where a loop range is set the layer is the loop's and the key
## says so.
class LengthKey extends ControlAffordance:
	var looper: Looper
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(KEY.x, KEY.y, 0.02)
		shape.shape = box
		add_child(shape)
		var face := MeshInstance3D.new()
		face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(KEY.x - 0.006, KEY.y - 0.006, 0.006)
		face.mesh = slab
		face.position = Vector3(0, 0, -0.002)
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.32, 0.3, 0.27)
		cap.roughness = 0.6
		face.material_override = cap
		add_child(face)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.text = "LENGTH\n2 BARS"
		legend.pixel_size = 0.0002
		legend.font_size = 80
		legend.outline_size = 0
		legend.modulate = Color(0.95, 0.92, 0.84)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position = Vector3(0, 0, 0.0015)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "LOOPER  LENGTH"

	func _default_readout() -> String:
		if looper == null:
			return ""
		if Looper.loop_set(DAW.state):
			return "the loop range's %d bars: a layer is the loop" % int(Looper.loop_bars(DAW.state)[1])
		return "%d bar%s a layer" % [looper.length, "" if looper.length == 1 else "s"]

	func hint() -> String:
		return "press for the next length, 1, 2, 4 or 8 bars · the wheel steps either way"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if looper != null:
			looper.step_length(1)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if looper == null:
			return false
		looper.step_length(signi(notches))
		return true
