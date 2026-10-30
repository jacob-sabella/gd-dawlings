class_name MarbleRun
extends Node3D

## A marble run (docs/spatial_loop.md part two, slice 49, idea #35), in the lattice zone, which no
## other kept idea uses: blocks put in the lattice's cells, and a marble rolling through them in time
## with the song, each bell block it rolls through ringing its note.
##
## The lattice is CELLS cells of CELL on every side, a SIDE cube on the zone's floor. A block in a cell
## is a room row (`marbles` {cell: [kind, facing]}, Vector3i cells), asked with the room verb `marble`
## [cell, kind, facing] (an empty kind takes the block out) and answered by `answer`, the same rule on
## both sides: a cell outside the lattice, a kind not known, a facing not one of four, and a block past
## MOST are refused in words. The kinds (KINDS), each told by its shape (tools/blender/marble_blocks.py):
## - a RAMP rolls the marble on into the next cell the way it faces;
## - a DROP drops it into the cell under it;
## - a SPLITTER sends one marble the way it faces and the next the other way (by the marble's number:
##   its bar, or a BALL's sixteenth), its brass vane tipped toward where the bar's marble goes;
## - a BELL rolls it on the way it faces, and rings as it rolls through: the scale degree its height
##   gives (its row up from the floor, from the key's tonic nearest LOW: VenueInstrument.scale_tone,
##   Harmony.at), so a run that falls plays down the scale.
##
## A marble is let go at the run's top (`top_of`: the highest block, the front-most and then left-most
## of those) at the start of every bar, and on the tray's BALL key on the next beat (the room's row
## `marble_balls`, its beats, asked with `marble_ball` [beat]). It travels a cell each sixteenth from
## there, the path walked from the blocks (`path`), never physics, so its notes fall on the grid: into
## an empty cell, or out of the lattice, it falls out of the run and is gone; a run that goes round in
## a ring ends after MOST_STEPS. Marbles are the room's, like rain (Weather): every machine computes
## them from the song clock and the rows (`rings`), they never touch mix state, and they are recorded
## only through the run's `marbles` jack into a track, where the host takes each ring down
## (HitRecorder.note), heard or not. With the song stopped, BALL rolls one here alone at the song's
## tempo (a preview, never recorded), so a run can be tried as it is built.
##
## This node carries the station `marbles` (Stations.ALL, zone-mounted in the lattice): its origin on
## the floor at the middle of the lattice's face toward the desk (`frame_in`), +Z out of that face
## toward the desk, the cells behind it (-Z). It carries the blocks (`Block`), the marbles drawn, and
## at that face, TRAY_X to its right, its tray (`Tray`), where the station's spot is (Venue.marbles_spot,
## `spot_in`): a board on a post with a well for each kind (`TrayKey`) and the BALL key, its plaque
## (Stations.plaque, folded) and its jack. Off the face's middle, the seat sees past it.
##
## Building, at a desk: a click on a tray key gives the mouse that block (Interactor.tool, as the
## string spool gives an end); each click then puts one in the cell the cursor picks (`pick`): on the
## working layer (the floor at first; Shift and the wheel raise it), or beside the face of a block it
## meets, the wheel turning it first. A click on a placed block picks it up to put somewhere else, the
## wheel over one turns it, Backspace takes it out, Esc puts what the mouse carries back. In a headset:
## take a block from the tray and let it go in a cell (the one the hand is in), or carry it from a tap
## and press there; take a placed one and let it go in another cell to move it, outside the lattice to
## take it out, or where it was to turn it; the stick turns one. Motion is Ergonomics' motion_scale: a
## marble glides between cells and a rung bell swings; at 0 the marble shows the cell it is in a step
## per beat, still, and the bells hang still.

## A block a hand here asks for (an empty kind takes it out), for the studio to do or ask.
signal block_asked(cell: Vector3i, kind: StringName, facing: int)
## The BALL key pressed while the song plays: a marble on beat `beat`, for the studio to do or ask.
signal ball_asked(beat: float)
## A marble rang a bell here: {song, beat, marble, step, cell, note, velocity, length, source,
## preview}. Fired as the song plays past it, on every machine; a preview's only here.
signal rang(ring: Dictionary)
## Something to say to this player.
signal told(text: String)

## The station, its room rows and the verbs that ask for them (Session.ROOM_VERBS).
const STATION := &"marbles"
const ROW := &"marbles"
const VERB := &"marble"
const BALLS := &"marble_balls"
const BALL_VERB := &"marble_ball"
## Its jack's source (Jack.WORLD): no item, onto a track only.
const SOURCE := &"marbles"
## A cell's side, how many cells each way, and the lattice's side (m).
const CELL := 0.25
const CELLS := 12
const SIDE := CELL * CELLS
## A sixteenth, in the tempo map's quarter-note beats: a marble's step.
const SIXTEENTH := 0.25
## The most cells one marble travels: two bars of 4/4, a ring of ramps' end.
const MOST_STEPS := 32
## The most blocks the lattice holds, and the most BALL marbles the room keeps.
const MOST := 144
const MOST_BALLS := 8
## A bell's note: the scale tone its height gives, up from the key's tonic nearest this (C5).
const LOW := 72
const VELOCITY := 84
## How long a ring's note is, taken down (s).
const LENGTH := 0.6
## The sound a bell block rings with (Foley.VENUE_BAR_SOUNDS), and how loud over its velocity's own.
const SOUND := &"chime"
const LEVEL_DB := -4.0
## A jump of the song this far or more (s), or back, is a seek: nothing between rings.
const JUMP := 1.0
## No cell: the run's top where it has no blocks, and no block lifted.
const NONE := Vector3i(-1, -1, -1)

const RAMP := &"ramp"
const DROP := &"drop"
const SPLIT := &"split"
const BELL := &"bell"
const KINDS: Array[StringName] = [RAMP, DROP, SPLIT, BELL]
const TITLES := {&"ramp": "RAMP", &"drop": "DROP", &"split": "SPLITTER", &"bell": "BELL"}
## What each does, for its cards.
const DOES := {
	&"ramp": "rolls the marble on into the next cell, the way it faces",
	&"drop": "drops the marble into the cell under it",
	&"split": "sends one marble the way it faces and the next the other way",
	&"bell": "rings its height's note as the marble rolls through, and rolls it on the way it faces",
}
## The four ways a block faces, as seen from the tray, and the cell each rolls the marble into.
const FACINGS := ["AWAY", "RIGHT", "TOWARD YOU", "LEFT"]
const DIRS: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)]
const DOWN := Vector3i(0, -1, 0)

