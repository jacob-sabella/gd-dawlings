class_name TapeDeck
extends Surface

## The transport, as a two-reel machine.
##
## The reels are not decoration and not a skin on a play button. A DAW's transport state is three
## booleans and a float, and on screen that is read from a highlighted triangle and a number. As
## a machine it is read PERIPHERALLY -- you know the thing is rolling from the corner of your eye,
## across the room, while looking at something else, which is precisely the situation this project
## exists for. The reels turn at a rate derived from how fast the song is actually moving, and
## each reel turns at its OWN rate, so the takeup starts fast and slows all song while the supply
## does the opposite. That difference is the signature you read peripherally; two reels sharing
## one rate are two wheels on a common axle.
##
## What this does NOT do is pretend to be tape: there is no wind, no spooling time, no latency
## added anywhere. Reaper's position is the truth and the reels follow it.

const REEL_RADIUS := 0.085
const REEL_SPACING := 0.26
const MESH_PATH := "res://assets/hardware/reel.glb"

## The tape pack, which the flange deliberately does not include: it is a function of how far
## through the song you are, so it is computed rather than authored. Seen only through the
## flange's three windows, which is what the windows are for on a real machine.
const PACK_HUB := 0.0215
const PACK_FULL := 0.0735

## Metres of "tape" drawn past the head per second of song at 1x. Not a real figure -- 15ips is
## 0.38 -- and it does not want to be, because the reels here are a tenth the diameter of real
## ones. It is set so a half-wound reel turns at the 2.4 rad/s this deck turned at when the rate
## was flat, which keeps the look that was already tuned by eye and changes only how it varies.
const TAPE_SPEED := 0.13

## A locate arrives as a position jump, and a jump divided by one frame is an arbitrarily large
## number. Real machines have a spool limit for the same reason, so this is a cap rather than a
## special case: a seek spins the reels hard and briefly, which is what a locate looks like.
const MAX_SPOOL_RATE := 48.0

## How fast the observed song speed catches up, per second.
##
## It has to be smoothed, and the reason is specific rather than cosmetic: position does not
## arrive every frame. A real Reaper link delivers it over the wire at its own rate, so at 60fps
## most frames see the same number as the frame before and read as a dead stop. Unsmoothed, the
## reels stutter to a halt and back several times a second -- which looks like a fault in the
## machine, and a peripheral display that looks faulty is worse than one that is absent.
const SPEED_FOLLOW := 6.0

## Below this, in song-seconds per second, the deck is stopped as far as the motor is concerned.
const MOTOR_FLOOR_SPEED := 0.02

## THE TAPE PATH, which this deck did not have.
##
## Two reels and nothing between them is not a tape machine; it is two wheels. Everything that
## makes a deck legible as a deck lives in the gap -- the ribbon itself, the guides that turn
## it, the heads it is dragged across, the capstan and pinch roller that are the only things
## actually setting its speed. A photograph of the old deck read as a poster of one.
##
## It also makes the reels mean something. The packs already shrink and grow correctly, but a
## pack with no tape coming off it is a disc that changes size. With a ribbon leaving it on a
## tangent that MOVES as the pack empties, the same geometry reads as what it is.
const PATH_Y := -0.050
const GUIDE_X := 0.040
const TAPE_WIDTH := 0.0065
## In front of the chassis and behind the transport buttons. The tape crosses the reel flanges
## rather than threading behind them, which is a compromise -- on a real machine the path is in
## the flange plane -- but a ribbon hidden behind two reels is a ribbon nobody can see.
const TAPE_Z := 0.016
## Where a run stops: at the flange rim, not at the pack it is tangent to. The pack sits BEHIND
## the flange and is only visible through the windows, so a run drawn all the way to it ends in
## the middle of a solid disc -- which is what the first attempt did, and it looked like a stick
## resting on the reel. Stopping at the rim reads as tape going in behind it. The ANGLE still
## comes from the pack, which is the part that has to stay true: that is what changes as the
## reel empties.

var _left_reel: Node3D
var _right_reel: Node3D
var _left_pack: MeshInstance3D
var _right_pack: MeshInstance3D
var _counter: Label3D
var _tempo_label: Label3D
var _tempo_knob: Knob
var _taps: Array[int] = []
var _play_lamp: PanelButton
var _rec_lamp: PanelButton
var _loop_lamp: PanelButton
var _click_lamp: PanelButton
var _count_lamp: PanelButton
var _punch_lamp: PanelButton
## What the COUNT key steps through, in bars.
const COUNT_IN_STEPS := [0, 1, 2, 4]
var _mark_key: PanelButton
var _section_label: Label3D
var _loop_label: Label3D
var _history_keys: Array[PanelButton] = []
var _tape_runs: Array[MeshInstance3D] = []
var _song_speed := 0.0
var _last_position := -1.0
var _motor: AudioStreamPlayer3D


func _ready() -> void:
	surface_kind = &"transport"
	if surface_id == &"":
		surface_id = &"tape_deck"
	super()


