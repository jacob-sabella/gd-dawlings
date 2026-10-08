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
## What a track name may use of the header: the header less the chip at its left and room for
## three state flags at its right.
const NAME_SPAN := HEADER_WIDTH - 0.036
## The ruler is two bands: the loop band along the top, where the loop range is drawn and
## dragged out, and the bar numbers under it, which are clicked and dragged to move the playhead.
## Two strips rather than one with a modifier key, because a headset has no shift key and a
## gesture that changes meaning with a key you cannot see is one people get wrong.
const LOOP_BAND := 0.008
const NUMBERS_HEIGHT := 0.022
const RULER_HEIGHT := LOOP_BAND + NUMBERS_HEIGHT
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
var _seek_strip: TimelineRuler
var _loop_strip: TimelineRuler
## The loop range drawn on the loop band: a bar between the two ends, lit while looping.
var _loop_bar: MeshInstance3D
var _drawn_loop := Vector3(-1, -1, -1)
var _lane_area_x := 0.0
var _lane_area_width := 0.0
var _top_y := 0.0
var _height := 0.0

## The ruler's own container, so that scrolling can rebuild the numbers without rebuilding the
## lanes underneath them. See `_relayout_view`.
var _ruler: Node3D
## Item geometry, as two banks rather than two meshes per block. Sized to every item in the
## project and drawn down to whatever the window currently shows.
var _item_blocks: MeshBank
var _item_strips: MeshBank
## Where each lane sits, in build order, so items can be placed without walking the tree.
var _lane_y: Array[float] = []


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

	# The ruler's two bands, built once for the same reason: a scrub is held across frames.
	_seek_strip = TimelineRuler.new()
	_seek_strip.name = "SeekStrip"
	_seek_strip.kind = TimelineRuler.Kind.SEEK
	_seek_strip.seconds_at = _seconds_at_local_x
	add_child(_seek_strip)
	_loop_strip = TimelineRuler.new()
	_loop_strip.name = "LoopStrip"
	_loop_strip.kind = TimelineRuler.Kind.LOOP
	_loop_strip.seconds_at = _seconds_at_local_x
	add_child(_loop_strip)
	DAW.state.transport_changed.connect(_draw_loop)


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

	_ruler = Node3D.new()
	_ruler.name = "Ruler"
	_adopt(_ruler)

	# Banked before the lanes, because a lane claims into them as it is built. Sized to EVERY
	# item in the project rather than to the visible ones: the window changes constantly and the
	# project's shape does not, so this is the capacity that can be fixed at build time.
	var total_items := 0
	for index in indices:
		total_items += DAW.state.track(index).items.size()
	_item_blocks = MeshBank.boxes(Materials.cap_plastic(Color.WHITE))
	_item_blocks.name = "ItemBlocks"
	_adopt(_item_blocks)
	_item_strips = MeshBank.strips()
	_item_strips.name = "ItemStrips"
	_adopt(_item_strips)

	var bed_bank := MeshBank.parts(Vector3(_lane_area_width, LANE_HEIGHT, 0.0010),
			Materials.recess())
	bed_bank.name = "LaneBeds"
	_adopt(bed_bank)
	var chip_bank := MeshBank.lamps(Vector3(0.0030, LANE_HEIGHT, 0.0014))
	chip_bank.name = "LaneChips"
	_adopt(chip_bank)

	_lane_y.clear()
	var y := _top_y - RULER_HEIGHT - LANE_GAP - LANE_HEIGHT * 0.5
	for index in indices:
		_lane_y.append(y)
		_build_lane(DAW.state.track(index), y, bed_bank, chip_bank)
		y -= LANE_HEIGHT + LANE_GAP
	bed_bank.commit()
	chip_bank.commit()

	# One slot per item, claimed now and positioned by _relayout_view. A claim needs a transform
	# and the window has not been applied yet, so they start folded flat and are never drawn in
	# that state -- show_first(0) until the first layout.
	for i in total_items:
		_item_blocks.claim(Transform3D(), Color.WHITE)
		_item_strips.claim(Transform3D(), Color.WHITE)
	_item_blocks.commit()
	_item_strips.commit()

	_build_loop_bar()
	_build_playhead()
	_build_blindness_notice()
	_build_bank_notice()
	_place_scrubber(project)
	_relayout_view()


