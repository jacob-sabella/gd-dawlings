class_name MiniatureItem
extends Item

## The session in miniature (docs/spatial_loop.md part two, slice 34, idea #6): a 40 cm model of
## the whole song to hold, on a wooden tray (tools/blender/miniature.py). Its tracks are strips,
## lettered with their names at the left, their items blocks on them; the regions are bands along
## its far edge, the markers flags there (a sticky note, a `NOTE ` marker, a card pinned to its
## time), the loop a bracket over them, and the playhead a line that moves across it all as the song
## plays, a step a beat at motion 0. Round its lip stand the room's stations as pins, lettered, each
## on the side of the tray its station is on as seen from the mix position, so it is a compass too.
##
## It is for getting to things. Pointing at a spot (a ray onto it, the other hand's fingertip on it,
## the mouse over it) names it in the hover card, its track and its time; a press there seeks the
## song to that time and brings that track's gear: the console banks to the track and comes. A
## press on an item selects it and brings the timeline, scrolled to it, instead. A press on a pin
## goes to that station: a headset travels there, a desk walks there (Studio.go_to_station). None
## of that is this item's: it says what was pressed (`pressed`, `station_pressed`) and the studio
## does it, as the tablet says what its plugs were dropped on.
##
## A room item like the duck (ItemRoom.KINDS), not a personal one: its home is the desk's left
## wing (Venue.miniature_spot), and anyone can carry it, or take it from a bandmate. Taken hold of
## by its front edge, since its bed is all buttons; at a desk, clicked there, or pressed where it
## lies.
##
## Laid out in its own frame, `_content`'s: the reader stands at +Z, the song's time runs along +X,
## its first track is the far strip. The item's own frame faces -Z, as every item does, so the
## content is turned half round in it.

const KIND := &"miniature"
const MODEL := "res://assets/models/miniature.glb"
## The tray, as tools/blender/miniature.py builds it: its footprint, how wide its lip is all round,
## the felt bed's top (where the strips lie) and the lip's (where the pins stand).
const SIZE := Vector2(0.40, 0.30)
const BAND := 0.03
const BED_TOP := 0.020
const LIP_TOP := 0.024
## The bed inside the lip, in the content frame's x and z.
const BED := Rect2(-0.17, -0.12, 0.34, 0.24)
## The track names' column at the bed's left, and the ruler's band along its far edge (regions,
## markers, the loop).
const NAMES := 0.062
const RULER := 0.032
## What is left of the bed past the strips' right end and their near one.
const MARGIN := 0.004
## A strip's gap to the next, and the most a strip is deep, so a song of three tracks is not three
## planks.
const STRIP_GAP := 0.0012
const STRIP_MOST := 0.03
## How tall an item's block stands, and a selected one: taller, not only brighter.
const BLOCK_TALL := 0.004
const SELECTED_TALL := 0.007
## The narrowest a block is drawn, so a short item can still be seen and pointed at.
const BLOCK_LEAST := 0.002
## The seam left between an item and the next where they meet.
const BLOCK_SEAM := 0.0007
## The most blocks drawn: past this, a ninety-track session's last items are left off.
const BLOCKS_MOST := 800
## A strip thinner than this is not lettered: nobody could read it.
const NAMED_LEAST := 0.005
## The lettering's scale: a cap of font size x PIXEL metres.
const PIXEL := 0.0001
## Where it is taken hold of: a strip along its front edge this deep, reaching this far in over the
## lip, short of the pins.
const GRIP_DEEP := 0.016
const GRIP_IN := 0.006
## Pins: how far in from the tray's edge they stand, how far apart round it at least, how tall,
## and their heads; their names lie on the lip this far further in.
const PIN_IN := 0.008
const PIN_GAP := 0.062
const PIN_TALL := 0.016
const PIN_HEAD := 0.0035
const PIN_NAME_IN := 0.013
## The flags: their poles' height, and the loop bracket's above the ruler.
const FLAG_TALL := 0.016
const BRACKET_HIGH := 0.022
const NOTE_PREFIX := Harmony.NOTE_PREFIX
const INK := Color(0.9, 0.9, 0.86)
const DIM := Color(0.55, 0.56, 0.58)
const STRIP := Color(0.13, 0.14, 0.16)
const REGION := [Color(0.52, 0.42, 0.24), Color(0.36, 0.30, 0.19)]
const FLAG := Color(0.95, 0.78, 0.35)
const NOTE_CARD := Color(0.96, 0.92, 0.55)
const LOOP := Color(0.36, 0.62, 0.98)
const LOOP_OFF := Color(0.34, 0.40, 0.52)
const PLAYHEAD := Color(1.0, 0.92, 0.62)
## A pin's head, by its station's area. Each is lettered too.
const PIN_HEADS := {&"control": Color(0.45, 0.7, 0.95), &"live": Color(0.95, 0.6, 0.3), &"venue": Color(0.6, 0.85, 0.5)}
## Where a desktop's hand holds it, in the eye's frame: low in the middle of the view, far enough
## that the whole tray is in it, and tipped up toward the eye (VIEW_TIP of the way from lying flat).
const VIEW_AT := Vector3(0.0, -0.13, -0.74)
const VIEW_TIP := 0.82
## Carried in a hand: how far its far edge is tipped up toward you, and how far its side stays clear
## of that hand's own ray (`held_pose`).
const HELD_TIP := 0.55
const HELD_CLEAR := 0.04
## Up as +Z, for the bed and the pins: a fingertip's press (PokeInteractor) lets go as the finger
## lifts along a control's +Z, and a held ray moves in its XY (Interactor._plane_point). What they
## show is turned back by its inverse.
const FACE_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