func _rebuild() -> void:
	_clear_built()

	var chassis := MeshInstance3D.new()
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(0.46, 0.30, 0.05)
	chassis.mesh = chassis_mesh
	chassis.position = Vector3(0, 0, -0.03)
	chassis.material_override = Materials.chassis()
	_adopt(chassis)

	_left_reel = _make_reel(-REEL_SPACING * 0.5)
	_right_reel = _make_reel(REEL_SPACING * 0.5)
	_left_pack = _left_reel.get_node_or_null(^"Pack")
	_right_pack = _right_reel.get_node_or_null(^"Pack")

	_counter = Label3D.new()
	_counter.font_size = 72
	_counter.pixel_size = 0.00024
	_counter.position = Vector3(0, 0.105, 0.002)
	_counter.modulate = Color(0.45, 0.95, 0.6)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_counter)
	_adopt(_counter)

	# Beside the counter rather than under the transport keys, where it was: the keys stand
	# proud of the panel and, from a seat above the deck, hid the tempo completely.
	_tempo_label = Label3D.new()
	_tempo_label.font_size = 40
	_tempo_label.pixel_size = 0.00024
	_tempo_label.position = Vector3(-0.165, 0.108, 0.002)
	_tempo_label.modulate = Color(0.7, 0.72, 0.75)
	_tempo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_tempo_label)
	_adopt(_tempo_label)

	# Tempo, beside its own readout: turned for a nudge, tapped for a feel. The knob is the
	# deck's whole tempo range, so a scroll notch is about eight BPM and a fine notch under one.
	_tempo_knob = Knob.new()
	_tempo_knob.name = "TempoKnob"
	_tempo_knob.position = Vector3(-0.105, 0.108, 0.006)
	_tempo_knob.turned.connect(func(v: float): DAW.set_tempo(knob_to_bpm(v)))
	_tempo_knob.describe_title = func() -> String: return "TRANSPORT  TEMPO"
	_tempo_knob.describe_value = func(v: float) -> String: return "%.1f BPM" % knob_to_bpm(v)
	_adopt(_tempo_knob)

	var tap := PanelButton.new()
	tap.name = "TapKey"
	tap.led_colour = Color(0.95, 0.80, 0.42)
	tap.lamp_scale = Vector2(0.8, 0.5)
	tap.position = Vector3(-0.115, -0.122, 0.028)
	tap.scale = Vector3(1.4, 1.4, 1.4)
	tap.pressed.connect(_tap)
	tap.describe_title = func() -> String: return "TRANSPORT  TAP TEMPO"
	tap.describe_value = func(_v: float) -> String:
		return "tap on the beat" if _taps.size() < 2 else "%.1f BPM" % tapped_bpm(_taps)
	_adopt(tap)
	var tap_caption := Label3D.new()
	tap_caption.text = "TAP"
	tap_caption.font_size = 30
	tap_caption.pixel_size = 0.00024
	tap_caption.position = Vector3(-0.115, -0.105, 0.002)
	tap_caption.modulate = Color(0.6, 0.62, 0.66)
	tap_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(tap_caption)
	_adopt(tap_caption)

	# Beside TAP, as COUNT is beside CLICK: punching in and out to the loop range.
	var punch := PanelButton.new()
	punch.name = "PunchKey"
	punch.led_colour = Color(0.95, 0.38, 0.34)
	punch.lamp_scale = Vector2(0.45, 0.8)
	punch.position = Vector3(-0.150, -0.122, 0.028)
	punch.scale = Vector3(1.4, 1.4, 1.4)
	punch.pressed.connect(func(): DAW.set_punch(not DAW.state.punch))
	punch.describe_title = func() -> String: return "TRANSPORT  PUNCH"
	punch.describe_value = func(_v: float) -> String: return punch_text(DAW.state)
	_adopt(punch)
	_punch_lamp = punch
	var punch_caption := Label3D.new()
	punch_caption.text = "PUNCH"
	punch_caption.font_size = 30
	punch_caption.pixel_size = 0.00024
	punch_caption.position = Vector3(-0.150, -0.105, 0.002)
	punch_caption.modulate = Color(0.6, 0.62, 0.66)
	punch_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(punch_caption)
	_adopt(punch_caption)

	_build_locator()

	# The click, opposite TAP: the two keys about the beat, either side of the transport.
	var click := PanelButton.new()
	click.name = "ClickKey"
	click.led_colour = Color(0.95, 0.80, 0.42)
	click.lamp_scale = Vector2(0.45, 0.8)
	click.position = Vector3(0.115, -0.122, 0.028)
	click.scale = Vector3(1.4, 1.4, 1.4)
	click.pressed.connect(func(): DAW.set_metronome(not DAW.state.metronome))
	click.describe_title = func() -> String: return "TRANSPORT  CLICK"
	click.describe_value = func(_v: float) -> String: return "on" if DAW.state.metronome else "off"
	_adopt(click)
	_click_lamp = click
	var click_caption := Label3D.new()
	click_caption.text = "CLICK"
	click_caption.font_size = 30
	click_caption.pixel_size = 0.00024
	click_caption.position = Vector3(0.115, -0.105, 0.002)
	click_caption.modulate = Color(0.6, 0.62, 0.66)
	click_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(click_caption)
	_adopt(click_caption)

	# Beside it, the bars of click before a recording: each press the next of COUNT_IN_STEPS.
	var count := PanelButton.new()
	count.name = "CountInKey"
	count.led_colour = Color(0.95, 0.80, 0.42)
	count.lamp_scale = Vector2(0.45, 0.8)
	count.position = Vector3(0.150, -0.122, 0.028)
	count.scale = Vector3(1.4, 1.4, 1.4)
	count.pressed.connect(_step_count_in)
	count.describe_title = func() -> String: return "TRANSPORT  COUNT-IN"
	count.describe_value = func(_v: float) -> String: return count_in_text(DAW.state)
	_adopt(count)
	_count_lamp = count
	var count_caption := Label3D.new()
	count_caption.text = "COUNT"
	count_caption.font_size = 30
	count_caption.pixel_size = 0.00024
	count_caption.position = Vector3(0.150, -0.105, 0.002)
	count_caption.modulate = Color(0.6, 0.62, 0.66)
	count_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(count_caption)
	_adopt(count_caption)

	_loop_label = Label3D.new()
	_loop_label.font_size = 40
	_loop_label.pixel_size = 0.00024
	_loop_label.position = Vector3(0.165, 0.108, 0.002)
	_loop_label.modulate = Color(0.45, 0.68, 0.98)
	_loop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_loop_label)
	_adopt(_loop_label)

	# Back to the start: of the loop when there is one, of the song when not. The key every
	# transport has at its left end, and the one pressed most after play.
	var home := PanelButton.new()
	home.led_colour = Color(0.75, 0.78, 0.82)
	home.lamp_scale = Vector2(0.9, 0.42)
	home.position = Vector3(-0.070, -0.096, 0.028)
	home.scale = Vector3(1.6, 1.6, 1.6)
	home.pressed.connect(func(): DAW.seek(DAW.state.loop_start
			if DAW.state.looping and DAW.state.has_loop_range() else 0.0))
	home.describe_title = func() -> String: return "TRANSPORT  RETURN TO START"
	home.describe_value = func(_v: float) -> String:
		return "to %s" % DAW.state.bar_beat(DAW.state.loop_start
				if DAW.state.looping and DAW.state.has_loop_range() else 0.0)
	_adopt(home)

	var loop := PanelButton.new()
	loop.led_colour = Color(0.36, 0.62, 0.98)
	loop.lamp_scale = Vector2(1.0, 0.6)
	loop.position = Vector3(0.070, -0.096, 0.028)
	loop.scale = Vector3(1.6, 1.6, 1.6)
	loop.pressed.connect(func():
		# Nothing to loop yet: the four bars from the playhead, the commonest thing to want.
		if not DAW.state.has_loop_range():
			var start := DAW.state.bar_to_seconds(floorf(
					DAW.state.position_seconds / DAW.state.bar_to_seconds(2.0)) + 1.0)
			DAW.set_loop_range(start, start + DAW.state.bar_to_seconds(5.0))
		DAW.set_looping(not DAW.state.looping))
	loop.describe_title = func() -> String: return "TRANSPORT  LOOP"
	loop.describe_value = func(_v: float) -> String: return _loop_text()
	_adopt(loop)
	_loop_lamp = loop

	# Legends over the keys, not under: the keys stand proud of the panel and, from a seat
	# above the deck, hide the strip of panel below them. Five unmarked lamps in a row is a
	# transport you learn by pressing.
	for spec in [[-0.070, "RTZ"], [-0.035, "PLAY"], [0.0, "STOP"], [0.035, "REC"], [0.070, "LOOP"]]:
		var legend := Label3D.new()
		legend.text = spec[1]
		legend.font_size = 26
		legend.pixel_size = 0.00024
		legend.position = Vector3(spec[0], -0.080, 0.002)
		legend.modulate = Color(0.6, 0.62, 0.66)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Lettering.range_to_legibility(legend)
		_adopt(legend)

	# History, in the bottom corners, away from the transport so a reach for stop never lands on
	# undo. Lit while there is something to undo or redo.
	_history_keys.clear()
	for spec in [[-1.0, "UNDO"], [1.0, "REDO"]]:
		var key := PanelButton.new()
		key.led_colour = Color(0.92, 0.72, 0.38)
		key.lamp_scale = Vector2(0.8, 0.5)
		key.position = Vector3(spec[0] * 0.185, -0.122, 0.028)
		key.scale = Vector3(1.4, 1.4, 1.4)
		var is_undo: bool = spec[0] < 0.0
		key.pressed.connect(func(): DAW.undo() if is_undo else DAW.redo())
		key.describe_title = func() -> String: return "EDIT  " + ("UNDO" if is_undo else "REDO")
		key.describe_value = func(_v: float) -> String:
			var depth := DAW.state.undo_depth if is_undo else DAW.state.redo_depth
			return "%d step(s)" % depth if depth >= 0 else "in Reaper's history"
		_adopt(key)
		_history_keys.append(key)
		var caption := Label3D.new()
		caption.text = spec[1]
		caption.font_size = 30
		caption.pixel_size = 0.00024
		caption.position = Vector3(spec[0] * 0.185, -0.105, 0.002)
		caption.modulate = Color(0.6, 0.62, 0.66)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Lettering.range_to_legibility(caption)
		_adopt(caption)

	var play := PanelButton.new()
	play.led_colour = Ergonomics.current.signal_colour(&"ok")
	play.lamp_scale = Vector2(1.0, 1.0)
	play.position = Vector3(-0.035, -0.096, 0.028)
	play.scale = Vector3(1.6, 1.6, 1.6)
	play.pressed.connect(func(): DAW.transport_play())
	play.describe_title = func() -> String: return "TRANSPORT  PLAY"
	_adopt(play)
	_play_lamp = play

	var stop := PanelButton.new()
	stop.led_colour = Ergonomics.current.signal_colour(&"mute")
	stop.lamp_scale = Vector2(0.45, 1.0)
	stop.position = Vector3(0.0, -0.096, 0.028)
	stop.scale = Vector3(1.6, 1.6, 1.6)
	stop.pressed.connect(func(): DAW.transport_stop())
	stop.describe_title = func() -> String: return "TRANSPORT  STOP"
	stop.describe_value = func(_v: float) -> String: return ""
	_adopt(stop)

	var rec := PanelButton.new()
	rec.led_colour = Ergonomics.current.signal_colour(&"record")
	rec.lamp_scale = Vector2(1.0, 0.42)
	rec.position = Vector3(0.035, -0.096, 0.028)
	rec.scale = Vector3(1.6, 1.6, 1.6)
	rec.pressed.connect(func(): DAW.transport_record())
	rec.describe_title = func() -> String: return "TRANSPORT  RECORD"
	_adopt(rec)
	_rec_lamp = rec

	_build_tape_path()

	# Once: this runs on every rebuild, and a second connection is an error from the engine
	# and a second refresh per transport change.
	if not DAW.transport_changed.is_connected(_refresh):
		DAW.transport_changed.connect(_refresh)
	_refresh()


