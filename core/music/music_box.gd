class_name MusicBox
extends Node3D

## A music-box sequencer (docs/spatial_loop.md part two, slice 47, idea #15): a brass cylinder of
## STEPS (16) steps round by ROWS (8) rows across, turning past a steel comb on a wooden case, on a
## plinth of its own. A station (Stations.ALL, `music_box`), free-standing, and so a trolley in a studio
## (Venue.WHEELED): gone to by name, stood clear of everything else, pushed about like the harp.
##
## Its pegs are a pattern, and the pattern is ordinary MIDI: the notes of one MIDI item on its TRACK,
## the first one under the box's bars (`item_of`). Pressing a cell adds a peg (DAW.insert_note at that
## step, one undo step), and pressing a peg takes it out (DAW.delete_note). A drag along a row adds a
## run of pegs, or takes a run out where it began on a peg, inside one edit (DAW.open_edit and
## close_edit), so the whole run is one undo step. The pegs are read back from the item every frame
## (`pegs_of`), never kept here, so a note moved in the 2D roll moves its peg, an undo takes its peg
## back, and every player's box shows the host's mix. It sounds as the track plays, as any MIDI does.
##
## Its bars: one turn of the cylinder is its LENGTH, 1, 2 or 4 bars (`span_of`): the loop's, from its
## first bar, a LENGTH a page where the loop is longer; else the LENGTH-bar page the playhead is in, so
## a cylinder left turning with the song shows each page of the item as the song reaches it. Its rows
## are the key's scale up from its root (the song's key at its first bar, Harmony.at), or semitones
## up from it by its SCALE switch (`rows_of`). The root is the key's tonic in A3 to G#4, moved by its
## ROOT key, so the rows follow a key change. A note that is on no row (after a key change, or played
## in by another instrument) is drawn at its nearest row with a mark: a collar round its peg, which
## leans toward where its pitch really is. Pressing it takes it out.
##
## TRACK, LENGTH, ROOT and SCALE are the room's row `music_box` [track, length, root, chromatic]
## (`row`), asked of the host and predicted (Session.ROOM_VERBS, Studio), so every player sees the same
## pegs. TRACK 0 is the MUSIC BOX track, the first track of that name (`track_of`), which the first
## peg makes at the end of the project where there is none. Each is a key on the case's front: a
## press steps it on, the wheel (a desk) or a stick (a headset) either way.
##
## It turns with the song (`turn_of`): the step sounding passes under the comb at the top, the steps
## to come below it on the front, so whoever stands at it sees the next half-bar coming up. The
## comb's teeth flick as pegs pass. At Ergonomics motion 0 the cylinder steps a step at a time and the
## teeth stand still. A desk clicks cells, and the wheel over the cylinder turns the view round a step
## a notch (`view_steps`, this player's own), to reach the steps round the back. A hand has the
## knurled wheel on the axle past the right cheek (`Thumbwheel`): pushed up or down, it rolls the brass
## round with it, as a real music box's cylinder is turned by hand; a press turns it a step, and a
## controller's stick over it or over the brass turns it either way. Without it a tracked hand, which
## has no wheel or stick, could reach only the steps on the front while the song is stopped.
##
## A guest's peg is DAW intents like every edit, shown at once here (`_predicted`, PREDICT_MS) until
## the host's mix says so. A first peg with no track or no item yet asks for them first (add_track,
## then insert_midi_take with the pegs so far as its notes), and the cells pressed meanwhile wait for
## them in the queue (`_queue`), so a drag that begins on an empty box is still one edit.
##
## Its numbers are tools/blender/music_box.py's, which builds the case. Origin the middle of the
## plinth's foot, on the floor; its front (+Z) where you stand.

## The station, and the room's row and the verb that asks for it (Session.ROOM_VERBS).
const STATION := &"music_box"
const VERB := &"music_box"
## The track TRACK 0 is, made by the first peg where the project has none.
const TRACK_NAME := "MUSIC BOX"
## The cylinder: steps round, rows across.
const STEPS := 16
const ROWS := 8
## The lengths LENGTH steps through, in bars.
const LENGTHS: Array[int] = [1, 2, 4]
## How far the ROOT key moves the root from the key's tonic, either way (semitones).
const ROOT_MOST := 24
## The lowest the key's tonic is put: A3. The rows begin at the tonic from here to an octave up.
const TONIC_FLOOR := 57
## The row a box starts with: the MUSIC BOX track, a bar a turn, the key's tonic, the key's scale.
const DEFAULT_ROW := [0, 1, 0, false]
## The keys on the case's front, in order.
enum Kind { TRACK, LENGTH, ROOT, SCALE }

const MODEL := "res://assets/models/music_box.glb"
## Half its footprint, how far along Z its middle is, and how tall it stands (the lid open): its
## walker solid and its trolley (Stations' row says the same).
const FOOT := Vector2(0.3, 0.22)
const FOOT_Z := -0.02
const TOP := 1.56
## The base board's top.
const DECK_Y := 0.88
## The cylinder's axle (across X), its radius and half its length; the rows across it, ROW_PITCH apart
## from ROW_LEFT (row 0, the lowest, at the left as on a keyboard); the step numbers' band past them.
const AXIS := Vector3(0, 1.0, -0.03)
const RADIUS := 0.095
const HALF := 0.18
const ROW_PITCH := 0.04
const ROW_LEFT := -0.18
const NUMBERS_X := 0.16
## The knurled wheel on the axle past the right cheek (`Thumbwheel`): its middle across, its radius
## and its width. Pushed up or down at its rim, it turns the brass with it a step every
## WHEEL_RADIUS * STEP_ANGLE (1.6 cm) of the hand's travel.
const WHEEL_X := 0.243
const WHEEL_RADIUS := 0.04
const WHEEL_WIDTH := 0.026
## A step's share of a turn, and where a peg sounds: under the comb, at the top.
const STEP_ANGLE := TAU / STEPS
const COMB_ANGLE := PI * 0.5
## A peg: its radius and how far it stands proud of the brass.
const PEG_RADIUS := 0.0075
const PEG_TALL := 0.018
## A marked peg's lean toward where its pitch really is (radians), and its collar's outer radius and
## its tube's: a bright steel ring well past the peg's foot, so the mark reads by its shape from the
## seat and not only by the lean.
const MARK_LEAN := 0.45
const MARK_RING := 0.0135
const MARK_TUBE := 0.003
## The comb: where its plate ends and its teeth begin, how high they are, and how far a flick lifts one
## (radians), dying away over FLICK_TIME (s).
const COMB_ROOT_Z := -0.11
const TOOTH_Y := 1.093
const TOOTH := Vector2(0.03, 0.0025)
const FLICK := 0.35
const FLICK_TIME := 0.12
## The row names' rail between the cylinder and the keys, and the keys on the base board's front: each
## KEY across and up its face, their middles across, how far forward they are, and how far their faces
## are tipped up toward whoever stands in front (from flat, radians).
const RAIL := Vector3(0.36, 0.01, 0.042)
const RAIL_Z := 0.09
const RAIL_X := -0.02
const KEY := Vector2(0.13, 0.07)
const KEY_XS: Array[float] = [-0.21, -0.07, 0.07, 0.21]
const KEY_Z := 0.166
const KEY_TILT := 0.35
## Where its plaque hangs: on the open lid's felt, as a music box's label is, leaning back with the lid
## from its hinge on the back wall's top (LID_HINGE, the felt's face there, and LID_LEAN, the model's),
## its top edge PLAQUE_UP along the lid. Up there it is over everything the box is played by and never
## behind any of it, and from the desk's seat across the room it is seen over the gear between (under
## the deck, the chord ledge's plaque covered it). Opened, it grows down the lid toward the hinge.
const LID_HINGE := Vector3(0, 1.12, -0.217)
const LID_LEAN := 0.06
const PLAQUE_UP := 0.405
const PLAQUE_WIDTH := 0.56
## Stations' frame: the folded plaque's top edge, on the lid, and the keys' front edge on the deck.
const FRAME_TOP := Vector3(0, 1.524, -0.241)
const FRAME_FOOT := Vector3(0, 0.88, 0.2)
## The lamp under the open lid's top edge, above the plaque, shining down on the cylinder and the keys.
const LAMP_AT := Vector3(0, 1.547, -0.231)
const LAMP_COLOUR := Color(1.0, 0.82, 0.58)
## How long (ms) a guest's peg is shown before the host's mix has to say so, and how long the queue
## waits for a track or an item asked for, or for a guest's mirror to take in what it sent.
const PREDICT_MS := 1500
const WAIT_MS := 2000
## How far (m) a dragged point must move before a held still pointer, the cylinder turning under it,
## can add another peg.
const DRAG_MOVE := 0.004