## The blocks and the tray (tools/blender/marble_blocks.py). Every block's out end is -Z (AWAY).
const MODEL := "res://assets/models/marble_blocks.glb"
## Half a block's side, and the slab's top over its cell's middle (the groove a little under it).
const BLOCK := 0.11
const SLAB_TOP := -0.03
## A marble: its radius, and its middle over its cell's, rolling in the groove.
const MARBLE_RADIUS := 0.026
const MARBLE_Y := -0.036
## Where a bell hangs from its arch, and how far it swings when rung (radians) and for how long (s).
const BELL_PIN := Vector3(0, 0.075, 0)
const SWING := 0.45
const SWING_TIME := 0.7
## The splitter's vane's pin, and how far it tips toward where the marble goes (radians).
const VANE_PIN := Vector3(0, -0.06, 0)
const VANE_TIP := 0.42
## The tray: off to the face's right of its middle (so the seat sees past it into the lattice and the
## room behind), its foot (half, x and z) and its middle along Z, out in front of the lattice's face; its
## board's middle, half its size, how far it tips toward you (radians) and its wells along it, the
## first four the kinds in KINDS' order and the last the BALL key; and its top, the board's back edge.
const TRAY_X := 1.05
const TRAY_FOOT := Vector2(0.18, 0.1)
const TRAY_Z := 0.12
const BOARD_Y := 1.1
const BOARD := Vector3(0.36, 0.0125, 0.09)
const BOARD_TILT := 0.35
const WELLS: Array[float] = [-0.26, -0.13, 0.0, 0.13, 0.26]
const WELL := 0.05
const TRAY_TOP := 1.144
## The plaque, leant back under the board's front edge: its width, its top edge and its lean.
const PLAQUE_WIDTH := 0.56
const PLAQUE_TOP := Vector3(0, 1.03, 0.21)
const PLAQUE_LEAN := 0.35
## The station's frame (Stations.ALL), in the station's spot (`spot_in`, the tray's): above the board's
## back edge, and its plaque's keys' feet, folded.
const FRAME_TOP := Vector3(0, 1.32, 0.02)
const FRAME_FOOT := Vector3(0, 0.87, 0.27)
## What a player at the tray looks at, in the station's spot: into the lattice behind it, toward its middle.
const LOOK := Vector3(-TRAY_X * 0.5, 1.25, -0.9)
## How far a hand carries a block from where it took it before its let-go puts it down (m): less is
## a tap, which leaves the block in the hand for a press where it goes.
const CARRIED := 0.12
## The most marbles drawn at once.
const MOST_DRAWN := 24

## The room's blocks, as `answer` keeps them: {Vector3i: [kind, facing]}. The studio's (`show_rows`).
var rows: Dictionary = {}
## The room's BALL marbles: the beats they are let go at.
var balls: Array = []
## Where the song is, here: {seconds, playing, valid}. GuestMidi.heard by default; the suite gives its own.
var heard_source: Callable = Callable()
## How much of a marble's movement to show, 0..1: Ergonomics' motion_scale by default.
var motion: Callable = Callable()
## The working layer a ray puts a block on (0 the floor), this player's own.
var layer := 0
## The way a block taken from the tray faces at first, this player's own: the last one turned.
var facing := 0
## The hand carrying a block, what it carries, and the cell it was lifted from (NONE for one off the tray).
var hand: Interactor = null
var carry_kind := &""
var carry_facing := 0
var lifted := NONE
## Where the carried block would go now ({cell, valid, against, layer}), for the ghost and the suite.
var target := {}
var tray: Node3D
var keys: Array[TrayKey] = []
var ball_key: TrayKey
var jack: JackSocket
## Its socket on the modular's patch (slice 53, `world:marbles`), beside the jack: a gate each bell
## rung, patched into the modular wall from the tray (ModularWorld).
var modular: WorldSocket
## How many bells have rung aloud here, for the suite.
var rung := 0
## The song position the rings have been played up to, or NAN while the song is not playing.
var _until := NAN
## A preview marble rolling with the song stopped: seconds it has rolled, and the beat length (s); empty for none.
var _preview := {}
var _blocks := {}
var _blocks_holder: Node3D
var _marbles: MultiMeshInstance3D
var _ghost: MeshInstance3D
var _ghost_cell: MeshInstance3D
var _ghost_letter: Label3D
var _layer_grid: MeshInstance3D
var _ghost_ink: StandardMaterial3D
var _down := false
## The button is still held from the press that took the block: let go away from there, it is put
## where the hand is (its cell, or out of the lattice), never where its ray points.
var _since_take := false
var _took_at := Vector3.ZERO
var _take := 0
var _paths := {}
var _paths_for := -1

static var _meshes := {}


func _init() -> void:
	name = "MarbleRun"


func _ready() -> void:
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	# The lattice's edges, a hair inside the cube so a venue's own outline of it never fights them.
	frame.mesh = ZoneKit.edges(Vector3(SIDE - 0.02, SIDE - 0.01, SIDE - 0.02), 0.014)
	frame.position = Vector3(0, SIDE * 0.5, -SIDE * 0.5)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.5, 0.3)
	brass.metallic = 0.7
	brass.roughness = 0.45
	frame.material_override = brass
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)
	_blocks_holder = Node3D.new()
	_blocks_holder.name = "Blocks"
	add_child(_blocks_holder)
	_build_tray()
	_build_marbles()
	_build_ghost()
	show_rows(rows)


# --- the lattice --------------------------------------------------------------------------------