## Where a tape leaves a pack, which is not a point on the pack -- it is the point where a line
## to the next guide stops cutting through it.
##
## `side` picks which of the two tangents: the tape has to come off the face of the pack that
## looks at the gap, and which one that is depends on which reel. Static because the whole
## reason the reels are worth drawing is that this moves, and a thing that moves is worth being
## able to check without a scene.
static func tangent_point(centre: Vector2, radius: float, toward: Vector2, side: float) -> Vector2:
	var d := toward - centre
	var span := d.length()
	if span <= radius or radius <= 0.0:
		# The guide is inside the pack. Cannot happen with the radii this deck uses, and
		# returning the near point rather than a NaN keeps a geometry change from drawing
		# nothing at all while somebody works out why.
		return centre + (d.normalized() * radius if span > 0.0 else Vector2(radius, 0.0))
	var along := d / span
	var across := Vector2(-along.y, along.x)
	var reach := sqrt(span * span - radius * radius)
	return centre + radius * ((radius / span) * along + side * (reach / span) * across)


## Where that tangent line crosses the flange rim on its way in from the guide.
##
## Static alongside `tangent_point` and for the same reason: between them they are the whole of
## where a run is drawn, and neither needs a scene to be wrong in.
static func rim_crossing(centre: Vector2, guide: Vector2, toward: Vector2, rim: float) -> Vector2:
	var along := toward - guide
	if along.length() < 1e-6:
		return toward
	along = along.normalized()
	var offset := guide - centre
	var half := offset.dot(along)
	var under := half * half - offset.length_squared() + rim * rim
	if under <= 0.0:
		# The run never reaches the reel. Not reachable with this deck's geometry; drawn to the
		# tangent rather than not drawn, so a layout change shows up as a wrong line instead of
		# a missing one.
		return toward
	var reach := -half - sqrt(under)
	if reach <= 0.0:
		return toward
	return guide + along * reach