## Somebody here asked for the room's row to be `wanted` (a key pressed or nudged): for the studio to
## set, or ask the host for.
signal row_asked(wanted: Array)
## Words for the studio's toast: what a press did, or why it could not.
signal told(text: String)

## The room's row: [track, length, root, chromatic].
var row: Array = DEFAULT_ROW.duplicate():
	set(v):
		row = v.duplicate() if v.size() == 4 else DEFAULT_ROW.duplicate()
		_dirty = true
## Where the song is as this player hears it ({seconds, playing, valid}); the suite's own, or
## GuestMidi.heard, or the mix's playhead.
var heard_source: Callable = Callable()
## How many steps this player has turned the view round with the wheel: theirs alone.
var view_steps := 0
## The cylinder's control (every cell is a click on it), the wheel that turns it round by hand, and the
## keys by Kind.
var drum: Drum = null
var thumbwheel: Thumbwheel = null
var keys := {}
## The cylinder's turning part (pegs, holes, numbers), and the comb's teeth, row by row.
var turn: Node3D = null
var teeth: Array[Node3D] = []
## The bars it shows now, [start, end] in seconds, and the angle it is shown at (radians, its view
## turned in): as last drawn.
var span := Vector2(0.0, 2.0)
var shown_angle := 0.0

## The pegs shown: {Vector2i(row, step): mark}, mark 0 on its row, +1 or -1 off it toward where its
## pitch is.
var _shown := {}
var _shown_key := ""
## Pegs pressed here the mix has not shown yet: {Vector2i: [on, until msec]}.
var _predicted := {}
## Cells waiting for the track, the item or a guest's mirror: [[Vector2i, adding], ...].
var _queue: Array = []
## When the track or the item was asked for, and a guest's last sent edits: what the item's notes were
## then and until when to wait for them to change.
var _asked_track_at := -1
var _asked_item_at := -1
var _sent_sig := ""
var _sent_until := 0
## The gesture: {"adding", "row", "last", "at" (where the pointer last added, box frame)}; empty for
## none. `_edit_open` while its edit is, `_ending` once let go with the queue not yet empty.
var _gesture := {}
var _edit_open := false
var _ending := false
var _flick: Array[float] = []
var _last_step := -1
var _dirty := true
var _peg_mesh: CylinderMesh
var _ring_mesh: TorusMesh
var _head_mesh: SphereMesh
var _steel: StandardMaterial3D
var _collar: StandardMaterial3D
var _pegs: Node3D
var _names: Array[Label3D] = []


func _init() -> void:
	name = "MusicBox"
	for _r in ROWS:
		_flick.append(0.0)


func _ready() -> void:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_build_turn()
	_build_comb()
	_build_rail()
	drum = Drum.new()
	drum.box = self
	drum.name = "Drum"
	drum.position = AXIS
	add_child(drum)
	thumbwheel = Thumbwheel.new()
	thumbwheel.box = self
	thumbwheel.name = "Thumbwheel"
	thumbwheel.position = AXIS + Vector3(WHEEL_X, 0, 0)
	add_child(thumbwheel)
	for kind: int in [Kind.TRACK, Kind.LENGTH, Kind.ROOT, Kind.SCALE]:
		var key := SettingKey.new()
		key.box = self
		key.kind = kind
		key.name = "Key%s" % Kind.keys()[kind].capitalize()
		key.transform = key_frame(kind)
		add_child(key)
		keys[kind] = key
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	plaque.transform = lid_frame() * Transform3D(Basis.IDENTITY,
			Vector3(0, PLAQUE_UP - float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5, 0.001))
	add_child(plaque)
	_build_lamp()
	refresh()


## The music box as the walker's solid, at `spot` (its transform in the venue's frame).
static func solid(spot: Transform3D) -> Dictionary:
	var middle := spot * Vector3(0, 0, FOOT_Z)
	return {"c": Vector2(middle.x, middle.z), "h": FOOT, "a": spot.basis.get_euler().y, "top": TOP}


## The open lid's frame: its origin the felt's face at the hinge, its +Y up the lid, its +Z the way the
## felt faces.
static func lid_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -LID_LEAN), LID_HINGE)


## Key `kind`'s frame on the case: on the base board's front, its face tipped up toward the player.
static func key_frame(kind: int) -> Transform3D:
	var tip := Basis(Vector3.RIGHT, -(PI * 0.5 - KEY_TILT))
	var up := sin(KEY_TILT) * KEY.y * 0.5
	return Transform3D(tip, Vector3(KEY_XS[kind], DECK_Y + up + 0.004, KEY_Z))


# --- the row --------------------------------------------------------------------------------