## The middle of `cell` in the run's frame: x across from the face's left, y up, z back from its face.
static func cell_centre(cell: Vector3i) -> Vector3:
	return Vector3(-SIDE * 0.5 + (cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL, -(cell.z + 0.5) * CELL)


## The cell `p` (the run's frame) is in, inside the lattice or not.
static func cell_at(p: Vector3) -> Vector3i:
	return Vector3i(floori((p.x + SIDE * 0.5) / CELL), floori(p.y / CELL), floori(-p.z / CELL))


## Whether `cell` is one of the lattice's.
static func inside(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < CELLS and cell.y < CELLS and cell.z < CELLS


## A block's turn for `way` (FACINGS): its out end, -Z, toward where it rolls the marble.
static func facing_basis(way: int) -> Basis:
	return Basis(Vector3.UP, -float(posmod(way, 4)) * PI * 0.5)


## The run's frame standing in front of lattice zone `lattice` (studio space): on the floor at the
## middle of its cube's face toward the control room (the zone's -Z side), turned to face it.
static func frame_in(lattice: AABB) -> Transform3D:
	var c := lattice.get_center()
	return Transform3D(Basis(Vector3.UP, PI), Vector3(c.x, 0.0, c.z - SIDE * 0.5))


## The station's spot for lattice zone `lattice` (Venue.marbles_spot): the run's frame (`frame_in`)
## moved along the face to the tray, TRAY_X, so its seat is in front of the tray.
static func spot_in(lattice: AABB) -> Transform3D:
	return frame_in(lattice).translated_local(Vector3(TRAY_X, 0, 0))


## The run's frame for its station's spot `spot` (`spot_in`): back along the face from the tray.
static func frame_at(spot: Transform3D) -> Transform3D:
	return spot.translated_local(Vector3(-TRAY_X, 0, 0))


## The tray's footprint for the walker, at the station's frame `at` ({c, h, a, top}), named as the
## station's own so its clearance leaves it out of its own air.
static func tray_solid(at: Transform3D) -> Dictionary:
	var middle := at * Vector3(TRAY_X, 0, TRAY_Z)
	return {"c": Vector2(middle.x, middle.z), "h": TRAY_FOOT, "a": at.basis.get_euler().y, "top": TRAY_TOP,
			"station": STATION}


# --- the rows -----------------------------------------------------------------------------------

## The room's word on block `kind` facing `way` in `cell`, done to `rows` where it may be: empty, or
## why not, in words. An empty kind takes the block out (nothing there, nothing to do). The same rule
## on the host and, before it asks, on a guest.
static func answer(at: Dictionary, cell: Vector3i, kind: StringName, way: int) -> String:
	if not inside(cell):
		return "That cell is outside the lattice: a block goes in one of its %d by %d by %d cells." % [CELLS, CELLS, CELLS]
	if kind == &"":
		at.erase(cell)
		return ""
	if not KINDS.has(kind):
		return "There is no block called %s: a ramp, a drop, a splitter or a bell." % kind
	if way < 0 or way > 3:
		return "A block faces one of four ways."
	if not at.has(cell) and at.size() >= MOST:
		return "The lattice holds %d blocks, the most it takes: take one out first (Backspace over it, or pull it out)." % MOST
	at[cell] = [kind, way]
	return ""


## The room's word on a BALL marble at `beat`: `held` with it, the oldest let go past MOST_BALLS, or
## `held` as it was for a beat that cannot be one.
static func answer_ball(held: Array, beat: float) -> Array:
	var out := held.duplicate()
	if is_nan(beat) or is_inf(beat) or beat < 0.0 or out.has(beat):
		return out
	out.append(beat)
	out.sort()
	while out.size() > MOST_BALLS:
		out.pop_front()
	return out


## The run's top: its highest block, the front-most of those and then the left-most. NONE with none.
static func top_of(at: Dictionary) -> Vector3i:
	var best := NONE
	for cell: Vector3i in at:
		if best == NONE or cell.y > best.y or (cell.y == best.y and (cell.z < best.z or (cell.z == best.z and cell.x < best.x))):
			best = cell
	return best


## The cells marble number `number` is in, a sixteenth each from its letting go: from the top, each
## block saying where next (a splitter by the number's parity), ending where it rolls into an empty
## cell (that cell its last: it falls out there) or would leave the lattice, or after MOST_STEPS.
static func path(at: Dictionary, number: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var cell := top_of(at)
	if cell == NONE:
		return out
	out.append(cell)
	while out.size() < MOST_STEPS:
		var block: Variant = at.get(cell)
		if block == null:
			break
		var way := int(block[1])
		var next := cell
		match StringName(block[0]):
			DROP:
				next = cell + DOWN
			SPLIT:
				next = cell + DIRS[posmod(way + (0 if posmod(number, 2) == 0 else 2), 4)]
			_:
				next = cell + DIRS[posmod(way, 4)]
		if not inside(next):
			break
		out.append(next)
		cell = next
	return out


## The note bell `cell` rings at song position `song`: the scale tone of its height.
static func note_of(state: MixState, song: float, cell: Vector3i) -> int:
	return VenueInstrument.scale_tone(Harmony.at(state, song), LOW, cell.y)


## The marbles let go that may be rolling at some beat from `first` up to `last`: [beat let go, its
## number] each, the bars' (their numbers their bars, from 0) and the BALL marbles' (their beats, so
## one a beat after another goes the other way through a splitter; `let_go` asks such a beat).
static func marbles_from(state: MixState, held: Array, first: float, last: float) -> Array:
	var out: Array = []
	var meter := state.meter()
	var reach := MOST_STEPS * SIXTEENTH
	var bar := maxi(floori(meter.bar_at(maxf(first - reach, 0.0)) + 0.000001), 0)
	for n in 4096:
		var at := meter.beat_of_bar(float(bar))
		if at > last:
			break
		out.append([at, bar])
		bar += 1
	for beat in held:
		if float(beat) <= last and float(beat) + reach > first:
			out.append([float(beat), ball_number(float(beat))])
	return out


## The number of the BALL marble let go on `beat`: its beat, whole (let_go only asks whole beats).
static func ball_number(beat: float) -> int:
	return roundi(beat)


## The beat a BALL marble asked when the song is on `beat` goes on, with `held` the ones let go: the
## next whole beat, or the one after when that one would go the same way through a splitter as the
## newest still rolling, so each BALL goes the other way from the last (and two presses before it
## comes are two marbles).
static func ball_beat(held: Array, beat: float) -> float:
	var next := ceilf(beat + 0.05)
	var newest := -INF
	for b in held:
		newest = maxf(newest, float(b))
	if newest + MOST_STEPS * SIXTEENTH > next:
		next = maxf(next, floorf(newest) + 1.0)
		if posmod(ball_number(next), 2) == posmod(ball_number(newest), 2):
			next += 1.0
	return next


## Every ring of a bell in `at` from song position `from` up to, not including, `to`, in the song
## `state`, with BALL marbles `held`, in order: each {song (s), beat, marble (its number), step (its
## sixteenth from its letting go), cell, note, velocity, length, source}. The same on every machine.
static func rings(at: Dictionary, held: Array, state: MixState, from: float, to: float) -> Array:
	var out: Array = []
	if at.is_empty() or state == null or to <= from:
		return out
	var first := state.beat_at(maxf(from, 0.0))
	var last := state.beat_at(maxf(to, 0.0))
	if last <= first:
		return out
	var paths := {}
	for m: Array in marbles_from(state, held, first, last):
		var parity := posmod(int(m[1]), 2)
		if not paths.has(parity):
			paths[parity] = path(at, int(m[1]))
		var cells: Array = paths[parity]
		for i in cells.size():
			var beat := float(m[0]) + float(i) * SIXTEENTH
			if beat >= last:
				break
			if beat < first:
				continue
			var block: Variant = at.get(cells[i])
			if block == null or StringName(block[0]) != BELL:
				continue
			var song := state.seconds_at_beat(beat)
			out.append({"song": song, "beat": beat, "marble": int(m[1]), "step": i, "cell": cells[i],
					"note": note_of(state, song, cells[i]), "velocity": VELOCITY, "length": LENGTH, "source": SOURCE})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["beat"]) < float(b["beat"]) or (float(a["beat"]) == float(b["beat"]) and int(a["marble"]) < int(b["marble"])))
	return out


## Where each marble rolling at beat `beat` is, in the run's frame, with how strongly it shows (0..1):
## [position, show] each. With motion it glides from cell to cell, and falls a little as it fades
## from its last; at motion 0 it is still in the cell it was in on the beat, a step per beat.
static func marbles_at(at: Dictionary, held: Array, state: MixState, beat: float, moves: float) -> Array:
	var out: Array = []
	if at.is_empty() or state == null:
		return out
	var paths := {}
	for m: Array in marbles_from(state, held, beat, beat):
		var since := beat - float(m[0])
		if since < 0.0:
			continue
		var parity := posmod(int(m[1]), 2)
		if not paths.has(parity):
			paths[parity] = path(at, int(m[1]))
		out.append_array(_marble_on(paths[parity], since, moves))
	return out


## One marble `since` beats into its path `cells`: [[position, show]], or none once it is gone.
static func _marble_on(cells: Array, since: float, moves: float) -> Array:
	if cells.is_empty():
		return []
	var f := since / SIXTEENTH
	if moves <= 0.0:
		# A step per beat: the cell it was in on the beat, still.
		var on := floori(since + 0.000001) * int(1.0 / SIXTEENTH)
		if on >= cells.size():
			return []
		return [[cell_centre(cells[on]) + Vector3(0, MARBLE_Y, 0), 1.0]]
	var i := floori(f)
	if i >= cells.size():
		return []
	var t := f - float(i)
	var here := cell_centre(cells[i]) + Vector3(0, MARBLE_Y, 0)
	if i + 1 < cells.size():
		var there := cell_centre(cells[i + 1]) + Vector3(0, MARBLE_Y, 0)
		return [[here.lerp(there, t), 1.0]]
	# Its last cell: it falls out of the run there, fading.
	return [[here - Vector3(0, CELL * 0.6 * t * t * moves, 0), clampf(1.0 - t, 0.0, 1.0)]]


# --- picking a cell -----------------------------------------------------------------------------

## The cell a ray from `origin` along `along` (the run's frame) puts a block in, with `at` the blocks
## there and `on_layer` the working layer: {cell, valid, against (the block whose face it meets, or
## NONE), layer (whether it came down on the working layer)}. Walking the cells the ray passes through,
## the first block it meets puts it in the empty cell it came through before; reaching the working
## layer's floor first puts it in the cell standing there. Nothing met, or a block met at the lattice's
## edge with no cell before it, is not valid.
static func pick(at: Dictionary, origin: Vector3, along: Vector3, on_layer: int) -> Dictionary:
	var none := {"cell": NONE, "valid": false, "against": NONE, "layer": false}
	if along.length_squared() < 0.000001:
		return none
	# Into the lattice's grid: a unit a cell, x from the left, y up, z back from the face.
	var o := Vector3((origin.x + SIDE * 0.5) / CELL, origin.y / CELL, -origin.z / CELL)
	var d := Vector3(along.x, along.y, -along.z).normalized()
	var t_in := 0.0
	var t_out := INF
	for k in 3:
		if absf(d[k]) < 0.0000001:
			if o[k] < 0.0 or o[k] > float(CELLS):
				return none
			continue
		var a := (0.0 - o[k]) / d[k]
		var b := (float(CELLS) - o[k]) / d[k]
		t_in = maxf(t_in, minf(a, b))
		t_out = minf(t_out, maxf(a, b))
	if t_in > t_out:
		return none
	# Where the ray comes down (or up) to the working layer's floor, if it does inside the lattice.
	var t_layer := INF
	if absf(d.y) > 0.0000001:
		var tl := (float(on_layer) - o.y) / d.y
		if tl >= t_in - 0.000001 and tl <= t_out + 0.000001:
			var q := o + d * tl
			var c := Vector3i(floori(q.x), clampi(on_layer, 0, CELLS - 1), floori(q.z))
			if inside(c):
				t_layer = tl
	# Walk the cells (Amanatides and Woo) until a block, the layer, or out.
	var p := o + d * (t_in + 0.00001)
	var cell := Vector3i(clampi(floori(p.x), 0, CELLS - 1), clampi(floori(p.y), 0, CELLS - 1), clampi(floori(p.z), 0, CELLS - 1))
	var step := Vector3i(1 if d.x > 0 else -1, 1 if d.y > 0 else -1, 1 if d.z > 0 else -1)
	var t_max := Vector3.ZERO
	var t_delta := Vector3.ZERO
	for k in 3:
		if absf(d[k]) < 0.0000001:
			t_max[k] = INF
			t_delta[k] = INF
		else:
			var edge := float(cell[k] + (1 if d[k] > 0 else 0))
			t_max[k] = (edge - o[k]) / d[k]
			t_delta[k] = absf(1.0 / d[k])
	var before := NONE
	var t_now := t_in
	for n in CELLS * 3 + 3:
		if not inside(cell):
			break
		if at.has(cell):
			if t_layer < t_now:
				break
			return {"cell": before, "valid": before != NONE and not at.has(before), "against": cell, "layer": false}
		before = cell
		var k := 0
		if t_max.y < t_max[k]:
			k = 1
		if t_max.z < t_max[k]:
			k = 2
		t_now = t_max[k]
		cell[k] += step[k]
		t_max[k] += t_delta[k]
	if t_layer < INF:
		var q := o + d * t_layer
		var c := Vector3i(floori(q.x), clampi(on_layer, 0, CELLS - 1), floori(q.z))
		return {"cell": c, "valid": not at.has(c), "against": NONE, "layer": true}
	return none


## Where the block hand `h` carries would go now: for a hand in the lattice (not a mouse), the cell it
## is in; else the cell its ray picks (`pick`), the lifted block's own cell counted empty. A hand
## still holding the press that took the block (`_since_take`), and not pointing, has no ray: out of
## the lattice it goes nowhere, so letting go there takes a lifted block out or puts one back.
func target_for(h: Interactor) -> Dictionary:
	var to_local := global_transform.affine_inverse()
	var among := rows
	if lifted != NONE:
		among = rows.duplicate()
		among.erase(lifted)
	if not (h is MouseInteractor):
		var p := to_local * h.catch_point()
		var c := cell_at(p)
		if inside(c):
			return {"cell": c, "valid": true, "against": NONE, "layer": false, "hand": true}
		if h == hand and _since_take and not h.pointing:
			return {"cell": NONE, "valid": false, "against": NONE, "layer": false, "hand": true}
	var a := h.aim()
	return pick(among, to_local * a.origin, to_local.basis * -a.basis.z, layer)


# --- carrying a block ---------------------------------------------------------------------------

## Whether a hand here is carrying a block.
func carrying() -> bool:
	return hand != null and is_instance_valid(hand) and hand.tool == _on_tool


## Whether the mouse here is carrying one: its wheel turns it and Esc puts it back.
func carried_by_mouse() -> bool:
	return carrying() and hand is MouseInteractor


## A block of `kind` from the tray to `by`'s hand (a poke's goes to its ray, RoomString.tying_hand),
## facing as the last one turned; or, if that hand already carries one off the tray of that kind, back
## on the tray.
func take(by: Node, kind: StringName) -> void:
	var h := RoomString.tying_hand(by)
	if h == null:
		return
	if carrying() and hand == h and lifted == NONE and carry_kind == kind:
		drop("The %s is back on the tray." % str(TITLES[kind]).to_lower())
		return
	_carry(h, kind, facing, NONE)
	told.emit(_take_words(h))


## Block `cell` picked up by `by`'s hand, to put somewhere else.
func lift(by: Node, cell: Vector3i) -> void:
	var h := RoomString.tying_hand(by)
	var block: Variant = rows.get(cell)
	if h == null or block == null:
		return
	_carry(h, StringName(block[0]), int(block[1]), cell)
	if h is MouseInteractor:
		told.emit("%s picked up: click the cell it goes in, Backspace takes it out, Esc puts it back · the wheel turns it" % str(TITLES[carry_kind]))
	else:
		told.emit("%s in hand: let it go in another cell, outside the lattice to take it out, or where it was to turn it" % str(TITLES[carry_kind]))
	_show_lifted()


func _carry(h: Interactor, kind: StringName, way: int, from: Vector3i) -> void:
	drop()
	if h.tool.is_valid():
		h.tool = Callable()
	hand = h
	carry_kind = kind
	carry_facing = way
	lifted = from
	_down = false
	_since_take = true
	_took_at = h.catch_point()
	h.tool = _on_tool
	h.tool_stick = _on_stick


func _take_words(h: Interactor) -> String:
	var what := str(TITLES[carry_kind])
	if h is MouseInteractor:
		return "%s: click a cell for one, on the lattice's floor or beside a block's face · the wheel turns it, Shift + wheel raises the layer · Esc puts it back" % what
	return "%s: let it go in the cell your hand is in, or carry it and press there · the stick turns it · press the tray to put it back" % what


## A headset hand's stick while it carries a block here, whatever it hovers (Interactor.tool_stick):
## a flick turns the block, a fine one moves the layer its ray puts it on, as the wheel does a mouse's.
func _on_stick(h: Interactor, notches: int, fine: bool) -> bool:
	if not carrying() or h != hand or notches == 0:
		return false
	if fine:
		move_layer(signi(notches))
	else:
		turn_carried(signi(notches))
	return true


## What the hand carries put back (on the tray, or in its cell, unchanged): `words` said, if any.
func drop(words := "") -> void:
	if hand != null and is_instance_valid(hand) and hand.tool == _on_tool:
		hand.tool = Callable()
		hand.tool_stick = Callable()
	hand = null
	carry_kind = &""
	lifted = NONE
	_down = false
	_since_take = false
	target = {}
	_show_lifted()
	_show_ghost()
	if words != "":
		told.emit(words)


## The carried block turned a quarter (`by` 1 clockwise from above, -1 back), and the next one off
## the tray facing so too.
func turn_carried(by: int) -> void:
	if not carrying():
		return
	carry_facing = posmod(carry_facing + by, 4)
	if lifted == NONE:
		facing = carry_facing
	_show_ghost()


## The working layer a ray puts blocks on, up or down a cell.
func move_layer(by: int) -> void:
	layer = clampi(layer + by, 0, CELLS - 1)
	_show_ghost()


## The carrying hand's button: a press on the tray takes another (or the same one puts it back, BALL
## lets a marble go); a mouse's press puts the block where it points; a hand's let-go where it is,
## once it has carried it off (a tap leaves it in the hand for a press where it goes, the ray's).
func _on_tool(h: Interactor, down: bool) -> void:
	if h != hand:
		return
	var mouse := h is MouseInteractor
	if down:
		_down = true
		var key := h.hovered as TrayKey
		if key != null and key.run == self:
			if key.kind == &"":
				let_go()
			else:
				take(h, key.kind)
			_down = false
			return
		if mouse:
			put(h)
		return
	if not _down and (mouse or h.catch_point().distance_to(_took_at) < CARRIED):
		# A tap: the block stays in the hand, and the next press puts it where the ray points.
		_since_take = false
		return
	_down = false
	if not mouse:
		put(h)


## The block `h` carries put where it would go (`target_for`): asked of the room, a lifted one out of
## where it was first. A mouse keeps one off the tray to put more; a moved block and a hand's are put
## down. A hand let go outside the lattice takes a lifted block out, and puts one off the tray back:
## carried there from the press that took it, wherever its ray points (`target_for`).
func put(h: Interactor) -> void:
	if not carrying() or h != hand:
		return
	var t := target_for(h)
	if not t.get("valid", false):
		if h is MouseInteractor:
			told.emit("Point into the lattice: at its floor (or the layer Shift + wheel raises), or at a block's face for the cell beside it · Esc puts the block back")
			return
		if lifted != NONE:
			var from := lifted
			drop("The %s is out of the lattice." % str(TITLES[carry_kind]).to_lower())
			block_asked.emit(from, &"", 0)
		else:
			drop("The block is back on the tray.")
		return
	var cell: Vector3i = t["cell"]
	var kind := carry_kind
	var way := carry_facing
	var from := lifted
	if from != NONE and from == cell and not (h is MouseInteractor) and way == int((rows.get(from, [kind, way]) as Array)[1]):
		# A hand letting a block go where it was: turned a quarter.
		way = posmod(way + 1, 4)
	if from != NONE or not (h is MouseInteractor):
		drop()
	if from != NONE and from != cell:
		block_asked.emit(from, &"", 0)
	block_asked.emit(cell, kind, way)


## Block `cell` taken out, for everyone: Backspace over it, or over the one the mouse lifted.
func take_out(cell: Vector3i) -> void:
	if carrying() and lifted == cell:
		drop()
	if rows.has(cell):
		var words := "The %s is out of the lattice." % str(TITLES.get(StringName(rows[cell][0]), "block")).to_lower()
		block_asked.emit(cell, &"", 0)
		told.emit(words)


## Backspace over `control` (what the mouse hovers or holds): the block it is, or the one the mouse
## carries lifted. True if it was the run's.
func take_out_under(control: Node) -> bool:
	if carried_by_mouse() and lifted != NONE:
		take_out(lifted)
		return true
	var block := control as Block
	if block == null or block.run != self:
		return false
	take_out(block.cell)
	return true


## Block `cell` turned a quarter (`by` 1 clockwise from above), for everyone.
func turn(cell: Vector3i, by: int) -> void:
	var block: Variant = rows.get(cell)
	if block == null:
		return
	var way := posmod(int(block[1]) + by, 4)
	if StringName(block[0]) == DROP:
		told.emit("A drop drops the marble straight down, whichever way it faces.")
	block_asked.emit(cell, StringName(block[0]), way)


# --- the marbles --------------------------------------------------------------------------------

func heard() -> Dictionary:
	if heard_source.is_valid():
		return heard_source.call()
	if Session.guest_midi != null:
		return Session.guest_midi.heard()
	return {"seconds": 0.0, "playing": false, "valid": false}


func _motion() -> float:
	if motion.is_valid():
		return clampf(float(motion.call()), 0.0, 1.0)
	return Ergonomics.current.motion_scale if Ergonomics.current != null else 1.0


## The BALL key: with the song playing, a marble on the next beat (`ball_beat`: the one after if the
## next would go the same way through a splitter as the last), for everyone (`ball_asked`); with it
## stopped, one rolled here alone at the song's tempo, to try the run.
func let_go() -> void:
	if rows.is_empty():
		told.emit("The lattice is empty: take a block from the tray and put it in a cell, the highest one the run's top.")
		return
	var h := heard()
	if h.get("valid", false) and h.get("playing", false) and DAW.state != null:
		ball_asked.emit(ball_beat(balls, DAW.state.beat_at(float(h["seconds"]))))
		return
	var s := DAW.state
	var at := s.position_seconds if s != null else 0.0
	var beat := s.beat_at(at) if s != null else 0.0
	var spb := (s.seconds_at_beat(beat + 1.0) - s.seconds_at_beat(beat)) if s != null else 0.5
	_preview = {"t": 0.0, "spb": maxf(spb, 0.05), "song": at, "step": -1, "cells": path(rows, 0)}
	told.emit("A marble rolls from the top here alone, at the song's tempo: play the song for one every bar, heard by everyone.")


func _process(delta: float) -> void:
	follow(heard(), delta)
	_show_ghost()


## One frame of the song as heard (`h`), `delta` seconds on: every bell the marbles have rolled
## through since the last frame rings (`ring`), a preview rolls on, and the marbles are drawn. A jump
## (a seek, the loop going round, a stop) rings nothing between.
func follow(h: Dictionary, delta := 0.0) -> void:
	var now := float(h.get("seconds", 0.0))
	var playing: bool = h.get("valid", false) and h.get("playing", false)
	if not playing:
		_until = NAN
	elif is_nan(_until) or now < _until or now - _until >= JUMP:
		_until = now
	elif now > _until:
		for r: Dictionary in rings(rows, balls, DAW.state, _until, now):
			ring(r)
		_until = now
	if playing:
		_preview = {}
	_follow_preview(delta)
	_draw(now if playing else NAN)
	_tend_bells(delta, now if playing else NAN)


## Bell `r["cell"]` ringing: heard from the block, its bell swung, and said (`rang`), for the jack.
func ring(r: Dictionary) -> void:
	rung += 1
	_take += 1
	var block := _blocks.get(r["cell"]) as Block
	if block != null:
		block.swung = SWING_TIME
	if is_inside_tree():
		var stream := Foley.venue_bar(SOUND, _take)
		var player := Foley.emitter(stream, linear_to_db(float(r["velocity"]) / 127.0) + LEVEL_DB,
				pow(2.0, float(int(r["note"]) - Foley.venue_bar_note(SOUND)) / 12.0))
		player.name = "Ring"
		player.position = cell_centre(r["cell"])
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	rang.emit(r)


func _follow_preview(delta: float) -> void:
	if _preview.is_empty():
		return
	_preview["t"] = float(_preview["t"]) + delta
	var cells: Array = _preview["cells"]
	var step := floori(float(_preview["t"]) / (float(_preview["spb"]) * SIXTEENTH))
	while int(_preview["step"]) < mini(step, cells.size() - 1):
		_preview["step"] = int(_preview["step"]) + 1
		var cell: Vector3i = cells[int(_preview["step"])]
		var block: Variant = rows.get(cell)
		if block != null and StringName(block[0]) == BELL:
			var song := float(_preview["song"])
			ring({"song": song, "beat": 0.0, "marble": 0, "step": int(_preview["step"]), "cell": cell,
					"note": note_of(DAW.state, song, cell), "velocity": VELOCITY, "length": LENGTH,
					"source": SOURCE, "preview": true})
	if step > cells.size():
		_preview = {}


## The marbles drawn now, in the run's frame ([position, show] each): the room's at song position
## `now` (NAN while the song is stopped), and a preview's.
func drawn(now := NAN) -> Array:
	var moves := _motion()
	var out: Array = []
	if not is_nan(now) and DAW.state != null:
		out = marbles_at(rows, balls, DAW.state, DAW.state.beat_at(now), moves)
	if not _preview.is_empty():
		out.append_array(_marble_on(_preview["cells"], float(_preview["t"]) / float(_preview["spb"]), moves))
	return out


func _draw(now: float) -> void:
	if _marbles == null:
		return
	var mm := _marbles.multimesh
	var at := 0
	for each: Array in drawn(now):
		if at >= MOST_DRAWN:
			break
		mm.set_instance_transform(at, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * lerpf(0.5, 1.0, float(each[1]))), each[0]))
		at += 1
	mm.visible_instance_count = at