## A press on the bed: `track` (0 for the ruler, where there is none), the song time under it
## (`seconds`, or negative on a track's name, which names no time), and the item there (-1 none).
signal pressed(track: int, seconds: float, item: int)
## A press on station `id`'s pin.
signal station_pressed(id: StringName)

## The stations standing here, for the pins: [[id, title, area, bearing]], `bearing` a Vector2 in
## the room's plan (x, z) from the mix position toward it. The studio's (`set_stations`).
var stations: Array = []
## The bed, as a control: what the hover card names and a press presses.
var face: Face = null
## {id: Pin}.
var pins: Dictionary = {}
## The strips as drawn, one a track in order: {track, name (Label3D or null), blocks: [[item
## index, MeshInstance3D]]}.
var strips: Array = []
## The regions' bands and the markers' flags as drawn: [[start, MeshInstance3D, Label3D]] and
## [[seconds, Node3D, Label3D or null, is a note]].
var bands: Array = []
var flags: Array = []

var _content: Node3D
var _drawn: Node3D
var _pins_node: Node3D
var _playhead: MeshInstance3D
var _bracket: Node3D
var _clock: Label3D
var _dirty := true
var _shape_key := []
var _key_clock := 0.0
var _drawn_loop := Vector3(-1, -1, -1)
var _clock_text := ""
var _mats: Dictionary = {}


func _init() -> void:
	id = KIND
	super()
	# Along the item's -Z edge, which is the content's +Z: the reader's. Its middle just inside the
	# edge, in front of the pins standing on the lip there, so a click on the edge is the tray's.
	_shape.position = Vector3(0, (LIP_TOP + 0.006) * 0.5, -SIZE.y * 0.5 + GRIP_IN - GRIP_DEEP * 0.5)


func item_title() -> String:
	return "SESSION IN MINIATURE"


func hint() -> String:
	return _hint("click its front edge to carry it · point at its bed and press: play from there, its gear comes · a pin goes to that station")


## The tray, turned half round so its reader is at the item's -Z. Only the tray: what is drawn on it
## is the song's, built once it is in a room (`_ready`), so a bandmate's ghost carries a bare tray.
func _build_body() -> Node3D:
	var root := Node3D.new()
	_content = Node3D.new()
	_content.name = "Content"
	_content.transform = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	root.add_child(_content)
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Tray"
	_content.add_child(model)
	# Matte and dark, so the bright things on it are what is seen, under a work light at arm's length.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.15, 0.085)
	wood.roughness = 0.85
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.035, 0.04, 0.05)
	felt.roughness = 1.0
	var swap := {"wood": wood, "felt": felt}
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for n in mesh.mesh.get_surface_count():
			var m := mesh.mesh.surface_get_material(n)
			if m != null and swap.has(m.resource_name):
				mesh.set_surface_override_material(n, swap[m.resource_name])
	return root


## Its near edge, the reader's, where a tray is taken hold of: the edge of its lip there and a little
## past it.
## Only there, since its bed is all buttons (`face`) and its other edges carry the pins. A box whose
## face is square to the reader, as a click from the desk's seat finds it.
func _grip_shape() -> Shape3D:
	var s := BoxShape3D.new()
	s.size = Vector3(SIZE.x, LIP_TOP + 0.006, GRIP_DEEP)
	return s


func centre_height() -> float:
	return 0.012