## `wanted` as a row the host keeps ([track, length, root, chromatic]), or [] where it is not one: a
## track that is the MUSIC BOX one (0) or in the project, a length of LENGTHS, a root within ROOT_MOST.
static func clean(wanted: Array, state: MixState) -> Array:
	if wanted.size() != 4 or typeof(wanted[0]) != TYPE_INT or typeof(wanted[1]) != TYPE_INT \
			or typeof(wanted[2]) != TYPE_INT or typeof(wanted[3]) != TYPE_BOOL:
		return []
	var track := int(wanted[0])
	if track < 0 or (track > 0 and (state == null or not state.tracks.has(track))):
		return []
	if not LENGTHS.has(int(wanted[1])) or absi(int(wanted[2])) > ROOT_MOST:
		return []
	return [track, int(wanted[1]), int(wanted[2]), bool(wanted[3])]


func length() -> int:
	return int(row[1]) if LENGTHS.has(int(row[1])) else LENGTHS[0]


## The track the row's TRACK is: its own where it is in the project, else the first MUSIC BOX track,
## else 0 (none yet: the first peg makes it).
static func track_of(state: MixState, r: Array) -> int:
	if state == null:
		return 0
	var t := int(r[0]) if r.size() > 0 else 0
	if t > 0 and state.tracks.has(t):
		return t
	return named_track(state)


## The first track named TRACK_NAME, or 0.
static func named_track(state: MixState) -> int:
	for i in state.track_indices():
		if (state.tracks[i] as MixState.TrackState).name == TRACK_NAME:
			return int(i)
	return 0


## The choices TRACK steps through: 0 (the MUSIC BOX track, made or not), then every other track.
static func track_choices(state: MixState) -> Array[int]:
	var out: Array[int] = [0]
	var own := named_track(state) if state != null else 0
	if state != null:
		for i in state.track_indices():
			if int(i) > 0 and int(i) != own:
				out.append(int(i))
	return out


## The row with key `kind` stepped `by` (a press is +1, the wheel either way): TRACK through
## track_choices, LENGTH through LENGTHS, ROOT a semitone (a press goes round an octave up from the
## tonic), SCALE between the key's scale and chromatic.
static func stepped(r: Array, kind: int, by: int, state: MixState, press := false) -> Array:
	var out := r.duplicate()
	match kind:
		Kind.TRACK:
			var choices := track_choices(state)
			var at := choices.find(int(r[0]))
			if at < 0:
				at = 0
			out[0] = choices[posmod(at + by, choices.size())]
		Kind.LENGTH:
			var at := LENGTHS.find(int(r[1]))
			out[1] = LENGTHS[posmod(at + by, LENGTHS.size())] if press \
					else LENGTHS[clampi(at + by, 0, LENGTHS.size() - 1)]
		Kind.ROOT:
			var root := int(r[2])
			out[2] = posmod(root + 1, 12) if press and root >= 0 and root < 12 \
					else (0 if press else clampi(root + by, -ROOT_MOST, ROOT_MOST))
		Kind.SCALE:
			out[3] = not bool(r[3])
	return out


## A key here pressed (`by` +1) or nudged: the room is asked for the row it makes, and shown at once
## by the studio.
func step_setting(kind: int, by: int, press := false) -> void:
	var wanted := stepped(row, kind, by, DAW.state, press)
	if wanted != row:
		row_asked.emit(wanted)


# --- its bars and its rows --------------------------------------------------------------------

## The bars a turn is, [start, end] in seconds, at song position `song`, `bars` a turn: in a loop range,
## the `bars` page of it the song is in (its first where the song is outside it); else the `bars` page
## of the song the playhead is in, counted from bar 1.
static func span_of(state: MixState, bars: int, song: float) -> Vector2:
	if state == null:
		return Vector2(0.0, 2.0)
	var first := 0
	var bar := floori(state.bar_at(song) + Harmony.BAR_SLACK)
	if state.has_loop_range():
		first = floori(state.bar_at(state.loop_start) + Harmony.BAR_SLACK)
		var last := maxi(ceili(state.bar_at(state.loop_end) - Harmony.BAR_SLACK), first + 1)
		if bar < first or bar >= last:
			bar = first
	var page := first + floori(float(bar - first) / bars) * bars
	# bar_at counts from 0, bar_to_seconds from 1.
	return Vector2(state.bar_to_seconds(page + 1.0), state.bar_to_seconds(page + 1.0 + bars))


## Where step `step` of `of` begins, in seconds: an even share of its beats.
static func step_time(state: MixState, of: Vector2, step: float) -> float:
	var b0 := state.beat_at(of.x)
	var b1 := state.beat_at(of.y)
	return state.seconds_at_beat(b0 + (b1 - b0) * step / STEPS)


## How far into `of` (in steps, unrounded) song time `seconds` is.
static func steps_into(state: MixState, of: Vector2, seconds: float) -> float:
	var b0 := state.beat_at(of.x)
	var b1 := state.beat_at(of.y)
	return (state.beat_at(seconds) - b0) / maxf(b1 - b0, 0.0001) * STEPS


## How far round (radians) the cylinder is at song position `song` in `of`: the step sounding under
## the comb, going round once a turn; at `motion` 0, a step at a time.
static func turn_of(state: MixState, of: Vector2, song: float, motion: float) -> float:
	if state == null:
		return 0.0
	var into := fposmod(steps_into(state, of, song), float(STEPS))
	if motion <= 0.0:
		into = floorf(into + 0.0001)
	return into * STEP_ANGLE


## The key the box plays in: the song's at the first bar of `of`.
static func key_of(state: MixState, of: Vector2) -> Harmony:
	return Harmony.at(state, of.x + Harmony.AT_SLACK)


## The row's lowest pitch: the key's tonic in TONIC_FLOOR's octave, moved by its root.
static func base_of(key: Harmony, r: Array) -> int:
	return TONIC_FLOOR + posmod(key.root - TONIC_FLOOR, 12) + int(r[2])