func _build_tape_path() -> void:
	var dark := Materials.cap_plastic(Color(0.07, 0.065, 0.06))

	# The head block: a plinth with three heads standing on it -- erase, record, play, in the
	# order the tape meets them. They are the reason the gap is the width it is.
	var block := MeshInstance3D.new()
	var block_mesh := BoxMesh.new()
	block_mesh.size = Vector3(0.050, 0.018, 0.014)
	block.mesh = block_mesh
	block.position = Vector3(-0.008, PATH_Y - 0.0045, TAPE_Z - 0.009)
	block.material_override = dark
	_adopt(block)

	for hx in [-0.026, -0.008, 0.010]:
		var head := MeshInstance3D.new()
		var head_mesh := BoxMesh.new()
		head_mesh.size = Vector3(0.009, 0.013, 0.010)
		head.mesh = head_mesh
		head.position = Vector3(hx, PATH_Y + 0.0005, TAPE_Z - 0.0055)
		head.material_override = Materials.brushed_metal()
		_adopt(head)

	# Guides at each end of the straight run, and the capstan and pinch roller that pull the
	# tape past the heads. Drawn because they are the parts that explain the motion: the reels
	# wind and unwind, but nothing on a real machine takes its speed from them.
	for gx in [-GUIDE_X, GUIDE_X]:
		var guide := MeshInstance3D.new()
		var guide_mesh := CylinderMesh.new()
		guide_mesh.top_radius = 0.0042
		guide_mesh.bottom_radius = 0.0042
		guide_mesh.height = 0.013
		guide_mesh.radial_segments = 16
		guide.mesh = guide_mesh
		guide.rotation_degrees = Vector3(90, 0, 0)
		guide.position = Vector3(gx, PATH_Y, TAPE_Z - 0.002)
		guide.material_override = Materials.brushed_metal()
		_adopt(guide)

	for spec in [[-0.0052, 0.0048, Materials.brushed_metal()],
			[0.0056, 0.0052, dark]]:
		var roller := MeshInstance3D.new()
		var roller_mesh := CylinderMesh.new()
		roller_mesh.top_radius = spec[1]
		roller_mesh.bottom_radius = spec[1]
		roller_mesh.height = 0.012
		roller_mesh.radial_segments = 18
		roller.mesh = roller_mesh
		roller.rotation_degrees = Vector3(90, 0, 0)
		roller.position = Vector3(0.028, PATH_Y + spec[0], TAPE_Z - 0.002)
		roller.material_override = spec[2]
		_adopt(roller)

	# Three runs: off the supply, straight across the heads, onto the takeup. The middle one
	# never moves; the two outer ones are re-laid whenever a pack changes size, which is the
	# whole point of drawing them.
	# Oxide, which is nearly black. The first pass used the pack's own brown and the runs came
	# back reading as wooden battens: a pack is lit through a window at the bottom of a recess
	# and needs lifting, a run is out in the open and does not.
	var tape_mat := Materials.cap_plastic(Color(0.042, 0.033, 0.028))
	_tape_runs.clear()
	for i in 3:
		var run := MeshInstance3D.new()
		run.name = "TapeRun%d" % i
		var run_mesh := BoxMesh.new()
		run_mesh.size = Vector3(1.0, TAPE_WIDTH, 0.0012)
		run.mesh = run_mesh
		run.material_override = tape_mat
		_adopt(run)
		_tape_runs.append(run)
	_lay_run(_tape_runs[1], Vector2(-GUIDE_X, PATH_Y), Vector2(GUIDE_X, PATH_Y))
	# And the two outer runs NOW, not on the first _process. A run's mesh is a unit-length box
	# that the transform shrinks to size, so an unlaid run is a one-metre plank lying across
	# the deck -- and `rebuilt` fires between the rebuild and the first pack update, which is
	# exactly when the grab handle measures the surface to decide where its edge is. The handle
	# ended up floating a foot to the right of the machine, attached to nothing.
	_update_packs()