## Each bell swinging as it dies away, and each splitter's vane tipped toward where the marble the song
## is on this bar goes; at motion 0 the bells hang still.
func _tend_bells(delta: float, now: float) -> void:
	var moves := _motion()
	var bar := 0
	if not is_nan(now) and DAW.state != null:
		bar = maxi(floori(DAW.state.meter().bar_at(DAW.state.beat_at(now)) + 0.000001), 0)
	for cell: Vector3i in _blocks:
		var b := _blocks[cell] as Block
		if b.bell != null:
			b.swung = maxf(b.swung - delta, 0.0)
			var left := b.swung / SWING_TIME
			b.bell.rotation.x = SWING * left * left * sin(b.swung * 26.0) * moves
		if b.vane != null:
			# Its lowered end the way the bar's marble goes: the out end (-Z) on an even bar.
			b.vane.rotation.x = -VANE_TIP if posmod(bar, 2) == 0 else VANE_TIP


# --- showing the rows ---------------------------------------------------------------------------

## The room's blocks as `given` has them, here: each stood in its cell, turned its way, the ones gone
## taken out.
func show_rows(given: Dictionary) -> void:
	rows = given.duplicate()
	if lifted != NONE and not rows.has(lifted):
		drop()
	if _blocks_holder == null:
		return
	for cell: Vector3i in _blocks.keys():
		var b := _blocks[cell] as Block
		var r: Variant = rows.get(cell)
		if r == null or StringName(r[0]) != b.kind:
			_blocks.erase(cell)
			_blocks_holder.remove_child(b)
			b.queue_free()
	for cell: Vector3i in rows:
		var r: Array = rows[cell]
		var b := _blocks.get(cell) as Block
		if b == null:
			b = Block.new()
			b.run = self
			b.cell = cell
			b.kind = StringName(r[0])
			b.name = "Block_%d_%d_%d" % [cell.x, cell.y, cell.z]
			b.position = cell_centre(cell)
			_blocks_holder.add_child(b)
			_blocks[cell] = b
		b.set_facing(int(r[1]))
	_show_lifted()