## The rows' pitches, lowest first: ROWS of the key's scale from the base up (the base taken up to the
## scale's next tone where the root has moved it off it), or ROWS semitones where the row is chromatic.
static func rows_of(key: Harmony, r: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var p := base_of(key, r)
	while out.size() < ROWS:
		if bool(r[3]) or key.scale.has(posmod(p, 12)):
			out.append(p)
		p += 1
	return out


## The row a pitch is drawn on, and its mark: [row, 0] on a row, [nearest row, +1 or -1] toward where it
## really is (the lower of two as near).
static func row_for(rows: PackedInt32Array, pitch: int) -> Array:
	var best := 0
	for i in rows.size():
		if rows[i] == pitch:
			return [i, 0]
		if absi(rows[i] - pitch) < absi(rows[best] - pitch):
			best = i
	return [best, signi(pitch - rows[best])]


## The MIDI item the box's pegs are on, on `track`: the first (by its place) that is MIDI and under any
## of `of`; -1 for none.
static func item_of(state: MixState, track: int, of: Vector2) -> int:
	var t := state.track(track, false) if state != null and track > 0 else null
	if t == null:
		return -1
	for i in t.items.size():
		var it: MixState.ItemState = t.items[i]
		if it.source == "" and it.start < of.y - 0.0005 and it.start + it.length > of.x + 0.0005:
			return i
	return -1


## The pegs of item `item` on `track` in `of`: {Vector2i(row, step): {"notes": [note indices], "mark":
## 0 or ±1}}, each note begun within half a step of a step drawn there, at its row (`row_for`). A cell
## with notes both on and off its row is on it.
static func pegs_of(state: MixState, track: int, item: int, of: Vector2, rows: PackedInt32Array) -> Dictionary:
	var out := {}
	var it := state.item(track, item) if state != null else null
	if it == null:
		return out
	var notes := it.notes
	for n in range(0, notes.size() - MidiTake.NOTE_WIDTH + 1, MidiTake.NOTE_WIDTH):
		var at := steps_into(state, of, it.start + notes[n])
		var step := roundi(at)
		if at < -0.5 or step >= STEPS or step < 0:
			continue
		var placed := row_for(rows, int(notes[n + 2]))
		var cell := Vector2i(int(placed[0]), step)
		var was: Dictionary = out.get(cell, {"notes": [], "mark": int(placed[1])})
		(was["notes"] as Array).append(n / MidiTake.NOTE_WIDTH)
		if int(placed[1]) == 0:
			was["mark"] = 0
		out[cell] = was
	return out


# --- following the song -----------------------------------------------------------------------

func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": DAW.state.position_seconds if DAW.state != null else 0.0, "playing": false, "valid": true}


func _song() -> Dictionary:
	var h := heard()
	if not bool(h.get("valid", false)):
		var s := DAW.state
		return {"seconds": s.position_seconds if s != null else 0.0, "playing": s != null and s.playing}
	return h


func _process(delta: float) -> void:
	var h := _song()
	var song := float(h.get("seconds", 0.0))
	var motion := Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0
	show_at(song, motion)
	_tend_teeth(song, bool(h.get("playing", false)), motion, delta)
	flush()


## The box drawn at song position `song`: its bars, its pegs and its names, and its cylinder turned
## to the step sounding (and the view this player has turned in).
func show_at(song: float, motion: float) -> void:
	var s := DAW.state
	span = span_of(s, length(), song)
	refresh()
	shown_angle = turn_of(s, span, song, motion) + view_steps * STEP_ANGLE
	if turn != null:
		turn.rotation.x = -shown_angle


## The comb's teeth: a peg reaching the comb as the song plays flicks its row's tooth, and the flick
## dies away; at motion 0 they stand.
func _tend_teeth(song: float, playing: bool, motion: float, delta: float) -> void:
	var step := floori(fposmod(steps_into(DAW.state, span, song), float(STEPS)) + 0.0001) if DAW.state != null else 0
	if playing and step != _last_step:
		for cell: Vector2i in _shown:
			if cell.y == step:
				_flick[cell.x] = 1.0
	_last_step = step
	for r in ROWS:
		_flick[r] = _flick[r] * exp(-delta / FLICK_TIME) if _flick[r] > 0.01 else 0.0
		if r < teeth.size():
			teeth[r].rotation.x = FLICK * _flick[r] * clampf(motion, 0.0, 1.0)


## How far a row's tooth is lifted now (radians): what the suite reads of a flick.
func tooth_lift(r: int) -> float:
	return teeth[r].rotation.x if r >= 0 and r < teeth.size() else 0.0


# --- the pegs ---------------------------------------------------------------------------------

## The pegs as the mix has them now, under what this player has pressed and the mix has not shown yet:
## {Vector2i: mark}.
func pegs() -> Dictionary:
	var s := DAW.state
	var key := key_of(s, span)
	var rows := rows_of(key, row)
	var track := track_of(s, row)
	var item := item_of(s, track, span)
	var out := {}
	var from_mix := pegs_of(s, track, item, span, rows) if item >= 0 else {}
	for cell: Vector2i in from_mix:
		out[cell] = int(from_mix[cell]["mark"])
	var now := Time.get_ticks_msec()
	for cell: Vector2i in _predicted.keys():
		var p: Array = _predicted[cell]
		if now > int(p[1]) or bool(p[0]) == from_mix.has(cell):
			_predicted.erase(cell)
			continue
		if bool(p[0]):
			out[cell] = 0
		else:
			out.erase(cell)
	return out


## Whether a peg is shown at `cell`.
func has_peg(cell: Vector2i) -> bool:
	return _shown.has(cell)


## The box redrawn where what it shows has changed: its pegs, the rows' names and the keys' legends.
func refresh() -> void:
	var now := pegs()
	var s := DAW.state
	var key := key_of(s, span)
	var rows := rows_of(key, row)
	var said := "%s|%s|%s|%s" % [now, rows, row, track_of(s, row)]
	if said == _shown_key and not _dirty:
		return
	_shown = now
	_shown_key = said
	_dirty = false
	_draw_pegs()
	for r in mini(_names.size(), rows.size()):
		_names[r].text = key.note_name(rows[r])
	for kind: int in keys:
		(keys[kind] as SettingKey).show_legend(legend(kind))


## What key `kind` says: its name over its setting.
func legend(kind: int) -> String:
	var s := DAW.state
	match kind:
		Kind.TRACK:
			return "TRACK\n%s" % track_title(s, row).left(14)
		Kind.LENGTH:
			return "LENGTH\n%d BAR%s" % [length(), "" if length() == 1 else "S"]
		Kind.ROOT:
			var key := key_of(s, span)
			return "ROOT\n%s" % key.note_name(base_of(key, row))
		Kind.SCALE:
			return "SCALE\n%s" % ("CHROMATIC" if bool(row[3]) else key_of(s, span).key_name.to_upper())
	return ""


## What the row's TRACK is called: its track's name, or MUSIC BOX where the first peg will make it.
static func track_title(state: MixState, r: Array) -> String:
	var t := track_of(state, r)
	if t <= 0:
		return TRACK_NAME
	var name_of := (state.tracks[t] as MixState.TrackState).name
	return name_of if not name_of.is_empty() else "TRACK %d" % t


## Where cell `cell`'s peg stands, in the cylinder's own frame (`turn`, its middle the axle).
static func cell_local(cell: Vector2i, out := 0.0) -> Vector3:
	var theta := COMB_ANGLE - cell.y * STEP_ANGLE
	var r := RADIUS + out
	return Vector3(ROW_LEFT + ROW_PITCH * (cell.x + 0.5), r * sin(theta), r * cos(theta))


## Where cell `cell` is on the brass now, in the box's frame: what a click on it hits.
func cell_point(cell: Vector2i) -> Vector3:
	var p := cell_local(cell)
	return AXIS + Basis(Vector3.RIGHT, -shown_angle) * p


## The cell under point `p` (the box's frame) on the cylinder as it is shown: a point on the brass (a
## ray's hit), or on the upright plane through the axle (a drag, Interactor._plane_point), read as the
## front's. Vector2i(-1, -1) off the rows.
func cell_at(p: Vector3) -> Vector2i:
	var q := p - AXIS
	var r := floori((q.x - ROW_LEFT) / ROW_PITCH)
	if r < 0 or r >= ROWS:
		return Vector2i(-1, -1)
	# On the brass (or a peg's head) it is where round it the point is; on the upright plane through the
	# axle it is a drag's point, read as the front's at that height.
	var theta := atan2(q.y, q.z) if absf(q.z) > 0.002 and Vector2(q.y, q.z).length() > RADIUS * 0.9 \
			else asin(clampf(q.y / RADIUS, -1.0, 1.0))
	var local := theta - shown_angle
	return Vector2i(r, posmod(roundi((COMB_ANGLE - local) / STEP_ANGLE), STEPS))


# --- pressing and dragging --------------------------------------------------------------------

## A press on `cell`: a peg put in where there is none, taken out where there is one. One undo step.
func press(cell: Vector2i) -> void:
	begin_gesture(cell)
	end_gesture()


## A hand or a click came down on `cell`: an edit opens, and the cell is changed. What it did (a peg
## in, or out) is what the rest of a drag along its row does.
func begin_gesture(cell: Vector2i, at := Vector3.INF) -> void:
	if cell.x < 0:
		return
	refresh()
	if _edit_open and not _ending:
		end_gesture()
	_gesture = {"adding": not has_peg(cell), "row": cell.x, "last": cell.y, "at": at}
	_ending = false
	if not _edit_open:
		DAW.open_edit("%s: pegs" % TRACK_NAME)
		_edit_open = true
	_change(cell, bool(_gesture["adding"]))
	flush()


## The drag moved on to `cell` (point `at`, the box's frame): every cell along its row from the last
## one changed, as the first was. A cell off its row, or a pointer held still while the cylinder turns
## under it, changes nothing.
func extend_gesture(cell: Vector2i, at := Vector3.INF) -> void:
	if _gesture.is_empty() or cell.x != int(_gesture["row"]):
		return
	var was: Vector3 = _gesture["at"]
	if at != Vector3.INF and was != Vector3.INF and at.distance_to(was) < DRAG_MOVE:
		return
	var last := int(_gesture["last"])
	if cell.y == last:
		return
	# The short way round, as the hand went.
	var by := posmod(cell.y - last, STEPS)
	var way := 1 if by <= STEPS / 2 else -1
	var steps := by if way == 1 else STEPS - by
	for k in range(1, steps + 1):
		_change(Vector2i(cell.x, posmod(last + way * k, STEPS)), bool(_gesture["adding"]))
	_gesture["last"] = cell.y
	_gesture["at"] = at
	flush()


## Let go: the edit closes once every cell of it has reached the mix (`flush`).
func end_gesture() -> void:
	_gesture = {}
	_ending = true
	flush()


## Cell `cell` to have a peg (`adding`) or not: shown so at once, and queued for the mix.
func _change(cell: Vector2i, adding: bool) -> void:
	if has_peg(cell) == adding:
		return
	_predicted[cell] = [adding, Time.get_ticks_msec() + PREDICT_MS]
	_queue.append([cell, adding])
	_dirty = true
	if adding:
		_shown[cell] = 0
	else:
		_shown.erase(cell)
	_draw_pegs()


## The queue to the mix, as far as it can go now: the MUSIC BOX track asked for where there is none,
## then the item (insert_midi_take, the pegs waiting as its notes), then each peg as a note in or out
## (deletes first, from the highest index, so no index moves under another). A guest waits for its
## mirror to show what it sent before it sends more, so an index it names is the host's. The edit
## closes when the queue is empty and the gesture let go.
func flush() -> void:
	var s := DAW.state
	var now := Time.get_ticks_msec()
	if not _queue.is_empty() and s != null:
		var track := track_of(s, row)
		if track <= 0:
			if _asked_track_at < 0:
				_asked_track_at = now
				DAW.add_track(Looper.track_count(s) + 1, TRACK_NAME)
				track = track_of(s, row)
			elif now - _asked_track_at > WAIT_MS:
				_give_up("The %s track did not arrive: press again." % TRACK_NAME)
		if track > 0:
			_asked_track_at = -1
			_send(s, track, now)
	if _queue.is_empty() and Session.is_authority():
		# The host's mix has it already: nothing to wait for it to say.
		_predicted.clear()
	if _ending and _queue.is_empty():
		_ending = false
		if _edit_open:
			_edit_open = false
			DAW.close_edit()


func _send(s: MixState, track: int, now: int) -> void:
	var item := item_of(s, track, span)
	if item < 0:
		if _asked_item_at < 0:
			var notes: Array = []
			var rows := rows_of(key_of(s, span), row)
			for q: Array in _queue:
				if bool(q[1]):
					var cell: Vector2i = q[0]
					notes.append([step_time(s, span, cell.y), step_time(s, span, cell.y + 1), rows[cell.x],
							DAWBackend.INSERT_VELOCITY, 0])
			_queue.clear()
			if notes.is_empty():
				return
			_asked_item_at = now
			DAW.insert_midi_take(track, span.x, span.y, notes, TRACK_NAME)
			if item_of(s, track, span) >= 0:
				_asked_item_at = -1
		elif now - _asked_item_at > WAIT_MS:
			_give_up("The music box's item did not arrive: press again.")
		return
	_asked_item_at = -1
	var it := s.item(track, item)
	if not Session.is_authority() and _sent_until > now and _notes_sig(it) == _sent_sig:
		return
	if it.locked:
		_give_up("%s's item is locked: unlock it on the timeline to change its pegs." % track_title(s, row))
		return
	var rows := rows_of(key_of(s, span), row)
	var found := pegs_of(s, track, item, span, rows)
	var deletes: Array[int] = []
	var inserts: Array = []
	for q: Array in _queue:
		var cell: Vector2i = q[0]
		if bool(q[1]):
			var on := step_time(s, span, cell.y) - it.start
			if found.has(cell) and int(found[cell]["mark"]) == 0:
				continue
			if on < -0.0005 or on >= it.length - MidiTake.MIN_NOTE:
				told.emit("Step %d is past the end of %s's item: lengthen it on the timeline." % [cell.y + 1, track_title(s, row)])
				_predicted.erase(cell)
				_dirty = true
				continue
			inserts.append([on, step_time(s, span, cell.y + 1) - it.start, rows[cell.x]])
		elif found.has(cell):
			for n: int in found[cell]["notes"]:
				if not deletes.has(n):
					deletes.append(n)
	_queue.clear()
	if deletes.is_empty() and inserts.is_empty():
		return
	_sent_sig = _notes_sig(it)
	_sent_until = now + WAIT_MS
	deletes.sort()
	deletes.reverse()
	for n in deletes:
		DAW.delete_note(track, item, n)
	for ins: Array in inserts:
		DAW.insert_note(track, item, float(ins[0]), float(ins[1]), int(ins[2]))


static func _notes_sig(it: MixState.ItemState) -> String:
	return str(it.notes) if it != null else ""


## Nothing waiting can be done: the queue dropped, what it showed taken back, and the player told why.
func _give_up(why: String) -> void:
	for q: Array in _queue:
		_predicted.erase(q[0])
	_queue.clear()
	_asked_track_at = -1
	_asked_item_at = -1
	_dirty = true
	told.emit(why)


## The view turned round `notches` steps (the wheel or a stick over the cylinder, the thumbwheel): this
## player's alone. A step on (+1) rolls the front of the brass up toward the comb, bringing up the steps
## from underneath.
func turn_view(notches: int) -> void:
	view_steps = posmod(view_steps + notches, STEPS)


## The step facing whoever stands in front now, at the front of the brass level with the axle.
func front_step() -> int:
	return posmod(roundi((COMB_ANGLE + shown_angle) / STEP_ANGLE), STEPS)


## How many pegs it shows, for its card.
func peg_count() -> int:
	return _shown.size()


# --- building it ------------------------------------------------------------------------------

## A warm strip under the lid's top edge and the light from it, down onto the cylinder, the rows'
## names and the keys: a dark corner of a venue still shows the pegs.
func _build_lamp() -> void:
	var strip := ZoneKit.block(self, Vector3(0.4, 0.01, 0.02), LAMP_AT, ZoneKit.glow(LAMP_COLOUR, 1.4), "LampStrip")
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := SpotLight3D.new()
	light.name = "BoxLight"
	light.light_color = LAMP_COLOUR
	light.light_energy = 0.8
	light.spot_range = 1.6
	light.spot_angle = 40.0
	light.spot_attenuation = 0.8
	light.shadow_enabled = false
	var aim := Vector3(0, DECK_Y + 0.06, KEY_Z * 0.6)
	light.transform = Transform3D(Basis.looking_at(aim - LAMP_AT, Vector3.UP), LAMP_AT)
	add_child(light)

## The cylinder's brass: brushed, not polished, so the lamp above lights it evenly rather than as one
## hotspot over the pegs in the middle.
func _brass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.6, 0.28)
	m.metallic = 0.75
	m.roughness = 0.62
	return m