## On a desk, low in the middle of the view and tipped up toward the eye, its reader's edge
## nearest (VIEW_AT). In a hand, held by its outer side as a tray is, out along the controller and
## lying across in front of you, its far edge tipped up toward you: wholly to the inside of the
## hand's own ray (HELD_CLEAR past its edge), so that hand still points past it at the room, and
## its trigger never presses the bed it carries. The other hand points at the bed.
func held_pose() -> Transform3D:
	if carried_by is MouseInteractor:
		var carry := Transform3D(Basis(Vector3.RIGHT, MouseInteractor.CARRY_TIP), MouseInteractor.CARRY_AT)
		return carry.affine_inverse() * facing_eye(VIEW_AT, VIEW_TIP)
	var side := 1
	if carried_by != null and carried_by.has_method(&"hand_side"):
		side = carried_by.hand_side()
	return Transform3D(Basis(Vector3.RIGHT, HELD_TIP) * Basis(Vector3.UP, PI),
			Vector3(-side * (SIZE.x * 0.5 + HELD_CLEAR), -0.03, -SIZE.y * 0.5 - 0.02))


## A pose at `at` in the eye's frame, its bed tipped `tip` of the way from lying flat to square to
## the eye, its reader's edge (the item's -Z) toward the eye's feet.
static func facing_eye(at: Vector3, tip: float) -> Transform3D:
	var toward := -at.normalized()
	var normal := Vector3.UP.slerp(toward, clampf(tip, 0.0, 1.0)).normalized()
	# The item's -Z, its reader's edge, along the bed toward the eye.
	var near := (toward - normal * toward.dot(normal)).normalized()
	if near.length() < 0.01:
		near = Vector3.DOWN
	return Transform3D(Basis(normal.cross(-near), normal, -near), at)


func flies() -> Dictionary:
	return {"bounce": 0.12, "roll": 2.0, "drag": 0.06}


func on_bounce(speed: float) -> void:
	Foley.play(self, Foley.gear_bump(), clampf(linear_to_db(speed / 4.0), -24.0, -4.0), 0.9)


func _foley_contact() -> AudioStream:
	return Foley.gear_bump()


# --- the song, drawn ---------------------------------------------------------------------------

func _ready() -> void:
	super()
	if face == null:
		face = Face.new()
		face.name = "Face"
		face.mini = self
		_content.add_child(face)
		_pins_node = Node3D.new()
		_pins_node.name = "Pins"
		_content.add_child(_pins_node)
		_build_fixed()
		_build_pins()
	for s: Signal in [DAW.timeline_changed, DAW.bank_changed, DAW.project_replaced]:
		if not s.is_connected(_on_changed):
			s.connect(_on_changed)
	if not DAW.track_added.is_connected(_on_track_added):
		DAW.track_added.connect(_on_track_added)
	if not DAW.track_changed.is_connected(_on_track_changed):
		DAW.track_changed.connect(_on_track_changed)
	if not DAW.tracks_renumbered.is_connected(_on_renumbered):
		DAW.tracks_renumbered.connect(_on_renumbered)
	_dirty = true


func _exit_tree() -> void:
	super()
	for s: Signal in [DAW.timeline_changed, DAW.bank_changed, DAW.project_replaced]:
		if s.is_connected(_on_changed):
			s.disconnect(_on_changed)
	if DAW.track_added.is_connected(_on_track_added):
		DAW.track_added.disconnect(_on_track_added)
	if DAW.track_changed.is_connected(_on_track_changed):
		DAW.track_changed.disconnect(_on_track_changed)
	if DAW.tracks_renumbered.is_connected(_on_renumbered):
		DAW.tracks_renumbered.disconnect(_on_renumbered)


func _on_changed() -> void:
	_dirty = true


func _on_track_added(_index: int) -> void:
	_dirty = true


func _on_track_changed(_index: int, field: StringName) -> void:
	if field in [&"name", &"colour"]:
		_dirty = true


func _on_renumbered(_map: Dictionary) -> void:
	_dirty = true


## The stations standing here (see `stations`), and their pins again.
func set_stations(rows: Array) -> void:
	stations = rows
	if _pins_node != null:
		_build_pins()


func _process(delta: float) -> void:
	if _content == null or not is_inside_tree():
		return
	_key_clock += delta
	if _key_clock >= 0.5:
		# Markers and regions are cheap to count; what a signal did not say still redraws.
		_key_clock = 0.0
		var key := _song_shape()
		if key != _shape_key:
			_dirty = true
	if _dirty:
		rebuild()
	_draw_loop()
	_draw_playhead()


func _song_shape() -> Array:
	var s := DAW.state
	return [s.timeline_length(), s.tracks.size(), s.markers.size(), s.regions.size(), s.bank_offset]