## The block standing in `cell`, or null.
func block_at(cell: Vector3i) -> Block:
	return _blocks.get(cell) as Block


## How many blocks stand in the lattice.
func block_count() -> int:
	return _blocks.size()


func _show_lifted() -> void:
	for cell: Vector3i in _blocks:
		var b := _blocks[cell] as Block
		b.visible = cell != lifted


# --- building it --------------------------------------------------------------------------------

## The mesh named `part` in the blocks' model (tools/blender/marble_blocks.py), or a stand-in box.
static func part(name_of: String) -> Mesh:
	if _meshes.is_empty() and ResourceLoader.exists(MODEL):
		var scene := (load(MODEL) as PackedScene).instantiate()
		for m: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			_meshes[String(m.name)] = m.mesh
		scene.free()
	if _meshes.has(name_of):
		return _meshes[name_of]
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK * 2.0, 0.085, BLOCK * 2.0)
	return box


## The mesh a kind's block is drawn with.
static func mesh_of(kind: StringName) -> Mesh:
	match kind:
		DROP:
			return part("Drop")
		SPLIT:
			return part("Splitter")
		BELL:
			return part("Bell")
	return part("Ramp")


## Where the tray's board is, in the tray's frame (the run's, TRAY_X along): tipped toward whoever
## stands at it.
static func board_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, BOARD_TILT), Vector3(0, BOARD_Y, TRAY_Z))