## The cylinder and what turns with it: the brass, a hole at every cell, a groove at every beat (deeper
## at the first step), the step numbers round its right end, and the pegs.
func _build_turn() -> void:
	turn = Node3D.new()
	turn.name = "Turn"
	turn.position = AXIS
	add_child(turn)
	var brass := MeshInstance3D.new()
	brass.name = "Brass"
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = HALF * 2.0
	cyl.radial_segments = 48
	brass.mesh = cyl
	brass.rotation.z = PI * 0.5
	brass.material_override = _brass()
	turn.add_child(brass)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.08, 0.04)
	dark.roughness = 0.8
	var holes := MultiMeshInstance3D.new()
	holes.name = "Holes"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dot := CylinderMesh.new()
	dot.top_radius = 0.0025
	dot.bottom_radius = 0.0025
	dot.height = 0.0012
	dot.radial_segments = 8
	dot.rings = 1
	mm.mesh = dot
	mm.instance_count = ROWS * STEPS
	for r in ROWS:
		for st in STEPS:
			var cell := Vector2i(r, st)
			mm.set_instance_transform(r * STEPS + st, _radial(cell, 0.0))
	holes.multimesh = mm
	# The holes are only drilled brass, a little darker than the cylinder: so a dark peg seen end-on is
	# not mistaken for one.
	var drilled := StandardMaterial3D.new()
	drilled.albedo_color = Color(0.42, 0.29, 0.12)
	drilled.metallic = 0.6
	drilled.roughness = 0.6
	holes.material_override = drilled
	turn.add_child(holes)
	for st in range(0, STEPS, 4):
		var groove := MeshInstance3D.new()
		groove.name = "Beat%d" % st
		var bar := BoxMesh.new()
		# A few millimetres short of the rows' span at each end: the rows start at the brass's left
		# end, and a groove reaching it would end in the end's own plane.
		bar.size = Vector3(ROW_PITCH * ROWS - 0.006, 0.0012, 0.003 if st == 0 else 0.0015)
		groove.mesh = bar
		var theta := COMB_ANGLE - (st - 0.5) * STEP_ANGLE
		groove.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - theta),
				Vector3(ROW_LEFT + ROW_PITCH * ROWS * 0.5, RADIUS * sin(theta), RADIUS * cos(theta)))
		groove.material_override = dark
		turn.add_child(groove)
	for st in STEPS:
		var n := Label3D.new()
		n.name = "Step%d" % (st + 1)
		n.text = str(st + 1)
		n.pixel_size = 0.0002
		n.font_size = 70 if st % 4 == 0 else 52
		n.outline_size = 0
		n.modulate = Color(0.16, 0.1, 0.04)
		n.double_sided = false
		var theta := COMB_ANGLE - st * STEP_ANGLE
		n.transform = Transform3D(Basis(Vector3.RIGHT, -theta),
				Vector3(NUMBERS_X, (RADIUS + 0.0006) * sin(theta), (RADIUS + 0.0006) * cos(theta)))
		Lettering.range_to_legibility(n)
		turn.add_child(n)
	_pegs = Node3D.new()
	_pegs.name = "Pegs"
	turn.add_child(_pegs)
	_peg_mesh = CylinderMesh.new()
	_peg_mesh.top_radius = PEG_RADIUS * 0.8
	_peg_mesh.bottom_radius = PEG_RADIUS
	_peg_mesh.height = PEG_TALL
	_peg_mesh.radial_segments = 10
	_peg_mesh.rings = 1
	_head_mesh = SphereMesh.new()
	_head_mesh.radius = PEG_RADIUS * 0.8
	_head_mesh.height = PEG_RADIUS * 0.8
	_head_mesh.is_hemisphere = true
	_head_mesh.radial_segments = 10
	_head_mesh.rings = 3
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = MARK_RING - MARK_TUBE
	_ring_mesh.outer_radius = MARK_RING
	_ring_mesh.rings = 20
	_ring_mesh.ring_segments = 8
	# Blued steel, dark against the brass, so a peg reads by its shape and its shadow from across the
	# cylinder, not only by its glint.
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.07, 0.075, 0.09)
	_steel.metallic = 0.7
	_steel.roughness = 0.3
	# A peg's head and a marked peg's collar are bright steel: a dot, and a ring, standing out from the
	# brass and from the dark peg.
	_collar = StandardMaterial3D.new()
	_collar.albedo_color = Color(0.85, 0.86, 0.9)
	_collar.metallic = 0.6
	_collar.roughness = 0.35
	_build_thumbwheel()