## Everything on the bed drawn again from the song as it is now.
func rebuild() -> void:
	_dirty = false
	_shape_key = _song_shape()
	if _drawn != null:
		_content.remove_child(_drawn)
		_drawn.queue_free()
	_drawn = Node3D.new()
	_drawn.name = "Drawn"
	_content.add_child(_drawn)
	strips.clear()
	bands.clear()
	flags.clear()
	var s := DAW.state
	var lanes := lanes_rect()
	var rows := rows()
	var depth := row_depth()
	var blocks := 0
	for n in rows.size():
		var index: int = rows[n]
		var t := s.track(index, false)
		if t == null:
			continue
		var z := z_of_row(n)
		var colour := TrackColours.shown(t.colour, index)
		_box(Vector3(lanes.get_center().x, BED_TOP + 0.0004, z), Vector3(lanes.size.x, 0.0008, depth - STRIP_GAP), STRIP)
		_box(Vector3(BED.position.x + 0.004, BED_TOP + 0.0006, z), Vector3(0.004, 0.0012, depth - STRIP_GAP), colour)
		var strip := {"track": index, "name": null, "blocks": []}
		if depth >= NAMED_LEAST:
			var name_label := _flat_text(t.name if t.name != "" else "Track %d" % s.absolute_track_number(index),
					Vector3(BED.position.x + 0.009, BED_TOP + 0.0012, z), mini(80, int(depth * 0.62 / PIXEL)),
					HORIZONTAL_ALIGNMENT_LEFT)
			Lettering.fit(name_label, NAMES - 0.012, name_label.font_size, 20)
			strip["name"] = name_label
		for i in t.items.size():
			if blocks >= BLOCKS_MOST:
				break
			var it: MixState.ItemState = t.items[i]
			var left := x_of(it.start)
			var right := maxf(x_of(it.end()), left + BLOCK_LEAST)
			# A hair apart where one item runs into the next, so two takes end to end are two.
			if right - left > BLOCK_LEAST + BLOCK_SEAM:
				right -= BLOCK_SEAM
			var tall := SELECTED_TALL if it.selected else BLOCK_TALL
			var tint := colour.darkened(0.6) if it.muted else colour
			var block := _box(Vector3((left + right) * 0.5, BED_TOP + 0.0008 + tall * 0.5, z),
					Vector3(right - left, tall, (depth - STRIP_GAP) * 0.8), tint)
			if it.selected:
				# Selected: taller, and a light rail along its top, a shape and not only a colour.
				_box(Vector3(0, tall * 0.5 + 0.0003, 0), Vector3(right - left, 0.0006, (depth - STRIP_GAP) * 0.25), INK, block)
			(strip["blocks"] as Array).append([i, block])
			blocks += 1
		strips.append(strip)
	_draw_ruler()
	_drawn_loop = Vector3(-1, -1, -1)
	_match_layers(_drawn)


## The regions as bands along the near half of the ruler, alternating two tones, each lettered; the
## markers as flags along its far half, and a `NOTE ` marker as a card pinned there.
func _draw_ruler() -> void:
	var s := DAW.state
	var lanes := lanes_rect()
	var band_z := lanes.position.y - RULER * 0.28
	var band_depth := RULER * 0.4
	for i in s.regions.size():
		var r: Array = s.regions[i]
		var left := x_of(float(r[0]))
		var right := maxf(x_of(float(r[1])), left + BLOCK_LEAST)
		var band := _box(Vector3((left + right) * 0.5, BED_TOP + 0.0005, band_z), Vector3(right - left - 0.0006, 0.001, band_depth),
				REGION[i % REGION.size()])
		var label := _flat_text(String(r[2]).to_upper(), Vector3(left + 0.0015, BED_TOP + 0.0011, band_z), 56, HORIZONTAL_ALIGNMENT_LEFT)
		Lettering.fit(label, right - left - 0.003, 56, 20)
		label.visible = right - left > 0.008
		bands.append([float(r[0]), band, label])
	var times: Array = s.markers.keys()
	times.sort()
	var flag_z := BED.position.y + RULER * 0.3
	for n in times.size():
		var at: float = times[n]
		var text := String(s.markers[at])
		var note := text.begins_with(NOTE_PREFIX)
		if not note:
			# Its name, not the harmony written after it (`Intro [A minor: Am F C G]`).
			text = text.get_slice(" [", 0)
		var x := x_of(at)
		var next := x_of(float(times[n + 1])) if n + 1 < times.size() else lanes.end.x
		var flag := Node3D.new()
		flag.position = Vector3(x, BED_TOP, flag_z)
		_drawn.add_child(flag)
		var label: Label3D = null
		if note:
			# A sticky note: a card lying on the ruler at its time, a pin through its corner.
			_box(Vector3(0.006, 0.0008, 0), Vector3(0.012, 0.0006, 0.01), NOTE_CARD, flag)
			_box(Vector3(0.001, 0.003, -0.004), Vector3(0.0016, 0.006, 0.0016), Color(0.85, 0.2, 0.2), flag)
			label = _flat_text(text.trim_prefix(NOTE_PREFIX), Vector3(0.0005, 0.0013, 0.0), 26, HORIZONTAL_ALIGNMENT_LEFT, flag)
			label.modulate = Color(0.12, 0.1, 0.05)
			label.outline_size = 0
			Lettering.fit(label, 0.011, 26, 14)
		else:
			_box(Vector3(0, FLAG_TALL * 0.5, 0), Vector3(0.0008, FLAG_TALL, 0.0008), DIM, flag)
			_box(Vector3(0.003, FLAG_TALL - 0.0025, 0), Vector3(0.006, 0.005, 0.0005), FLAG, flag)
			# Its name lying on the ruler past the flag, as the regions' are: a tray tipped up to
			# be read shows lettering standing on it nearly edge-on.
			label = _flat_text(text, Vector3(0.0072, 0.0011, 0), 52, HORIZONTAL_ALIGNMENT_LEFT, flag)
			Lettering.fit(label, maxf(next - x - 0.009, 0.004), 52, 16)
			label.visible = next - x > 0.014
		flags.append([at, flag, label, note])