## Stretch one run between two points on the faceplate. The mesh is a unit-length box and the
## basis does the work, so re-laying a run is a transform write rather than a new mesh -- which
## matters because this happens every frame the transport is moving.
func _lay_run(run: MeshInstance3D, a: Vector2, b: Vector2) -> void:
	var d := b - a
	var span := d.length()
	if span < 0.0008:
		run.visible = false
		return
	run.visible = true
	var along := Vector3(d.x, d.y, 0.0) / span
	run.transform = Transform3D(
			Basis(along * span, Vector3(-along.y, along.x, 0.0), Vector3(0, 0, 1)),
			Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5,
					TAPE_Z + 0.0004 * _tape_runs.find(run)))


func _make_reel(x: float) -> Node3D:
	var hub := Node3D.new()
	hub.position = Vector3(x, 0.0, 0.01)
	_adopt(hub)

	# BEHIND the flange, so the only way to see it is through the windows -- which is both the
	# cheapest way to draw a tape pack and the honest one. A pack drawn in front would be a
	# disc sitting on a reel rather than tape wound inside one.
	var pack := MeshInstance3D.new()
	pack.name = "Pack"
	var pack_mesh := CylinderMesh.new()
	pack_mesh.height = 0.008
	pack_mesh.radial_segments = 48
	pack.mesh = pack_mesh
	pack.rotation_degrees = Vector3(90, 0, 0)
	# Pushed up until its face all but touches the back of the flange. A pack sitting deeper is
	# geometrically fine and visually absent: it falls into the shadow the flange casts and the
	# windows read as holes in a plate. The whole feature lives or dies on being lit.
	pack.position = Vector3(0, 0, -0.0065)
	# Lighter than real tape, for the same reason, and lighter than the first attempt at that:
	# 0.21 albedo was still reading as a hole rather than as tape. Oxide is nearly black, and
	# nearly black at the bottom of a recess the flange shadows is just black -- the window
	# then looks like a window with nothing behind it, which is worse than no window at all.
	pack.material_override = Materials.cap_plastic(Color(0.42, 0.27, 0.18))
	hub.add_child(pack)

	var flange := Part.build(
		MESH_PATH,
		Materials.reel_flange(),
		{"hub": Materials.cap_plastic(Color(0.6, 0.18, 0.16))},
	)
	if flange != null:
		# Modelled axis-up; the axis here is the panel normal, which is local Z.
		flange.rotation_degrees = Vector3(90, 0, 0)
		hub.add_child(flange)
	else:
		hub.add_child(_stand_in())
	return hub


## The pre-Blender reel: a plate, three crossing bars and a boss. Kept because a transport you
## cannot see turning is the one failure this surface exists to avoid.
func _stand_in() -> Node3D:
	var holder := Node3D.new()

	var flange := MeshInstance3D.new()
	var flange_mesh := CylinderMesh.new()
	flange_mesh.top_radius = REEL_RADIUS
	flange_mesh.bottom_radius = REEL_RADIUS
	flange_mesh.height = 0.004
	flange_mesh.radial_segments = 32
	flange.mesh = flange_mesh
	flange.rotation_degrees = Vector3(90, 0, 0)
	flange.material_override = Materials.brushed_metal()
	holder.add_child(flange)

	for i in 3:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.012, REEL_RADIUS * 1.7, 0.006)
		spoke.mesh = spoke_mesh
		spoke.rotation_degrees = Vector3(0, 0, i * 60.0)
		spoke.position = Vector3(0, 0, 0.004)
		spoke.material_override = Materials.cap_plastic(Color(0.1, 0.11, 0.12))
		holder.add_child(spoke)

	var centre := MeshInstance3D.new()
	var centre_mesh := CylinderMesh.new()
	centre_mesh.top_radius = 0.016
	centre_mesh.bottom_radius = 0.016
	centre_mesh.height = 0.012
	centre.mesh = centre_mesh
	centre.rotation_degrees = Vector3(90, 0, 0)
	centre.position = Vector3(0, 0, 0.006)
	centre.material_override = Materials.cap_plastic(Color(0.6, 0.18, 0.16))
	holder.add_child(centre)
	return holder