## The knurled brass wheel on the axle past the right cheek, turning with the brass: its rim ridged
## across, so the ridges move under a finger that rolls it.
func _build_thumbwheel() -> void:
	var wheel := MeshInstance3D.new()
	wheel.name = "WheelBody"
	var body := CylinderMesh.new()
	body.top_radius = WHEEL_RADIUS - 0.002
	body.bottom_radius = WHEEL_RADIUS - 0.002
	body.height = WHEEL_WIDTH
	body.radial_segments = 40
	body.rings = 1
	wheel.mesh = body
	wheel.rotation.z = PI * 0.5
	wheel.position = Vector3(WHEEL_X, 0, 0)
	var brass := _brass()
	wheel.material_override = brass
	turn.add_child(wheel)
	var ridges := MultiMeshInstance3D.new()
	ridges.name = "Knurl"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var ridge := BoxMesh.new()
	ridge.size = Vector3(WHEEL_WIDTH - 0.004, 0.004, 0.004)
	mm.mesh = ridge
	mm.instance_count = 32
	for i in mm.instance_count:
		var a := TAU * i / mm.instance_count
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, -a),
				Vector3(WHEEL_X, (WHEEL_RADIUS - 0.002) * sin(a), (WHEEL_RADIUS - 0.002) * cos(a))))
	ridges.multimesh = mm
	ridges.material_override = brass
	turn.add_child(ridges)