## The tray's own lettering, the loop's bracket and the playhead: built once, moved as the song
## goes.
func _build_fixed() -> void:
	var lanes := lanes_rect()
	_playhead = _box(Vector3(lanes.position.x, BED_TOP + 0.006, (BED.position.y + lanes.end.y) * 0.5),
			Vector3(0.0012, 0.012, lanes.end.y - BED.position.y), PLAYHEAD, _content, true)
	_playhead.name = "Playhead"
	_bracket = Node3D.new()
	_bracket.name = "Loop"
	_content.add_child(_bracket)
	for part in ["Top", "Left", "Right"]:
		var bar := MeshInstance3D.new()
		bar.name = part
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		bar.mesh = mesh
		_bracket.add_child(bar)
	_bracket.visible = false
	var caption := _flat_text("THE SESSION  ·  point and press: play from there", Vector3(-SIZE.x * 0.5 + 0.012,
			LIP_TOP + 0.0004, -SIZE.y * 0.5 + 0.009), 64, HORIZONTAL_ALIGNMENT_LEFT, _content)
	caption.modulate = DIM
	Lettering.fit(caption, 0.27, 64, 24)
	_clock = _flat_text("1.1.00", Vector3(SIZE.x * 0.5 - 0.012, LIP_TOP + 0.0004, -SIZE.y * 0.5 + 0.009), 80,
			HORIZONTAL_ALIGNMENT_RIGHT, _content)


func _draw_loop() -> void:
	var s := DAW.state
	var key := Vector3(s.loop_start, s.loop_end, 1.0 if s.looping else 0.0)
	if key == _drawn_loop:
		return
	_drawn_loop = key
	_bracket.visible = s.has_loop_range()
	if not _bracket.visible:
		return
	var left := x_of(s.loop_start)
	var right := maxf(x_of(s.loop_end), left + BLOCK_LEAST)
	var z := BED.position.y + RULER * 0.55
	var tint := LOOP if s.looping else LOOP_OFF
	var top := _bracket.get_node("Top") as MeshInstance3D
	top.scale = Vector3(right - left, 0.0012, 0.0012)
	top.position = Vector3((left + right) * 0.5, BED_TOP + BRACKET_HIGH, z)
	for side: String in ["Left", "Right"]:
		var leg := _bracket.get_node(side) as MeshInstance3D
		leg.scale = Vector3(0.0012, BRACKET_HIGH, 0.0012)
		leg.position = Vector3(left if side == "Left" else right, BED_TOP + BRACKET_HIGH * 0.5, z)
	for bar: MeshInstance3D in _bracket.get_children():
		bar.material_override = _mat(tint, s.looping)
	_match_layers(_bracket)


func _draw_playhead() -> void:
	var at := playhead_seconds()
	_playhead.position.x = x_of(at)
	var text := DAW.state.bar_beat(at)
	if text != _clock_text:
		_clock_text = text
		_clock.text = text


## Where the playhead is drawn: the song's position, or at motion 0 the beat it is in, so it steps
## a beat at a time rather than sliding.
func playhead_seconds() -> float:
	var s := DAW.state
	var at := s.position_seconds
	if Ergonomics.current != null and Ergonomics.current.motion_scale <= 0.0:
		at = s.seconds_at_beat(floorf(s.beat_at(at) + 0.0001))
	return clampf(at, 0.0, span())


# --- the pins ----------------------------------------------------------------------------------

## A pin a station, each on the side of the tray its station is on from the mix position (the
## tray's far edge toward the desk), spread so no two are nearer than PIN_GAP round the edge.
func _build_pins() -> void:
	for p in _pins_node.get_children():
		_pins_node.remove_child(p)
		p.queue_free()
	pins.clear()
	var around := pin_spots(stations.map(func(r: Array) -> Vector2: return r[3]))
	for n in stations.size():
		var row: Array = stations[n]
		var pin := Pin.new()
		pin.mini = self
		pin.station = row[0]
		pin.station_title = row[1]
		pin.area = row[2]
		pin.name = "Pin_%s" % row[0]
		var spot: Array = around[n]
		pin.position = Vector3((spot[0] as Vector2).x, LIP_TOP, (spot[0] as Vector2).y)
		pin.along = spot[1]
		_pins_node.add_child(pin)
		pins[row[0]] = pin
	_match_layers(_pins_node)