## How much tape is on a reel holding `fraction` of the song, as a radius.
##
## Not linear in the fraction, because tape has thickness: a wound pack grows by AREA, so the
## radius goes as a square root and a reel spends most of a song looking nearly full. Getting
## this wrong is visible -- a linear pack empties far too fast in the first minute and then
## crawls -- and it costs one sqrt to get right.
static func pack_radius(fraction: float) -> float:
	var f := clampf(fraction, 0.0, 1.0)
	return sqrt(PACK_HUB * PACK_HUB + f * (PACK_FULL * PACK_FULL - PACK_HUB * PACK_HUB))


## How fast a reel turns, in radians per second, given the fraction of the song wound ON IT.
##
## This is the whole reason a reel is worth drawing rather than animating. Tape crosses the head
## at one speed whatever the reels are doing, so a reel's angular rate is that speed divided by
## the radius it is paying out at. The consequence is the thing you recognise: a takeup reel is
## fastest when it is empty and slowest when it is full, the supply reel is the mirror of that,
## and the two agree only at the exact middle of the song.
##
## Takes the fraction on ONE reel rather than returning a pair, so there is no tuple whose order
## a caller can get backwards -- which is the mistake this surface is most exposed to, given that
## supply and takeup are otherwise identical objects.
##
## Signed: a negative song speed is a rewind, and turns the reel the other way.
static func reel_rate(on_reel: float, song_speed: float) -> float:
	var radius := pack_radius(on_reel)
	if radius <= 0.0:
		return 0.0
	return clampf(TAPE_SPEED * song_speed / radius, -MAX_SPOOL_RATE, MAX_SPOOL_RATE)


## Where the song is, as a fraction, or -1 when nobody has said how long the song is.
##
## `timeline_length()` always returns a usable number because it floors at one second, which is
## right for drawing a ruler and wrong for dividing by: against a backend with no timeline it
## would put both reels hard against their stops and call it a reading. -1 means "unknown", and
## the reels then sit half wound and stay there, which is a machine with a tape on it rather
## than a machine making a claim.
static func song_fraction(state: MixState) -> float:
	if state.project_length <= 0.0:
		return -1.0
	return clampf(state.position_seconds / state.project_length, 0.0, 1.0)


func _update_packs() -> void:
	if _left_pack == null or _right_pack == null:
		return
	var played := song_fraction(DAW.state)
	var left := 0.5 if played < 0.0 else 1.0 - played
	var right := 0.5 if played < 0.0 else played
	# Left is the supply reel and empties; right is the takeup and fills. Reversing these is
	# the kind of mistake nobody reports and everybody notices.
	(_left_pack.mesh as CylinderMesh).top_radius = pack_radius(left)
	(_left_pack.mesh as CylinderMesh).bottom_radius = pack_radius(left)
	(_right_pack.mesh as CylinderMesh).top_radius = pack_radius(right)
	(_right_pack.mesh as CylinderMesh).bottom_radius = pack_radius(right)

	if _tape_runs.size() == 3:
		var supply := Vector2(-REEL_SPACING * 0.5, 0.0)
		var takeup := Vector2(REEL_SPACING * 0.5, 0.0)
		var left_guide := Vector2(-GUIDE_X, PATH_Y)
		var right_guide := Vector2(GUIDE_X, PATH_Y)
		# Opposite sides, because the two reels are mirror images and one sign would run the
		# tape off the back of the takeup.
		_lay_run(_tape_runs[0], rim_crossing(supply, left_guide,
				tangent_point(supply, pack_radius(left), left_guide, -1.0), REEL_RADIUS),
				left_guide)
		_lay_run(_tape_runs[2], right_guide, rim_crossing(takeup, right_guide,
				tangent_point(takeup, pack_radius(right), right_guide, 1.0), REEL_RADIUS))


## THE LOCATOR, between the reels under the counter: back a marker, drop one, on a marker. And
## above the keys, the section the playhead is in -- read off the markers, which is what they are
## named for. A performer looks for "where am I in the song", and a bar number is the answer to
## a different question.
func _build_locator() -> void:
	_section_label = Label3D.new()
	_section_label.name = "Section"
	_section_label.font_size = 34
	_section_label.pixel_size = 0.00024
	_section_label.position = Vector3(0, 0.081, 0.002)
	_section_label.modulate = Color(0.88, 0.74, 0.44)
	_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(_section_label)
	_adopt(_section_label)

	for spec in [[-1, "PREV"], [0, "MARK"], [1, "NEXT"]]:
		var way: int = spec[0]
		var key := PanelButton.new()
		key.name = "Locate%s" % spec[1].capitalize()
		key.led_colour = Color(0.88, 0.74, 0.44)
		key.lamp_scale = Vector2(0.8, 0.45) if way == 0 else Vector2(0.45, 0.45)
		key.position = Vector3(float(way) * LOCATOR_PITCH, 0.044, 0.006)
		key.scale = Vector3(1.3, 1.3, 1.3)
		if way == 0:
			key.pressed.connect(_drop_marker)
			key.describe_title = func() -> String: return "TRANSPORT  ADD MARKER"
			key.describe_value = func(_v: float) -> String:
				if not DAW.can(DAWBackend.Capability.MARKERS):
					return "needs the ReaScript bridge"
				return "%s at %s" % [next_marker_name(DAW.state.markers),
						DAW.state.bar_beat(DAW.state.position_seconds)]
			_mark_key = key
		else:
			key.pressed.connect(func(): _locate(way))
			key.describe_title = func() -> String:
				return "TRANSPORT  " + ("PREVIOUS MARKER" if way < 0 else "NEXT MARKER")
			key.describe_value = func(_v: float) -> String:
				var at := marker_before(DAW.state.markers, DAW.state.position_seconds) if way < 0 \
						else marker_after(DAW.state.markers, DAW.state.position_seconds)
				if at < 0.0:
					return "the start" if way < 0 else "no marker after here"
				return str(DAW.state.markers.get(at, "")) if str(DAW.state.markers.get(at, "")) != "" \
						else DAW.state.bar_beat(at)
		_adopt(key)

		var legend := Label3D.new()
		legend.text = spec[1]
		legend.font_size = 22
		legend.pixel_size = 0.00024
		legend.position = Vector3(float(way) * LOCATOR_PITCH, 0.058, 0.002)
		legend.modulate = Color(0.6, 0.62, 0.66)
		legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Lettering.range_to_legibility(legend)
		_adopt(legend)