## A frame at cell `cell` on the brass, `out` from it, its +Y out along the radius.
static func _radial(cell: Vector2i, out: float) -> Transform3D:
	var theta := COMB_ANGLE - cell.y * STEP_ANGLE
	return Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - theta), cell_local(cell, out))


## The pegs as `_shown` has them: a steel peg at each, its head polished bright, so one seen end-on is a
## bright dot ringed dark and never a hole; and at a marked one a collar round its foot and a lean toward
## where its pitch is.
func _draw_pegs() -> void:
	if _pegs == null:
		return
	for c in _pegs.get_children():
		_pegs.remove_child(c)
		c.queue_free()
	for cell: Vector2i in _shown:
		var mark := int(_shown[cell])
		var peg := MeshInstance3D.new()
		peg.name = "Peg%d_%d" % [cell.x, cell.y]
		peg.mesh = _peg_mesh
		peg.material_override = _steel
		var frame := _radial(cell, PEG_TALL * 0.5)
		if mark != 0:
			frame.basis = frame.basis * Basis(Vector3.BACK, -mark * MARK_LEAN)
			peg.set_meta(&"mark", mark)
			var ring := MeshInstance3D.new()
			ring.name = "Mark"
			ring.mesh = _ring_mesh
			ring.material_override = _collar
			ring.transform = _radial(cell, MARK_TUBE * 0.5)
			_pegs.add_child(ring)
		peg.transform = frame
		_pegs.add_child(peg)
		var head := MeshInstance3D.new()
		head.name = "Head"
		head.mesh = _head_mesh
		head.material_override = _collar
		head.position = Vector3(0, PEG_TALL * 0.5, 0)
		peg.add_child(head)


## The comb's eight teeth, one a row, from the plate's front edge forward over the cylinder's top, each
## on a pivot at its root so a flick lifts its tip.
func _build_comb() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.71, 0.74)
	steel.metallic = 0.9
	steel.roughness = 0.25
	var reach := AXIS.z + 0.004 - COMB_ROOT_Z
	for r in ROWS:
		var pivot := Node3D.new()
		pivot.name = "Tooth%d" % r
		pivot.position = Vector3(ROW_LEFT + ROW_PITCH * (r + 0.5), TOOTH_Y, COMB_ROOT_Z)
		var tooth := MeshInstance3D.new()
		var bar := BoxMesh.new()
		# Longer for the low rows, as a comb's teeth are.
		var long := reach + (ROWS - 1 - r) * 0.0015
		bar.size = Vector3(TOOTH.x - 0.004, TOOTH.y, long)
		tooth.mesh = bar
		tooth.position = Vector3(0, 0, long * 0.5)
		tooth.material_override = steel
		pivot.add_child(tooth)
		add_child(pivot)
		teeth.append(pivot)


## The rail between the cylinder and the keys: a plate tipped up toward the player as the keys are,
## its face lettered with each row's note under its row.
func _build_rail() -> void:
	var tip := Basis(Vector3.RIGHT, KEY_TILT)
	var middle := Vector3(RAIL_X, DECK_Y + RAIL.y * 0.5 + RAIL.z * 0.5 * sin(KEY_TILT), RAIL_Z)
	var rail := MeshInstance3D.new()
	rail.name = "Rail"
	var bar := BoxMesh.new()
	bar.size = RAIL
	rail.mesh = bar
	rail.transform = Transform3D(tip, middle)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.12, 0.07, 0.04)
	wood.roughness = 0.5
	rail.material_override = wood
	add_child(rail)
	var face := middle + tip * Vector3(0, RAIL.y * 0.5 + 0.0006, 0)
	for r in ROWS:
		var n := Label3D.new()
		n.name = "Row%d" % r
		n.pixel_size = 0.0002
		n.font_size = 96
		n.outline_size = 0
		n.modulate = Color(0.95, 0.88, 0.7)
		n.shaded = false
		n.double_sided = false
		n.transform = Transform3D(Basis(Vector3.RIGHT, -(PI * 0.5 - KEY_TILT)),
				Vector3(ROW_LEFT + ROW_PITCH * (r + 0.5), face.y, face.z))
		Lettering.range_to_legibility(n)
		add_child(n)
		_names.append(n)