func _place_strips() -> void:
	if _seek_strip == null:
		return
	_seek_strip.width = _lane_area_width
	_seek_strip.height = NUMBERS_HEIGHT
	_seek_strip.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			_top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0018)
	_seek_strip.refresh()
	_loop_strip.width = _lane_area_width
	_loop_strip.height = LOOP_BAND
	_loop_strip.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			_top_y - LOOP_BAND * 0.5, 0.0018)
	_loop_strip.refresh()


## Seconds under a point given in a strip's own x (centred on the lane area).
func _seconds_at_local_x(x: float) -> float:
	var from_left := x + _lane_area_width * 0.5
	return view_start + from_left / maxf(_lane_area_width, 0.0001) * view_span


## The loop range on the loop band. Moved, not rebuilt, and only when it changed.
func _draw_loop() -> void:
	if _loop_bar == null or not is_instance_valid(_loop_bar):
		return
	var s := DAW.state
	var key := Vector3(s.loop_start, s.loop_end, (1.0 if s.looping else 0.0) + view_start * 1000.0 + view_span)
	if key == _drawn_loop:
		return
	_drawn_loop = key
	if not s.has_loop_range():
		_loop_bar.visible = false
		return
	var left := maxf(_x_for(s.loop_start), _lane_area_x)
	var right := minf(_x_for(s.loop_end), _lane_right())
	_loop_bar.visible = right > left
	if right <= left:
		return
	_loop_bar.scale = Vector3(right - left, 1, 1)
	_loop_bar.position = Vector3((left + right) * 0.5, _top_y - LOOP_BAND * 0.5, 0.0014)
	# The bar-graph material, not an LED: a lit LED this long blooms into a smear that hides
	# the bar numbers under it.
	_loop_bar.material_override = Materials.indicator_bar(Color(0.36, 0.62, 0.98) if s.looping
			else Color(0.30, 0.36, 0.46))


func _build_loop_bar() -> void:
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(WIDTH, LOOP_BAND, 0.0012)
	band.mesh = band_mesh
	band.position = Vector3(0, _top_y - LOOP_BAND * 0.5, 0.0007)
	band.material_override = Materials.chassis()
	_adopt(band)
	_loop_bar = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	# Unit width, scaled to the range, so moving the range is a transform and not a mesh.
	mesh.size = Vector3(1.0, LOOP_BAND * 0.62, 0.0010)
	_loop_bar.mesh = mesh
	_adopt(_loop_bar)
	_drawn_loop = Vector3(-1, -1, -1)
	_draw_loop()


func _place_scrubber(project: float) -> void:
	_scrubber.width = _lane_area_width
	_scrubber.project_length = project
	_scrubber.view_start = view_start
	_scrubber.view_span = view_span
	_scrubber.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			-_top_y + SCRUBBER_BAND * 0.52, 0.0016)
	_scrubber.refresh()
	_place_strips()
	_drawn_loop = Vector3(-1, -1, -1)
	_draw_loop()


## Point the window at a part of the project. What the scrubber does, and what `--view` does.
func set_view(start: float, span: float) -> void:
	view_span = span
	view_start = start
	_clamp_view(DAW.state.timeline_length())
	_relayout_view()
	_place_scrubber(DAW.state.timeline_length())