## Where each pin stands, for `bearings` (plan directions from the mix position, a station each):
## [[point on the lip (x, z), the edge's direction there]], in the content frame, spread round the
## edge to PIN_GAP apart at least. The tray's far edge is the room's -Z, toward the desk.
static func pin_spots(bearings: Array) -> Array:
	var a := SIZE.x * 0.5 - PIN_IN
	var b := SIZE.y * 0.5 - PIN_IN
	var perimeter := 4.0 * (a + b)
	var along: Array[float] = []
	for d: Vector2 in bearings:
		along.append(_round_of(d if d.length() > 0.001 else Vector2(0, 1), a, b))
	# In order round the edge, each pushed on from the one before until PIN_GAP apart; then the
	# whole run turned back by half of how far it was pushed, so it sits round where it was.
	var order: Array = range(along.size())
	order.sort_custom(func(i: int, j: int) -> bool: return along[i] < along[j])
	var gap := minf(PIN_GAP, perimeter / maxf(1.0, along.size()))
	var placed := along.duplicate()
	for k in range(1, order.size()):
		placed[order[k]] = maxf(placed[order[k]], placed[order[k - 1]] + gap)
	var pushed := 0.0
	for k in order.size():
		pushed += placed[order[k]] - along[order[k]]
	var back := pushed / maxf(1.0, order.size())
	var out: Array = []
	for i in along.size():
		var s := fposmod(placed[i] - back, perimeter)
		out.append(_on_round(s, a, b))
	return out


## How far round the edge (a rectangle of half sizes `a` by `b`) the ray from its middle along `d`
## meets it, from the far left corner clockwise as the reader sees it: along the far edge to the
## right, down the right, back along the near edge, up the left.
static func _round_of(d: Vector2, a: float, b: float) -> float:
	var t := minf(a / absf(d.x) if absf(d.x) > 0.0001 else INF, b / absf(d.y) if absf(d.y) > 0.0001 else INF)
	var p := d * t
	if absf(p.y + b) < 0.0001:
		return p.x + a
	if absf(p.x - a) < 0.0001:
		return 2.0 * a + (p.y + b)
	if absf(p.y - b) < 0.0001:
		return 2.0 * a + 2.0 * b + (a - p.x)
	return 4.0 * a + 2.0 * b + (b - p.y)


## The point `s` round the edge (`_round_of`'s measure), and the edge's direction there.
static func _on_round(s: float, a: float, b: float) -> Array:
	if s < 2.0 * a:
		return [Vector2(-a + s, -b), Vector2.RIGHT]
	s -= 2.0 * a
	if s < 2.0 * b:
		return [Vector2(a, -b + s), Vector2(0, 1)]
	s -= 2.0 * b
	if s < 2.0 * a:
		return [Vector2(a - s, b), Vector2.LEFT]
	s -= 2.0 * a
	return [Vector2(-a, b - s), Vector2(0, -1)]


# --- where a point is --------------------------------------------------------------------------

## The strips' rectangle on the bed, in the content frame's x and z.
func lanes_rect() -> Rect2:
	var left := BED.position.x + NAMES
	var far := BED.position.y + RULER
	return Rect2(left, far, BED.end.x - MARGIN - left, BED.end.y - MARGIN - far)


## How long the whole tray is in song time: the timeline's whole length.
func span() -> float:
	return DAW.state.timeline_length()


func x_of(seconds: float) -> float:
	var lanes := lanes_rect()
	return lanes.position.x + clampf(seconds / span(), 0.0, 1.0) * lanes.size.x


func seconds_at_x(x: float) -> float:
	var lanes := lanes_rect()
	return clampf((x - lanes.position.x) / lanes.size.x, 0.0, 1.0) * span()


## The tracks drawn, one a strip, far to near.
func rows() -> Array:
	return DAW.state.track_indices()


## How deep a strip is: the lanes shared between the tracks, at most STRIP_MOST.
func row_depth() -> float:
	return minf(STRIP_MOST, lanes_rect().size.y / maxf(1.0, rows().size()))


## The middle of strip `n` (0 the far one) along z.
func z_of_row(n: int) -> float:
	return lanes_rect().position.y + (n + 0.5) * row_depth()


## A point on the bed over `track` at `seconds`, in the content frame (its ruler for track 0).
func point_of(track: int, seconds: float) -> Vector3:
	var n := rows().find(track)
	var z := z_of_row(n) if n >= 0 else BED.position.y + RULER * 0.5
	return Vector3(x_of(seconds), BED_TOP, z)


