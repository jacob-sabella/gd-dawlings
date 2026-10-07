class_name TimelineSurface
extends Surface

## The arrangement: a lane per track, the blocks on it, and the playhead crossing them.
##
## THE ONE SURFACE THAT IS NOT HARDWARE, and that is a decision rather than an oversight. Every
## other surface in this project is modelled as a thing you could buy: the console is a desk,
## the rack is nineteen inches wide, the bay has quarter-inch jacks. A timeline has no hardware
## ancestor -- a tape machine's equivalent is a reel you cannot see into -- and inventing one
## would mean a made-up object pretending to be remembered.
##
## So it is drawn as what it is: a flat panel, defaulting to SCREEN mode, which
## `Presentation.default_mode` already routes `&"timeline"` to in every medium including AR. A
## forty-minute song is absurd as furniture and perfectly readable flat, and an engineer in a
## headset wants it on a surface they can glance at rather than a wall they have to turn toward.
##
## It still builds in metres like everything else, because it can be put in the room if someone
## wants it there, and a surface that measured itself in pixels could not be.

## Panel geometry, in metres. Sized for a monitor at SCREEN_MARGIN and comfortable in the room.
const WIDTH := 0.86
const LANE_HEIGHT := 0.0168
const LANE_GAP := 0.0022
const HEADER_WIDTH := 0.108
const RULER_HEIGHT := 0.022
const DEPTH := 0.006

## Bars per ruler label. One number per bar is unreadable past about thirty bars, and a song is
## never thirty bars.
const LABEL_EVERY := 8

## Hairline between abutting items, in metres.
const EDGE_GAP := 0.0006

var _playhead: Node3D
var _lane_area_x := 0.0
var _lane_area_width := 0.0
var _top_y := 0.0
var _height := 0.0


func _ready() -> void:
	surface_kind = &"timeline"
	if surface_id == &"":
		surface_id = &"timeline"
	super()
	DAW.state.timeline_changed.connect(mark_dirty)


func _process(delta: float) -> void:
	super(delta)
	_move_playhead()


func _rebuild() -> void:
	_clear_built()
	_playhead = null

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		return

	var lanes := indices.size()
	_height = RULER_HEIGHT + lanes * (LANE_HEIGHT + LANE_GAP) + LANE_GAP
	_top_y = _height * 0.5
	_lane_area_x = -WIDTH * 0.5 + HEADER_WIDTH
	_lane_area_width = WIDTH - HEADER_WIDTH - 0.006

	_build_carcass()
	_build_ruler()

	var y := _top_y - RULER_HEIGHT - LANE_GAP - LANE_HEIGHT * 0.5
	for index in indices:
		_build_lane(DAW.state.track(index), y)
		y -= LANE_HEIGHT + LANE_GAP

	_build_playhead()
	_build_blindness_notice()


func _build_carcass() -> void:
	var panel := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(WIDTH, _height, DEPTH)
	panel.mesh = mesh
	panel.position = Vector3(0, 0, -DEPTH * 0.5)
	panel.material_override = Materials.chassis()
	_adopt(panel)

	# The track headers are a shade darker than the lanes behind them, which is the only thing
	# separating a name from the block it sits beside once a lane is 17mm tall.
	var gutter := MeshInstance3D.new()
	var gutter_mesh := BoxMesh.new()
	gutter_mesh.size = Vector3(HEADER_WIDTH, _height - RULER_HEIGHT, 0.0012)
	gutter.mesh = gutter_mesh
	gutter.position = Vector3(-WIDTH * 0.5 + HEADER_WIDTH * 0.5,
			-(RULER_HEIGHT * 0.5), 0.0007)
	gutter.material_override = Materials.recess()
	_adopt(gutter)


## Bar lines and numbers, spaced by tempo.
##
## In BARS rather than minutes, because every decision made while looking at an arrangement is
## made in bars -- "drop the second chorus" is bar 57, not 1:54. The seconds are still what is
## stored; this is only how it is read.
func _build_ruler() -> void:
	var span := DAW.state.timeline_length()
	var bar := 4.0 * 60.0 / maxf(DAW.state.tempo, 1.0)
	var bars := int(ceil(span / bar))

	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(WIDTH, RULER_HEIGHT, 0.0012)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, _top_y - RULER_HEIGHT * 0.5, 0.0007)
	strip.material_override = Materials.recess()
	_adopt(strip)

	for n in range(0, bars + 1, LABEL_EVERY):
		var x := _x_for(n * bar)
		if x > WIDTH * 0.5:
			break
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.0006, RULER_HEIGHT * 0.45, 0.0008)
		tick.mesh = tick_mesh
		tick.position = Vector3(x, _top_y - RULER_HEIGHT * 0.72, 0.0014)
		tick.material_override = Materials.legend()
		_adopt(tick)

		var label := _text(str(n + 1), 24, Color(0.60, 0.64, 0.70))
		label.position = Vector3(x + 0.0025, _top_y - RULER_HEIGHT * 0.26, 0.0016)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_adopt(label)

	# Section markers sit on the ruler, where the arrangement is actually named.
	for at in DAW.state.markers:
		var mx := _x_for(float(at))
		if mx > WIDTH * 0.5:
			continue
		var flag := _text(str(DAW.state.markers[at]).to_upper(), 20, Color(0.88, 0.74, 0.44))
		flag.position = Vector3(mx + 0.0025, _top_y - RULER_HEIGHT * 0.74, 0.0016)
		flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_adopt(flag)