func _on_view_changed(start: float, span: float) -> void:
	view_start = start
	view_span = span
	# NOT mark_dirty(). Scrolling changes WHERE the project is looked at, not what shape it is,
	# and a full rebuild tore down and recreated every lane, every lane label and every item --
	# once per frame, for the whole of a drag. At twelve lanes that was survivable and at ninety
	# it was not. What actually depends on the window is the items and the ruler's numbers.
	_relayout_view()


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
## Rebuilt on every scroll, unlike the lanes. The numbers it shows ARE the window -- which bar
## you are looking at, which step is readable at this zoom -- so there is nothing to preserve.
## It is also a bounded handful of nodes whatever the project is, which is what makes rebuilding
## it per frame acceptable where rebuilding the lanes was not.
func _build_ruler() -> void:
	if _ruler == null:
		return
	for child in _ruler.get_children():
		child.free()

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
	strip_mesh.size = Vector3(WIDTH, NUMBERS_HEIGHT, 0.0012)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0007)
	strip.material_override = Materials.recess()
	_ruler.add_child(strip)

	for n in range(first, last + 1, step):
		if n < 0:
			continue
		var x := _x_for(n * bar)
		if x < _lane_area_x - 0.0001 or x > _lane_right():
			continue
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.0006, NUMBERS_HEIGHT * 0.45, 0.0008)
		tick.mesh = tick_mesh
		tick.position = Vector3(x, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.72, 0.0014)
		tick.material_override = Materials.legend()
		_ruler.add_child(tick)

		var label := _text(str(n + 1), 34, Color(0.60, 0.64, 0.70))
		label.position = Vector3(x + 0.0025, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.26, 0.0016)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_ruler.add_child(label)

	# Section markers sit on the ruler, where the arrangement is actually named.
	for at in DAW.state.markers:
		var mx := _x_for(float(at))
		if mx < _lane_area_x - 0.0001 or mx > _lane_right():
			continue
		var flag := _text(str(DAW.state.markers[at]).to_upper(), 28, Color(0.88, 0.74, 0.44))
		flag.position = Vector3(mx + 0.0025, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.74, 0.0016)
		flag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_ruler.add_child(flag)


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


## Says so, in the gutter, when these lanes are a BANK rather than the project.
##
## Same refusal as the notice above and the same failure it prevents, one level less obvious.
## A control surface protocol streams a window of tracks, so a 90-track session arrives here as
## 64 lanes -- and a timeline is read as a picture of the whole arrangement, which is exactly
## what makes a truncated one dangerous. The console has had a bank control since it was
## written; this surface was showing the same partial project with nothing saying so, and so
## was the patchbay.
##
## A caption and not a control, deliberately. There is one bank and it is a property of the
## session, so moving it belongs in one place -- two sets of bank buttons that can disagree
## about which bank you are on is worse than one.
func _build_bank_notice() -> void:
	var caption := DAW.state.bank_caption()
	if caption == "":
		return
	var notice := _text(caption, 18, Color(0.72, 0.60, 0.40))
	notice.position = Vector3(-WIDTH * 0.5 + 0.009, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0016)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_adopt(notice)


func _build_lane(t: MixState.TrackState, y: float, bed_bank: MeshBank,
		chip_bank: MeshBank) -> void:
	bed_bank.claim(Transform3D(Basis.IDENTITY,
			Vector3(_lane_area_x + _lane_area_width * 0.5, y, 0.0006)), Color.WHITE)
	# chip_colour and not lamp_colour, for the reason in Materials: this is the track's identity
	# and a clipped identity is no identity.
	chip_bank.claim(Transform3D(Basis.IDENTITY, Vector3(-WIDTH * 0.5 + 0.0035, y, 0.0014)),
			Materials.chip_colour(t.colour))

	# Half the lane's height, up from under a third: measured at 7px with the timeline focused
	# at 1600x900. The lane had the room; the header's width is what limits a long name, and
	# `fit` holds it there without letting it go below the size every name used to be.
	var name_label := _text(t.display_name(), 38, Color(0.82, 0.84, 0.87))
	name_label.position = Vector3(-WIDTH * 0.5 + 0.009, y, 0.0016)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Lettering.fit(name_label, NAME_SPAN, 38 * 4, 22 * 4)
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
		var flag_label := _text(flags, 32,
				Color(0.90, 0.38, 0.33) if t.rec_arm else Color(0.72, 0.74, 0.78))
		flag_label.position = Vector3(_lane_area_x - 0.004, y, 0.0016)
		flag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_adopt(flag_label)