## The same, in the world: for a hand to press there.
func global_point_of(track: int, seconds: float) -> Vector3:
	return _content.global_transform * point_of(track, seconds)


## A point in the world, in the content frame.
func content_local(global_point: Vector3) -> Vector3:
	return _content.global_transform.affine_inverse() * global_point


## What is under `local` (the content frame): {track, seconds, item}. `track` 0 is the ruler, or
## off the strips; `seconds` is negative over the names' column, which names a track but no time;
## `item` is the index of the item there on that track, -1 for none, the latest to start winning
## where two overlap.
func spot_at(local: Vector3) -> Dictionary:
	var lanes := lanes_rect()
	var out := {"track": 0, "seconds": seconds_at_x(local.x), "item": -1}
	if local.x < lanes.position.x:
		out["seconds"] = -1.0
	if local.z < lanes.position.y:
		return out
	var n := int(floor((local.z - lanes.position.y) / row_depth()))
	var tracks := rows()
	if n < 0 or n >= tracks.size():
		return out
	var index: int = tracks[n]
	out["track"] = index
	if float(out["seconds"]) < 0.0:
		return out
	var t := DAW.state.track(index, false)
	if t == null:
		return out
	# A block is drawn at least BLOCK_LEAST wide: so is what a press finds.
	var least := BLOCK_LEAST / lanes.size.x * span()
	var at: float = out["seconds"]
	for i in t.items.size():
		var it: MixState.ItemState = t.items[i]
		if at >= it.start - 0.0001 and at <= maxf(it.end(), it.start + least) + 0.0001:
			out["item"] = i
	return out


## A press at `local`: said, for the studio to seek and bring the gear. Nothing over the names'
## column of the ruler, where there is neither a track nor a time.
func press(local: Vector3) -> void:
	var spot := spot_at(local)
	if int(spot["track"]) == 0 and float(spot["seconds"]) < 0.0:
		return
	pressed.emit(int(spot["track"]), float(spot["seconds"]), int(spot["item"]))


## What the hover card says over `local`: [title, readout, hint].
func card(local: Vector3) -> Array:
	var spot := spot_at(local)
	var s := DAW.state
	var track: int = spot["track"]
	var at: float = spot["seconds"]
	var t := s.track(track, false) if track > 0 else null
	var who := (t.name if t.name != "" else "Track %d" % s.absolute_track_number(track)) if t != null else ""
	var when := ""
	if at >= 0.0:
		when = s.bar_beat(at)
		var r := s.region_at(at)
		if r >= 0:
			when += " · %s" % String(s.regions[r][2]).to_upper()
	var item: MixState.ItemState = s.item(track, int(spot["item"])) if int(spot["item"]) >= 0 else null
	if item != null:
		var called := item.name if item.name != "" else "an item"
		return ["MINIATURE  %s" % who.to_upper(), "%s on %s · %s" % [called, who, when],
				"press: play from here, select %s and bring the timeline to it" % called]
	if t != null and at < 0.0:
		return ["MINIATURE  %s" % who.to_upper(), "track %d" % s.absolute_track_number(track),
				"press: the console comes, banked to %s" % who]
	if t != null:
		return ["MINIATURE  %s" % who.to_upper(), when,
				"press: play from here, the console comes banked to %s" % who]
	if at >= 0.0:
		return ["SESSION IN MINIATURE", when, "press: play from here"]
	return ["SESSION IN MINIATURE", "%d tracks" % s.tracks.size(), "point at a track or a time"]


# --- drawing -----------------------------------------------------------------------------------