## Says so, in the lane area, when the backend cannot see the arrangement.
##
## "I cannot read this project's items" and "this project has no items in it" look identical on
## a timeline and mean opposite things -- one is a limitation to work around, the other is a
## session waiting to be recorded. The patchbay already refuses to pretend about routing for the
## same reason; this is the same refusal.
func _build_blindness_notice() -> void:
	if DAW.can(DAWBackend.Capability.TIMELINE):
		return
	var notice := _text("NO ARRANGEMENT FROM %s" % DAW.summary().to_upper(), 24,
			Color(0.72, 0.60, 0.40))
	notice.position = Vector3(_lane_area_x + _lane_area_width * 0.5, 0.0, 0.004)
	_adopt(notice)


func _build_lane(t: MixState.TrackState, y: float) -> void:
	var bed := MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(_lane_area_width, LANE_HEIGHT, 0.0010)
	bed.mesh = bed_mesh
	bed.position = Vector3(_lane_area_x + _lane_area_width * 0.5, y, 0.0006)
	bed.material_override = Materials.recess()
	_adopt(bed)

	var chip := MeshInstance3D.new()
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.0030, LANE_HEIGHT, 0.0014)
	chip.mesh = chip_mesh
	chip.position = Vector3(-WIDTH * 0.5 + 0.0035, y, 0.0014)
	chip.material_override = Materials.led(t.colour, true)
	_adopt(chip)

	var name_label := _text(t.display_name(), 22, Color(0.82, 0.84, 0.87))
	name_label.position = Vector3(-WIDTH * 0.5 + 0.009, y, 0.0016)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_adopt(name_label)

	# The three states that change what you are looking at, as one glyph rather than three
	# buttons: a lane is too short to put controls on, and the controls are on the console.
	var flags := ""
	if t.rec_arm:
		flags += "●"
	if t.mute:
		flags += "M"
	if t.solo:
		flags += "S"
	if flags != "":
		var flag_label := _text(flags, 20,
				Color(0.90, 0.38, 0.33) if t.rec_arm else Color(0.72, 0.74, 0.78))
		flag_label.position = Vector3(_lane_area_x - 0.004, y, 0.0016)
		flag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_adopt(flag_label)

	for item in t.items:
		_build_item(item, t.colour, y, t.mute)


func _build_item(item: MixState.ItemState, tint: Color, y: float, lane_muted: bool) -> void:
	# Inset, so that two sections that butt up against each other -- which is what an
	# arrangement mostly is -- read as two blocks rather than one long one. A hairline gap does
	# what the edge shading of a real arranger does, at a size where shading would be invisible.
	var left := _x_for(item.start) + EDGE_GAP
	var right := _x_for(item.end()) - EDGE_GAP
	var width := right - left
	if width <= 0.0005:
		return

	var dim := item.muted or lane_muted
	var block := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, LANE_HEIGHT - 0.0024, 0.0014)
	block.mesh = mesh
	block.position = Vector3(left + width * 0.5, y, 0.0014)
	# Tinted with the track's colour but well down in value: at twelve lanes the blocks are most
	# of the panel, and a wall of saturated colour buries the playhead and the markers, which
	# are the two things actually being read.
	var body := tint.darkened(0.40).lerp(Color(0.16, 0.17, 0.19), 0.30)
	block.material_override = Materials.cap_plastic(body.darkened(0.55) if dim else body)
	_adopt(block)

	# The take strip along the top edge, which is how a block reads as a block rather than a
	# bar on a chart.
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(width, 0.0022, 0.0006)
	strip.mesh = strip_mesh
	strip.position = Vector3(left + width * 0.5, y + (LANE_HEIGHT - 0.0024) * 0.5 - 0.0011, 0.0022)
	strip.material_override = Materials.led(tint, not dim)
	_adopt(strip)


## A vertical line, kept as a node and MOVED each frame rather than rebuilt.
##
## The playhead is the one thing on this surface that changes continuously, and a surface
## rebuilds only when the project changes SHAPE -- so rebuilding to move it would mean tearing
## down and re-creating several hundred meshes thirty times a second.
func _build_playhead() -> void:
	_playhead = Node3D.new()

	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.0008, _height - RULER_HEIGHT * 0.4, 0.0010)
	line.mesh = mesh
	line.position = Vector3(0, -(RULER_HEIGHT * 0.2), 0.0026)
	line.material_override = Materials.led(Color(0.96, 0.86, 0.45), true)
	_playhead.add_child(line)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.0042, 0.0042, 0.0012)
	head.mesh = head_mesh
	head.position = Vector3(0, _top_y - 0.0021, 0.0028)
	head.material_override = Materials.led(Color(0.96, 0.86, 0.45), true)
	_playhead.add_child(head)

	_adopt(_playhead)
	_move_playhead()


func _move_playhead() -> void:
	if _playhead == null:
		return
	var x := _x_for(DAW.state.position_seconds)
	# Parked at the left edge rather than hidden when the playhead runs off the end: a timeline
	# with no playhead anywhere reads as broken, and a song that has run past the last bar it
	# drew is a scroll problem, not a missing transport.
	_playhead.position.x = clampf(x, _lane_area_x, _lane_area_x + _lane_area_width)
	_playhead.visible = DAW.state.timeline_length() > 0.0


## Seconds to a position across the lane area. The whole project is fitted to the panel -- there
## is no scroll and no zoom yet, which for a stand-in song is the right first answer and for a
## forty-minute session is not. See docs/loop_backlog.md.
func _x_for(seconds: float) -> float:
	var span := DAW.state.timeline_length()
	return _lane_area_x + clampf(seconds / span, 0.0, 1.0) * _lane_area_width


func _text(content: String, size: int, tint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = content
	l.font_size = size * 4
	l.pixel_size = 0.000055
	l.modulate = tint
	l.outline_size = 0
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l