## Centre to centre, across the gap between the reels.
const LOCATOR_PITCH := 0.026
## How far behind the playhead a marker has to be for PREV to go to it rather than past it.
## Without it, PREV pressed while rolling lands on the marker just passed, the playhead moves a
## frame on, and the next press lands on the same marker: a key that cannot get further back.
const LOCATE_SLACK := 0.4


## The latest marker strictly before `seconds` less the slack, or -1 when there is none.
static func marker_before(markers: Dictionary, seconds: float) -> float:
	var best := -1.0
	for at in markers:
		if float(at) < seconds - LOCATE_SLACK and float(at) > best:
			best = float(at)
	return best


## The first marker after `seconds`, or -1.
static func marker_after(markers: Dictionary, seconds: float) -> float:
	var best := -1.0
	for at in markers:
		if float(at) > seconds + 0.001 and (best < 0.0 or float(at) < best):
			best = float(at)
	return best


## The marker at or before `seconds`: the section the playhead is in. "" before the first.
static func section_at(markers: Dictionary, seconds: float) -> String:
	var best := -1.0
	for at in markers:
		if float(at) <= seconds + 0.001 and float(at) > best:
			best = float(at)
	return str(markers[best]) if best >= 0.0 else ""


## What MARK calls the marker it drops: the next free number, the way Reaper numbers markers it
## was not told the name of.
static func next_marker_name(markers: Dictionary) -> String:
	var n := 1
	while markers.values().has("MARK %d" % n):
		n += 1
	return "MARK %d" % n


func _locate(way: int) -> void:
	var s := DAW.state
	var at := marker_before(s.markers, s.position_seconds) if way < 0 \
			else marker_after(s.markers, s.position_seconds)
	if at < 0.0:
		if way < 0:
			DAW.seek(0.0)
		return
	DAW.seek(at)


func _drop_marker() -> void:
	if not DAW.can(DAWBackend.Capability.MARKERS):
		return
	DAW.add_marker(DAW.state.position_seconds, next_marker_name(DAW.state.markers))


func _refresh() -> void:
	if _counter == null:
		return
	_counter.text = DAW.state.position_string
	_tempo_label.text = "%.1f BPM" % DAW.state.tempo
	_tempo_knob.apply_remote(bpm_to_knob(DAW.state.tempo))
	_play_lamp.lit = DAW.state.playing
	# Flashing on the beat while recording waits -- counting in, or short of the punch range --
	# and lit while it takes.
	var s := DAW.state
	_rec_lamp.lit = s.taking() or (s.recording and s.playing
			and fposmod(s.beat_at(s.position_seconds), 1.0) < 0.5)
	_punch_lamp.lit = s.punch
	_count_lamp.lit = DAW.state.count_in_bars > 0
	_loop_lamp.lit = DAW.state.looping
	_click_lamp.lit = DAW.state.metronome
	_section_label.text = section_at(DAW.state.markers, DAW.state.position_seconds).to_upper()
	_loop_label.text = _loop_text()
	for i in _history_keys.size():
		var depth := DAW.state.undo_depth if i == 0 else DAW.state.redo_depth
		_history_keys[i].lit = depth != 0


## The knob's sweep, in BPM. Wider than most songs and narrower than Reaper's 1-960, because a
## knob that spends nine tenths of its travel on tempos nobody plays is a knob you cannot set.
const TEMPO_LOW := 40.0
const TEMPO_HIGH := 240.0
## Taps further apart than this start a new count rather than averaging into the old one.
const TAP_GAP_MSEC := 2000
const TAPS_KEPT := 6


static func knob_to_bpm(v: float) -> float:
	return snappedf(lerpf(TEMPO_LOW, TEMPO_HIGH, clampf(v, 0.0, 1.0)), 0.1)


static func bpm_to_knob(bpm: float) -> float:
	return clampf(inverse_lerp(TEMPO_LOW, TEMPO_HIGH, bpm), 0.0, 1.0)


## The next count-in after `bars` on the COUNT key, round to none.
static func next_count_in(bars: int) -> int:
	for step in COUNT_IN_STEPS:
		if step > bars:
			return step
	return 0


## After [before playback, pre-roll], the next: neither, playback, playback with the song, the song.
static func next_count_mode(play: bool, song: bool) -> Vector2i:
	if not play and not song:
		return Vector2i(1, 0)
	if play and not song:
		return Vector2i(1, 1)
	if play and song:
		return Vector2i(0, 1)
	return Vector2i(0, 0)


## What the COUNT key says of a count-in.
static func count_in_text(s: MixState) -> String:
	if s.count_in_bars == 0:
		return "off: recording starts at once"
	var bars := "%d bar%s of click%s before recording%s" % [s.count_in_bars, "" if s.count_in_bars == 1 else "s",
			" and the song" if s.pre_roll else "", " and playback" if s.count_in_play else ""]
	return bars if s.metronome else bars + ", when the click is on"