func _box(at: Vector3, size: Vector3, tint: Color, parent: Node3D = null, lit := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.material_override = _mat(tint, lit)
	(parent if parent != null else _drawn).add_child(m)
	return m


## A colour of this tray's own, unshaded: never Materials' shared ones, since a hand's rim (Item.set_rim) is
## put on every material under the body, and a shared one would ring the whole room's.
func _mat(tint: Color, lit := false) -> StandardMaterial3D:
	var key := "%s/%s" % [tint.to_html(), lit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	# Painted as a screen paints, lit by itself: a tray held up under the body's work light is
	# close enough to it to wash every colour on it out to white.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = tint * 0.85 if not lit else tint
	_mats[key] = m
	return m


## Lettering lying on the bed, read from its reader's edge.
func _flat_text(text: String, at: Vector3, size: int, align: HorizontalAlignment, parent: Node3D = null) -> Label3D:
	var l := _text(text, size, align, parent)
	l.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at)
	return l


func _text(text: String, size: int, align: HorizontalAlignment, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = maxi(size, 12)
	l.pixel_size = PIXEL
	l.modulate = INK
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	(parent if parent != null else _drawn).add_child(l)
	return l


## What is drawn after a hand took it is drawn as the tray is: off the mirror while it is in a hand
## here (Item._layers), since the mirror's ghost carries a tray of its own.
func _match_layers(under: Node) -> void:
	var tray := _content.get_node_or_null("Tray")
	var shown: VisualInstance3D = null
	if tray != null:
		for v in tray.find_children("*", "VisualInstance3D", true, false):
			shown = v
			break
	if shown == null:
		return
	for v in under.find_children("*", "VisualInstance3D", true, false):
		(v as VisualInstance3D).layers = shown.layers


## The bed as a control: the hover card names the track and the time under the pointer, and a
## press there is the tray's (`press`).
class Face extends ControlAffordance:
	var mini: MiniatureItem

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		# Lying on the bed, its +Z up (FACE_UP) and its far edge up its +Y: a fingertip lets go as
		# it lifts off. Its middle is the bed's, as high as an item's block is.
		transform = Transform3D(FACE_UP, Vector3(BED.get_center().x, BED_TOP + BLOCK_TALL * 0.5, BED.get_center().y))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Thin: what a glancing ray meets is where the eye was, within a strip, rather than a box's
		# side a centimetre short of it.
		box.size = Vector3(BED.size.x, BED.size.y, 0.001)
		shape.shape = box
		add_child(shape)

	## This player's own: a press here is never held against anyone's.
	func personal() -> bool:
		return true

	func _pointer() -> Vector3:
		var by: Node = held_by if held_by != null else (_hovered_by[0] if not _hovered_by.is_empty() else null)
		if by == null or not ("hover_point" in by):
			return Vector3(BED.get_center().x, BED_TOP, BED.get_center().y)
		return mini.content_local(by.hover_point)

	func _default_title() -> String:
		return mini.card(_pointer())[0]

	func _default_readout() -> String:
		return mini.card(_pointer())[1]

	func hint() -> String:
		return mini.card(_pointer())[2]

	func _on_grab_begin(at: Vector3) -> void:
		mini.press(mini.content_local(at))


## A station's pin on the lip, lettered: a press goes there.
class Pin extends ControlAffordance:
	var mini: MiniatureItem
	var station := &""
	var station_title := ""
	var area := &""
	## The edge's direction where it stands, in the content frame's plan: its name runs along it.
	var along := Vector2.RIGHT

	func _ready() -> void:
		collision_layer = 1 << (Interactor.CONTROL_LAYER - 1)
		collision_mask = 0
		# Its +Z up (FACE_UP), so a fingertip pressing its head lets go as it lifts off; what it
		# shows is laid out as standing on the lip (+Y up) and turned back by `flat`.
		basis = FACE_UP
		var flat := Transform3D(FACE_UP.inverse(), Vector3.ZERO)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.02, PIN_TALL + 0.006, 0.02)
		shape.shape = box
		shape.transform = flat.translated_local(Vector3(0, (PIN_TALL + 0.006) * 0.5, 0))
		add_child(shape)
		var stem := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = 0.0008
		tube.bottom_radius = 0.0008
		tube.height = PIN_TALL
		tube.radial_segments = 8
		stem.mesh = tube
		stem.transform = flat.translated_local(Vector3(0, PIN_TALL * 0.5, 0))
		stem.material_override = mini._mat(Color(0.75, 0.66, 0.42))
		add_child(stem)
		var head := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = PIN_HEAD
		ball.height = PIN_HEAD * 2.0
		ball.radial_segments = 12
		ball.rings = 6
		head.mesh = ball
		head.transform = flat.translated_local(Vector3(0, PIN_TALL, 0))
		head.material_override = mini._mat(PIN_HEADS.get(area, INK), true)
		add_child(head)
		# Its name on the lip, a little further in, running along the edge.
		var inward := Vector2(-along.y, along.x)
		# Read from the reader's edge: along the near edge it runs left to right too.
		var runs := along if along.x > -0.5 else -along
		var l := mini._text(station_title, 60, HORIZONTAL_ALIGNMENT_CENTER, self)
		l.transform = flat * Transform3D(Basis(Vector3.UP, -runs.angle()) * Basis(Vector3.RIGHT, -PI * 0.5),
				Vector3(inward.x * PIN_NAME_IN, 0.0004, inward.y * PIN_NAME_IN))
		Lettering.fit(l, PIN_GAP - 0.006, 60, 20)

	func personal() -> bool:
		return true

	func title() -> String:
		return station_title

	func readout() -> String:
		return "in the %s" % String(Stations.AREA_TITLES.get(area, "room")).to_lower()

	func hint() -> String:
		return "press: go there"

	func _on_grab_begin(_at: Vector3) -> void:
		mini.station_pressed.emit(station)