## Everything that depends on WHERE the window is, redone without touching the tree.
##
## This is the whole reason the items are banked. Dragging the overview scrubber used to call
## mark_dirty() and get a full rebuild on the next frame: every lane bed, every lane label,
## every flag, every item, destroyed and recreated at the frame rate for the length of the
## drag. Now a scroll writes transforms into two MultiMeshes and rebuilds the ruler's numbers,
## which is a bounded handful of nodes whatever the track count.
func _relayout_view() -> void:
	if _item_blocks == null:
		return
	_build_ruler()

	var indices := DAW.state.track_indices()
	var slot := 0
	for i in indices.size():
		if i >= _lane_y.size():
			break
		var t := DAW.state.track(indices[i])
		for item in t.items:
			if slot >= _item_blocks.count():
				break
			if _place_item(item, t.colour, _lane_y[i], t.mute, slot):
				slot += 1
	# Items off the end of the window keep whatever they last held and are simply not drawn.
	_item_blocks.show_first(slot)
	_item_strips.show_first(slot)
	_draw_loop()


## Put one item in the banks at `slot`, or report that it is not on screen.
##
## Returns false without writing anything when the item falls outside the window, which is what
## lets the caller pack the visible ones into the low slots.
func _place_item(item: MixState.ItemState, tint: Color, y: float, lane_muted: bool,
		slot: int) -> bool:
	# Inset, so that two sections that butt up against each other -- which is what an
	# arrangement mostly is -- read as two blocks rather than one long one. A hairline gap does
	# what the edge shading of a real arranger does, at a size where shading would be invisible.
	var left := _x_for(item.start) + EDGE_GAP
	var right := _x_for(item.end()) - EDGE_GAP
	if right < _lane_area_x or left > _lane_right():
		return false
	# Clipped to the lane, not culled. An item that starts before the window and ends inside it
	# must still be drawn, or scrolling into the middle of a long block shows empty lane.
	left = maxf(left, _lane_area_x)
	right = minf(right, _lane_right())
	var width := right - left
	if width <= 0.0005:
		return false

	var dim := item.muted or lane_muted
	var block_height := LANE_HEIGHT - 0.0024
	# Tinted with the track's colour but well down in value: at twelve lanes the blocks are most
	# of the panel, and a wall of saturated colour buries the playhead and the markers, which
	# are the two things actually being read.
	var body := tint.darkened(0.40).lerp(Color(0.16, 0.17, 0.19), 0.30)
	if dim:
		body = body.darkened(0.55)
	# The bank holds unit cubes, so the size of an item IS its instance scale.
	_item_blocks.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(width, block_height, 0.0014)),
			Vector3(left + width * 0.5, y, 0.0014)))
	_item_blocks.set_colour(slot, body)

	# The take strip along the top edge, which is how a block reads as a block rather than a
	# bar on a chart.
	_item_strips.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(width, 0.0022, 0.0006)),
			Vector3(left + width * 0.5, y + block_height * 0.5 - 0.0011, 0.0022)))
	_item_strips.set_colour(slot, Materials.chip_colour(tint) if not dim
			else Materials.lamp_colour(tint, false))
	return true


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
	head.position = Vector3(0, _top_y - LOOP_BAND - 0.0021, 0.0028)
	head.material_override = Materials.led(Color(0.96, 0.86, 0.45), true)
	_playhead.add_child(head)

	_adopt(_playhead)
	_move_playhead()


func _move_playhead() -> void:
	if _playhead == null:
		return
	var at := DAW.state.position_seconds
	# Paging relays out in place, so the playhead is positioned through the NEW window in the
	# same frame. Returning here instead would leave it one frame behind the page it caused.
	_follow(at)
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
	# NOT mark_dirty(), for the reason in _on_view_changed -- and more so here. A hand drag is
	# at least something someone is doing on purpose and watching; this fires unattended, in
	# the middle of a take, once per window. A full rebuild there tears down and recreates
	# every lane label while the transport is rolling, which is the worst possible moment.
	_relayout_view()
	_place_scrubber(DAW.state.timeline_length())
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
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l