func _build_tray() -> void:
	tray = Node3D.new()
	tray.name = "Tray"
	tray.position = Vector3(TRAY_X, 0, 0)
	add_child(tray)
	var stand := MeshInstance3D.new()
	stand.name = "Stand"
	stand.mesh = part("Tray")
	tray.add_child(stand)
	var board := Node3D.new()
	board.name = "Board"
	board.transform = board_frame()
	tray.add_child(board)
	for n in WELLS.size():
		var key := TrayKey.new()
		key.run = self
		key.kind = KINDS[n] if n < KINDS.size() else &""
		key.name = ("Take" + str(TITLES[key.kind]).capitalize()) if key.kind != &"" else "Ball"
		key.position = Vector3(WELLS[n], BOARD.y, 0)
		board.add_child(key)
		if key.kind != &"":
			keys.append(key)
		else:
			ball_key = key
	var plaque := Stations.plaque(STATION, PLAQUE_WIDTH)
	var top := float(plaque.get_meta(&"plaque_tall", 0.2)) * 0.5
	var lean := Basis(Vector3.RIGHT, -PLAQUE_LEAN)
	plaque.transform = Transform3D(lean, PLAQUE_TOP - lean * Vector3(0, top, 0))
	tray.add_child(plaque)
	jack = JackSocket.new(null, SOURCE)
	jack.label = "MARBLE RUN"
	# Off the board's left end, the lattice's middle's side, facing out of the station's front, toward
	# whoever stands at it.
	jack.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-BOARD.x - 0.05, BOARD_Y - 0.02, TRAY_Z + 0.03))
	tray.add_child(jack)
	modular = WorldSocket.new(&"world:marbles")
	modular.position = Vector3(-BOARD.x - 0.05 - WorldSocket.BESIDE, BOARD_Y - 0.02, TRAY_Z + 0.03)
	tray.add_child(modular)