## What the PUNCH key says of punching in and out.
static func punch_text(s: MixState) -> String:
	if not s.punch:
		return "off: recording takes all it plays"
	if not s.has_loop_range():
		return "on, but there is no loop range: recording takes all it plays"
	return "recording takes only %s to %s" % [s.bar_beat(s.loop_start), s.bar_beat(s.loop_end)]


## A press steps the bars; a fine press (shift on a monitor) steps what the count is for: recording
## alone, playback too, playback with the song under it (pre-roll), recording with the song. A
## count needs bars to count.
func _step_count_in() -> void:
	var by: Node = _count_lamp.held_by if _count_lamp != null else null
	if by != null and by.has_method("fine") and by.fine():
		var next := next_count_mode(DAW.state.count_in_play, DAW.state.pre_roll)
		DAW.set_count_in_play(next.x == 1)
		DAW.set_pre_roll(next.y == 1)
		if DAW.state.count_in_bars == 0:
			DAW.set_count_in(1)
		return
	DAW.set_count_in(next_count_in(DAW.state.count_in_bars))


## The tempo a run of taps means: the average gap across the whole run, not the last one, so
## one rushed tap moves it a little rather than a lot. 0 until there are two.
static func tapped_bpm(taps_msec: Array) -> float:
	if taps_msec.size() < 2:
		return 0.0
	var span := float(int(taps_msec[-1]) - int(taps_msec[0]))
	if span <= 0.0:
		return 0.0
	return snappedf(60000.0 * float(taps_msec.size() - 1) / span, 0.1)


func _tap() -> void:
	var now := Time.get_ticks_msec()
	if not _taps.is_empty() and now - _taps[-1] > TAP_GAP_MSEC:
		_taps.clear()
	_taps.append(now)
	while _taps.size() > TAPS_KEPT:
		_taps.pop_front()
	# Three taps before the tempo moves: two is one interval, and one interval is a guess.
	if _taps.size() >= 3:
		DAW.set_tempo(tapped_bpm(_taps))


func _loop_text() -> String:
	var s := DAW.state
	if not s.has_loop_range():
		return "NO LOOP"
	var a := s.bar_beat(s.loop_start)
	var b := s.bar_beat(s.loop_end)
	return "LOOP %s-%s" % [a.get_slice(".", 0) + "." + a.get_slice(".", 1),
			b.get_slice(".", 0) + "." + b.get_slice(".", 1)]


func _process(delta: float) -> void:
	super(delta)
	if _left_reel == null:
		return
	# Driven by where Reaper says the position IS, not by a local animation flag and not by the
	# playing flag either. Position is the only thing that cannot disagree with the DAW: a deck
	# that keeps spinning after a stop is a lie told peripherally, and so, less obviously, is a
	# deck that sits still through a scrub or a rewind. Both fall out of reading one number.
	_observe_speed(delta)
	var played := song_fraction(DAW.state)
	var on_supply := 0.5 if played < 0.0 else 1.0 - played
	var on_takeup := 0.5 if played < 0.0 else played
	# Left is supply, right is takeup, matching the packs. Each gets its own rate from its own
	# radius; sharing one would undo the point of computing it.
	_left_reel.rotation.z -= reel_rate(on_supply, _song_speed) * delta
	_right_reel.rotation.z -= reel_rate(on_takeup, _song_speed) * delta
	_motor_follows_transport(delta)
	_update_packs()
	_refresh()


## How fast the song is moving, in song-seconds per real second, from watching the position.
##
## Derived rather than asked for because there is nothing to ask: the transport state is three
## booleans and a position, with no rate in it. Differencing the position is therefore the only
## source, and it has the side benefit of being backend-agnostic -- a scrub, a locate and a
## rewind all look like position moving, which is exactly how the deck should treat them.
func _observe_speed(delta: float) -> void:
	var now := DAW.state.position_seconds
	if _last_position < 0.0 or delta <= 0.0:
		_last_position = now
		return
	var observed := (now - _last_position) / delta
	_last_position = now
	_song_speed = lerpf(_song_speed, observed, minf(1.0, delta * SPEED_FOLLOW))


## The deck hums while tape is moving, and the hum fades rather than switching.
##
## Same argument as the reels, and the same source: it follows the observed speed, so it cannot
## outlive a stop, and a rewind is audible because a rewind moves tape. The fade is because a
## motor does not start at speed -- but mostly because a looping sample cut off at full level
## clicks, and the click is louder than the hum.
func _motor_follows_transport(delta: float) -> void:
	if _motor == null:
		_motor = Foley.emitter(Foley.reel_motor(), -80.0)
		_left_reel.add_child(_motor)
		_motor.play()
	var speed := absf(_song_speed)
	var wanted := MOTOR_DB if speed > MOTOR_FLOOR_SPEED else -80.0
	_motor.volume_db = move_toward(_motor.volume_db, wanted, delta * MOTOR_FADE_DB_PER_SEC)
	# A spool-up sounds like one because the pitch rides the speed, 1x landing at unity. Capped
	# well short of 2x: past that a looping hum stops reading as a faster motor and starts
	# reading as a different sound, which loses the thing the pitch was there to tell you.
	_motor.pitch_scale = clampf(0.72 + speed * 0.28, 0.72, 1.9)


## Low: this runs continuously for as long as the transport does, so it sets the noise floor of
## the whole room rather than being an event in it.
const MOTOR_DB := -20.0
const MOTOR_FADE_DB_PER_SEC := 90.0
