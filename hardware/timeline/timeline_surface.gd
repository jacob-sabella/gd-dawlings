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

## Candidate spacings for ruler labels, in bars. The ruler takes the first one that leaves the
## numbers far enough apart to read -- a fixed spacing is unreadable zoomed out and useless
## zoomed in, and the whole point of a zoom is that both happen.
const LABEL_STEPS := [1, 2, 4, 8, 16, 32, 64, 128]
## Minimum gap between two ruler numbers, in metres.
const LABEL_CLEARANCE := 0.042

## Hairline between abutting items, in metres.
const EDGE_GAP := 0.0006

const SCRUBBER_BAND := 0.016

## The window onto the project, in seconds. Zero span means "not set yet": the first rebuild
## that finds a project fits the whole of it, and after that the viewer owns the window.
var view_start := 0.0
var view_span := 0.0

var _playhead: Node3D
var _scrubber: TimelineScrubber
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

	# Built ONCE and never rebuilt, unlike everything else on this panel. A rebuild frees its
	# children, and the scrubber is the one control here that is held across frames -- freeing
	# it mid-drag would drop the grab on the very gesture that caused the rebuild.
	_scrubber = TimelineScrubber.new()
	_scrubber.name = "Scrubber"
	_scrubber.view_changed.connect(_on_view_changed)
	add_child(_scrubber)


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
	_height = RULER_HEIGHT + lanes * (LANE_HEIGHT + LANE_GAP) + LANE_GAP + SCRUBBER_BAND
	_top_y = _height * 0.5
	_lane_area_x = -WIDTH * 0.5 + HEADER_WIDTH
	_lane_area_width = WIDTH - HEADER_WIDTH - 0.006

	var project := DAW.state.timeline_length()
	if view_span <= 0.0:
		view_span = project
	_clamp_view(project)

	_build_carcass()
	_build_ruler()

	var y := _top_y - RULER_HEIGHT - LANE_GAP - LANE_HEIGHT * 0.5
	for index in indices:
		_build_lane(DAW.state.track(index), y)
		y -= LANE_HEIGHT + LANE_GAP

	_build_playhead()
	_build_blindness_notice()
	_place_scrubber(project)


func _place_scrubber(project: float) -> void:
	_scrubber.width = _lane_area_width
	_scrubber.project_length = project
	_scrubber.view_start = view_start
	_scrubber.view_span = view_span
	_scrubber.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			-_top_y + SCRUBBER_BAND * 0.52, 0.0016)
	_scrubber.refresh()


## Point the window at a part of the project. What the scrubber does, and what `--view` does.
func set_view(start: float, span: float) -> void:
	view_span = span
	view_start = start
	_clamp_view(DAW.state.timeline_length())
	mark_dirty()


func _on_view_changed(start: float, span: float) -> void:
	view_start = start
	view_span = span
	mark_dirty()


## Keeps the window inside the project. Needed on every rebuild and not only on a drag: a song
## that got shorter -- the last item deleted -- can leave the window entirely past the end,
## which draws a panel of nothing with no clue that scrolling left would fix it.
func _clamp_view(project: float) -> void:
	view_span = clampf(view_span, TimelineScrubber.MIN_SPAN, maxf(project, TimelineScrubber.MIN_SPAN))
	view_start = clampf(view_start, 0.0, maxf(project - view_span, 0.0))


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
	var bar := 4.0 * 60.0 / maxf(DAW.state.tempo, 1.0)
	var per_bar := bar / maxf(view_span, 0.0001) * _lane_area_width
	var step: int = LABEL_STEPS[-1]
	for candidate in LABEL_STEPS:
		if candidate * per_bar >= LABEL_CLEARANCE:
			step = candidate
			break
	var first := int(floor(view_start / bar / step)) * step
	var last := int(ceil((view_start + view_span) / bar))

	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(WIDTH, RULER_HEIGHT, 0.0012)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, _top_y - RULER_HEIGHT * 0.5, 0.0007)
	strip.material_override = Materials.recess()
	_adopt(strip)

	for n in range(first, last + 1, step):
		if n < 0:
			continue
		var x := _x_for(n * bar)
		if x < _lane_area_x - 0.0001 or x > _lane_right():
			continue
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
		if mx < _lane_area_x - 0.0001 or mx > _lane_right():
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
	if right < _lane_area_x or left > _lane_right():
		return
	# Clipped to the lane, not culled. An item that starts before the window and ends inside it
	# must still be drawn, or scrolling into the middle of a long block shows empty lane.
	left = maxf(left, _lane_area_x)
	right = minf(right, _lane_right())
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
	var at := DAW.state.position_seconds
	if _follow(at):
		return
	var x := _x_for(at)
	# Hidden rather than parked at the edge once it leaves the window. A playhead pinned to the
	# left edge while the song plays on somewhere else is a lie about where you are, and the
	# scrubber below already says which part of the project is on screen.
	_playhead.visible = x >= _lane_area_x and x <= _lane_right()
	_playhead.position.x = x


## Pages the window forward when the playhead runs off the right edge during playback.
##
## PAGES rather than scrolls continuously, which is the behaviour every arranger offers and most
## engineers leave on: a view that slides under a stationary playhead makes the whole
## arrangement move while you are trying to read it. Jumping a window at a time keeps the blocks
## still and moves the line across them.
##
## Only while rolling. Scrubbing by hand with the transport stopped is exactly when someone is
## looking somewhere other than the playhead, and yanking the view back would fight them.
func _follow(at: float) -> bool:
	if not DAW.state.playing or view_span <= 0.0:
		return false
	if at >= view_start and at <= view_start + view_span:
		return false
	var project := DAW.state.timeline_length()
	var target := clampf(at - view_span * 0.08, 0.0, maxf(project - view_span, 0.0))
	if is_equal_approx(target, view_start):
		return false
	view_start = target
	mark_dirty()
	return true


## Seconds to a position across the lane area, through the current window.
##
## DELIBERATELY UNCLAMPED. Clamping here would pile everything before the window onto the left
## edge as a stack of zero-width blocks and everything after it onto the right, which reads as
## real content at both ends of every scroll. Callers clip instead.
func _x_for(seconds: float) -> float:
	return _lane_area_x + (seconds - view_start) / maxf(view_span, 0.0001) * _lane_area_width


func _lane_right() -> float:
	return _lane_area_x + _lane_area_width


func _text(content: String, size: int, tint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = content
	l.font_size = size * 4
	l.pixel_size = 0.000055
	l.modulate = tint
	l.outline_size = 0
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l