func _build_marbles() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.82, 0.9, 1.0)
	glass.metallic = 0.35
	glass.roughness = 0.08
	glass.rim_enabled = true
	glass.rim = 0.4
	var ball := SphereMesh.new()
	ball.radius = MARBLE_RADIUS
	ball.height = MARBLE_RADIUS * 2.0
	ball.radial_segments = 16
	ball.rings = 8
	ball.material = glass
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ball
	mm.instance_count = MOST_DRAWN
	for n in MOST_DRAWN:
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), Vector3.ZERO))
	mm.visible_instance_count = 0
	_marbles = MultiMeshInstance3D.new()
	_marbles.name = "Marbles"
	_marbles.multimesh = mm
	add_child(_marbles)


func _build_ghost() -> void:
	_ghost_ink = StandardMaterial3D.new()
	_ghost_ink.albedo_color = Color(0.95, 0.9, 0.78, 0.45)
	_ghost_ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.material_override = _ghost_ink
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.97, 0.93, 0.82, 0.8)
	line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_cell = MeshInstance3D.new()
	_ghost_cell.name = "GhostCell"
	_ghost_cell.mesh = ZoneKit.edges(Vector3.ONE * (CELL - 0.01), 0.005)
	_ghost_cell.material_override = line
	_ghost_cell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_cell.visible = false
	add_child(_ghost_cell)
	_ghost_letter = Label3D.new()
	_ghost_letter.name = "GhostLetter"
	_ghost_letter.pixel_size = 0.0004
	_ghost_letter.font_size = 64
	_ghost_letter.modulate = Color(0.97, 0.93, 0.82)
	_ghost_letter.visible = false
	Lettering.range_to_legibility(_ghost_letter)
	add_child(_ghost_letter)
	# The working layer: the lattice's grid of cells at its height, while a ray puts a block on it.
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for n in CELLS + 1:
		var u := -SIDE * 0.5 + float(n) * CELL
		grid.surface_add_vertex(Vector3(u, 0, 0))
		grid.surface_add_vertex(Vector3(u, 0, -SIDE))
		grid.surface_add_vertex(Vector3(-SIDE * 0.5, 0, -float(n) * CELL))
		grid.surface_add_vertex(Vector3(SIDE * 0.5, 0, -float(n) * CELL))
	grid.surface_end()
	_layer_grid = MeshInstance3D.new()
	_layer_grid.name = "LayerGrid"
	_layer_grid.mesh = grid
	var faint := line.duplicate() as StandardMaterial3D
	faint.albedo_color = Color(0.97, 0.93, 0.82, 0.3)
	_layer_grid.material_override = faint
	_layer_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_layer_grid.visible = false
	add_child(_layer_grid)


## Where the carried block would go, drawn: a pale copy of it turned its way in the cell, the cell's
## edges, and the working layer's grid while the ray comes down on it. What it is, which way it faces
## and the layer are lettered for its tray key's card (`ghost_text`), never floated over the lattice:
## words in the air were too much of the room (2026-10-29). Nothing while nothing is carried.
func _show_ghost() -> void:
	if _ghost == null:
		return
	if not carrying():
		_ghost.visible = false
		_ghost_cell.visible = false
		_ghost_letter.text = ""
		_layer_grid.visible = false
		return
	target = target_for(hand)
	var ok: bool = target.get("valid", false)
	var cell: Vector3i = target.get("cell", NONE)
	_ghost.visible = ok
	_ghost_cell.visible = ok
	_layer_grid.visible = not target.get("hand", false)
	_layer_grid.position = Vector3(0, float(layer) * CELL + 0.002, 0)
	if ok:
		_ghost.mesh = mesh_of(carry_kind)
		_ghost.transform = Transform3D(facing_basis(carry_facing), cell_centre(cell))
		_ghost_cell.position = cell_centre(cell)
		_ghost_letter.position = cell_centre(cell) + Vector3(0, CELL * 0.7, 0)
		_ghost_letter.text = carry_words(cell)
	elif target.get("hand", false):
		# Carried out of the lattice: what letting go here does.
		_ghost_letter.position = Vector3(0, CELL * 0.5, 0.1)
		_ghost_letter.text = "%s · let go here to %s" % [str(TITLES[carry_kind]),
				"take it out" if lifted != NONE else "put it back on the tray"]
	else:
		_ghost_letter.position = Vector3(0, float(layer) * CELL + 0.3, 0.1)
		_ghost_letter.text = "%s  %s · point into the lattice · LAYER %d" % [str(TITLES[carry_kind]), FACINGS[carry_facing], layer + 1]


## What the ghost in `cell` says: the block, the way it faces (a drop none), a bell its note, and the layer.
func carry_words(cell: Vector3i) -> String:
	var way := "" if carry_kind == DROP else "  %s" % FACINGS[carry_facing]
	var note := ""
	if carry_kind == BELL and DAW.state != null:
		var h := Harmony.at(DAW.state, DAW.state.position_seconds)
		note = "  %s" % h.note_name(VenueInstrument.scale_tone(h, LOW, cell.y))
	return "%s%s%s · LAYER %d" % [str(TITLES[carry_kind]), way, note, cell.y + 1]


## What the ghost says now, "" while nothing is carried: for the carried kind's tray key's card,
## and the suite.
func ghost_text() -> String:
	return _ghost_letter.text if _ghost_letter != null and carrying() else ""


## What a block says on its card: its kind, the way it faces, a bell's note now, and where it is.
func block_words(cell: Vector3i) -> String:
	var r: Variant = rows.get(cell)
	if r == null:
		return ""
	var kind := StringName(r[0])
	var bits := [str(DOES[kind])]
	if kind != DROP:
		bits[0] = "%s: %s" % [FACINGS[int(r[1])].to_lower(), bits[0]]
	if cell == top_of(rows):
		bits.append("the run's top: each marble starts here")
	bits.append("layer %d, %d across, %d back" % [cell.y + 1, cell.x + 1, cell.z + 1])
	return " · ".join(bits)