## The cylinder, as a control: every cell is a click on it, a fingertip's touch or a pinch's ray, and a
## drag along a row is a run. It does not turn itself (its drag plane stays upright through the axle);
## the brass and the pegs turn on `turn`.
class Drum extends ControlAffordance:
	var box: MusicBox

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = RADIUS + PEG_TALL * 0.6
		cyl.height = (ROW_PITCH * ROWS)
		shape.shape = cyl
		shape.rotation.z = PI * 0.5
		shape.position = Vector3(ROW_LEFT + ROW_PITCH * ROWS * 0.5, 0, 0)
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "MUSIC BOX"

	func _default_readout() -> String:
		if box == null:
			return ""
		var s := DAW.state
		var key := MusicBox.key_of(s, box.span)
		return "%d peg%s · %s · %s from %s · %d bar%s a turn" % [box.peg_count(), "" if box.peg_count() == 1 else "s",
				MusicBox.track_title(s, box.row), "chromatic" if bool(box.row[3]) else key.key_name,
				key.note_name(MusicBox.base_of(key, box.row)), box.length(), "" if box.length() == 1 else "s"]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "press a cell (a fingertip or a pinch) for a peg, a peg to take it out · along a row for a run, one undo step · roll the wheel at its right end, or the stick over it, to turn the back steps round"
		return "click a cell for a peg, a peg to take it out · drag along a row for a run, one undo step · the wheel turns it round a step, or drag the knurled wheel at its right end"

	func _local(at: Vector3) -> Vector3:
		return box.global_transform.affine_inverse() * at

	func _on_grab_begin(at: Vector3) -> void:
		if box == null:
			return
		var p := _local(at)
		box.begin_gesture(box.cell_at(p), p)

	func _on_grab_move(at: Vector3) -> void:
		if box == null:
			return
		var p := _local(at)
		box.extend_gesture(box.cell_at(p), p)

	func _on_grab_end() -> void:
		if box != null:
			box.end_gesture()

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if box == null:
			return false
		box.turn_view(signi(notches))
		return true


## A key on the case's front: TRACK, LENGTH, ROOT or SCALE. A press steps it on; the wheel, or a
## controller's stick, steps it either way.
class SettingKey extends ControlAffordance:
	var box: MusicBox
	var kind := 0
	var legend: Label3D

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(KEY.x, KEY.y, 0.02)
		shape.shape = b
		add_child(shape)
		var face := MeshInstance3D.new()
		face.name = "Face"
		var slab := BoxMesh.new()
		slab.size = Vector3(KEY.x - 0.008, KEY.y - 0.008, 0.008)
		face.mesh = slab
		face.position = Vector3(0, 0, -0.003)
		var cap := StandardMaterial3D.new()
		cap.albedo_color = Color(0.2, 0.13, 0.08)
		cap.roughness = 0.55
		face.material_override = cap
		add_child(face)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.pixel_size = 0.0002
		legend.font_size = 78
		legend.outline_size = 0
		legend.modulate = Color(0.96, 0.9, 0.76)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.position = Vector3(0, 0, 0.0015)
		Lettering.range_to_legibility(legend)
		add_child(legend)

	func show_legend(text: String) -> void:
		legend.text = text
		Lettering.fit(legend, KEY.x - 0.014, 78, 40)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return true

	func _default_title() -> String:
		return "MUSIC BOX  %s" % MusicBox.Kind.keys()[kind]

	func _default_readout() -> String:
		if box == null:
			return ""
		var s := DAW.state
		match kind:
			MusicBox.Kind.TRACK:
				var t := MusicBox.track_of(s, box.row)
				return "the pegs are %s's item" % MusicBox.track_title(s, box.row) if t > 0 \
						else "a new MUSIC BOX track, made with the first peg"
			MusicBox.Kind.LENGTH:
				return "a turn is %d bar%s: a step is a 1/%d note" % [box.length(), "" if box.length() == 1 else "s",
						MusicBox.STEPS / box.length()]
			MusicBox.Kind.ROOT:
				var key := MusicBox.key_of(s, box.span)
				var by := int(box.row[2])
				return "the lowest row is %s: the key's tonic%s" % [key.note_name(MusicBox.base_of(key, box.row)),
						"" if by == 0 else " %+d" % by]
			MusicBox.Kind.SCALE:
				return "the rows are semitones" if bool(box.row[3]) else "the rows are %s's scale" % MusicBox.key_of(s, box.span).key_name
		return ""

	func hint() -> String:
		var either := "the stick" if InstrumentItem.hands_hint else "the wheel"
		match kind:
			MusicBox.Kind.TRACK:
				return "press for the next track · %s steps either way · MUSIC BOX makes its own" % either
			MusicBox.Kind.LENGTH:
				return "press for 1, 2 or 4 bars a turn · %s steps either way" % either
			MusicBox.Kind.ROOT:
				return "press for a semitone up, round an octave · %s moves it either way" % either
		return "press: the key's scale or chromatic"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if box != null:
			box.step_setting(kind, 1, true)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if box == null:
			return false
		box.step_setting(kind, signi(notches))
		return true


## The knurled wheel on the axle past the right cheek: the brass turned round by hand. Pushed up or
## down at its front (a fingertip's touch and slide, a pinch's or a click's drag on the upright plane
## through the axle), it turns the view round a step every WHEEL_RADIUS * STEP_ANGLE of the hand's
## travel, the front of the brass going the way the hand does; a press that does not move it turns it
## a step on; the wheel or a stick over it, a step either way. This player's own, as the view is.
class Thumbwheel extends ControlAffordance:
	var box: MusicBox
	## The point's height the drag is measured from (the box's frame), the view's steps when the grab
	## began, and whether it has moved a step since. The height is taken at the first move, not at the
	## grab: a ray's grab lands on the front of the fat collision cylinder, while every move after it
	## is that ray's hit on the upright plane through the axle, a few centimetres further back, and
	## for a ray sloping down at the wheel those two heights differ by more than a step.
	var _from_y := NAN
	var _from_steps := 0
	var _rolled := false

	func _init() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		# A little fatter than the wheel, so a fingertip finds its rim.
		cyl.radius = WHEEL_RADIUS + 0.008
		cyl.height = WHEEL_WIDTH + 0.01
		shape.shape = cyl
		shape.rotation.z = PI * 0.5
		add_child(shape)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "MUSIC BOX  TURN"

	func _default_readout() -> String:
		if box == null:
			return ""
		return "step %d at the front · steps %d to %d face you" % [box.front_step() + 1,
				posmod(box.front_step() - 3, STEPS) + 1, posmod(box.front_step() + 4, STEPS) + 1]

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "push it up or down with a fingertip, or pinch and drag, to turn the brass round · a press turns it a step · the stick either way"
		return "drag it up or down to turn the brass round · click for a step on · the wheel either way"

	func _local(at: Vector3) -> Vector3:
		return box.global_transform.affine_inverse() * at

	func _on_grab_begin(at: Vector3) -> void:
		if box == null:
			return
		_from_y = NAN
		_from_steps = box.view_steps
		_rolled = false

	func _on_grab_move(at: Vector3) -> void:
		if box == null:
			return
		if is_nan(_from_y):
			_from_y = _local(at).y
			return
		var by := roundi((_local(at).y - _from_y) / (WHEEL_RADIUS * STEP_ANGLE))
		if by != 0:
			_rolled = true
		box.view_steps = posmod(_from_steps + by, STEPS)

	func _on_grab_end() -> void:
		if box != null and not _rolled:
			box.turn_view(1)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		if box == null:
			return false
		box.turn_view(signi(notches))
		return true