## A placed block: its kind's slab turned the way it rolls the marble, a bell's arch and bell (it
## swings when rung) with its note on its card (the letter that said it over the bell kept, never
## shown), a splitter's vane. A click picks it up to put somewhere
## else (a hand takes it), the wheel or a stick turns it, Backspace takes it out (the studio's key).
class Block extends ControlAffordance:
	var run: MarbleRun
	var cell := Vector3i.ZERO
	var kind := &"ramp"
	var way := 0
	var body: MeshInstance3D
	var bell: Node3D
	var vane: Node3D
	var letter: Label3D
	## How long the bell has left to swing (s).
	var swung := 0.0

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(BLOCK * 2.0, 0.16 if kind == BELL else 0.1, BLOCK * 2.0)
		shape.shape = box
		shape.position = Vector3(0, -0.04 if kind == BELL else -0.07, 0)
		add_child(shape)
		body = MeshInstance3D.new()
		body.name = "Body"
		body.mesh = MarbleRun.mesh_of(kind)
		add_child(body)
		if kind == BELL:
			var arch := MeshInstance3D.new()
			arch.name = "Arch"
			arch.mesh = MarbleRun.part("BellArch")
			body.add_child(arch)
			bell = Node3D.new()
			bell.name = "Bell"
			bell.position = BELL_PIN
			body.add_child(bell)
			var cup := MeshInstance3D.new()
			cup.mesh = MarbleRun.part("BellBell")
			bell.add_child(cup)
			letter = Label3D.new()
			letter.name = "Note"
			letter.pixel_size = 0.0004
			letter.font_size = 70
			letter.modulate = Color(0.96, 0.92, 0.82)
			letter.outline_size = 6
			letter.position = Vector3(0, 0.13, 0)
			# Lettered for its card's title, never shown.
			letter.visible = false
			Lettering.range_to_legibility(letter)
			add_child(letter)
		elif kind == SPLIT:
			vane = Node3D.new()
			vane.name = "Vane"
			vane.position = VANE_PIN
			body.add_child(vane)
			var plate := MeshInstance3D.new()
			plate.mesh = MarbleRun.part("SplitterVane")
			vane.add_child(plate)

	## Turned to face `to` (FACINGS).
	func set_facing(to: int) -> void:
		way = posmod(to, 4)
		if body != null:
			body.basis = MarbleRun.facing_basis(way)

	func _process(_delta: float) -> void:
		if letter != null and DAW.state != null:
			var h := Harmony.at(DAW.state, DAW.state.position_seconds)
			letter.text = h.note_name(VenueInstrument.scale_tone(h, LOW, cell.y))

	func personal() -> bool:
		return true

	func _default_title() -> String:
		var t := str(TITLES.get(kind, "BLOCK"))
		if kind == BELL and letter != null:
			t += "  " + letter.text
		return t

	func _default_readout() -> String:
		return run.block_words(cell) if run != null else ""

	func hint() -> String:
		if InstrumentItem.hands_hint:
			return "take it and let it go in another cell to move it, outside the lattice to take it out, or where it was to turn it · the stick turns it"
		return "click to pick it up, then click where it goes · the wheel turns it · Backspace takes it out"

	func _on_grab_begin(_at: Vector3) -> void:
		var hand := held_by
		grab_end(hand)
		if run != null:
			run.lift(hand, cell)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if run == null:
			return false
		if run.carrying():
			if fine:
				run.move_layer(signi(notches))
			else:
				run.turn_carried(signi(notches))
			return true
		run.turn(cell, signi(notches))
		return true


## A well on the tray: a block of its kind to take (a small one lies in it, lettered underneath), or
## the BALL key (`kind` empty), a marble in its cup.
class TrayKey extends ControlAffordance:
	var run: MarbleRun
	var kind := &""
	var legend: Label3D

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WELL * 2.0 + 0.02, 0.07, WELL * 2.0 + 0.04)
		shape.shape = box
		shape.position = Vector3(0, 0.02, 0)
		add_child(shape)
		var shown := MeshInstance3D.new()
		shown.name = "Shown"
		if kind != &"":
			shown.mesh = MarbleRun.mesh_of(kind)
			# A small one, lying in the well with its out end away from you.
			shown.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.4), Vector3(0, 0.04, 0))
		else:
			var ball := SphereMesh.new()
			ball.radius = MARBLE_RADIUS
			ball.height = MARBLE_RADIUS * 2.0
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.82, 0.9, 1.0)
			glass.metallic = 0.35
			glass.roughness = 0.08
			ball.material = glass
			shown.mesh = ball
			shown.position = Vector3(0, MARBLE_RADIUS - 0.006, 0)
		add_child(shown)
		legend = Label3D.new()
		legend.name = "Legend"
		legend.pixel_size = 0.0002
		legend.font_size = 90
		legend.outline_size = 0
		legend.modulate = Color(0.96, 0.92, 0.82)
		legend.shaded = false
		legend.double_sided = false
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		legend.text = str(TITLES[kind]) if kind != &"" else "BALL"
		# On the board in front of the well, lying on it.
		legend.rotation.x = -PI * 0.5
		legend.position = Vector3(0, 0.002, WELL + 0.022)
		Lettering.range_to_legibility(legend)
		Lettering.fit(legend, WELL * 2.0 + 0.02, 90, 50)
		add_child(legend)

	func personal() -> bool:
		return true

	func dwell_activates() -> bool:
		return false

	func _default_title() -> String:
		return "MARBLE RUN  %s" % (str(TITLES[kind]) if kind != &"" else "BALL")

	func _default_readout() -> String:
		if run == null:
			return ""
		if kind == &"":
			return "%d block%s · a marble rolls from the top each bar, a cell a sixteenth" % [run.block_count(), "" if run.block_count() == 1 else "s"]
		# Carrying one of these: where it would go, as the ghost would have said over it.
		if run.carrying() and run.carry_kind == kind and run.ghost_text() != "":
			return run.ghost_text()
		return str(DOES[kind])

	func hint() -> String:
		var hands := InstrumentItem.hands_hint
		if kind == &"":
			return "press for a marble on the next beat · with the song stopped, one rolls here alone" if hands \
					else "click for a marble on the next beat · with the song stopped, one rolls here alone to try the run"
		if hands:
			return "take one and let it go in a cell · the stick turns it"
		return "click to take one, then click cells: on the lattice's floor, or beside a block's face · the wheel turns it, Shift + wheel raises the layer"

	func grab_begin(by: Node, at: Vector3) -> void:
		super(by, at)
		if held_by != by or run == null:
			return
		grab_end(by)
		if kind == &"":
			run.let_go()
		else:
			run.take(by, kind)

	func _on_nudge(notches: int, fine: bool) -> bool:
		if run == null or not run.carrying():
			return false
		if fine:
			run.move_layer(signi(notches))
		else:
			run.turn_carried(signi(notches))
		return true
