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
## Given a wide frame the panel is wider than on its stand: the stand is built for WIDTH, but a
## screen is sixteen by nine and the band the timeline gets on it is short and long. More
## width is more time per lane, which is the one thing a timeline cannot have too much of.
const SCREEN_WIDTH := 1.30
var width := WIDTH
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
## How close to an item's edge a press trims it rather than moving it, in metres.
const EDGE_GRIP := 0.004

const SCRUBBER_BAND := 0.016
## Most lanes the panel shows at once. Past this the panel stopped being a timeline and became a
## wall: at 40 tracks it was 0.8 m tall and hung down over the middle of the console, hiding the
## faders a person had sat down to use. The rest scroll -- the wheel over the track names.
const MAX_LANES := 16
## Notes drawn on MIDI items, at most: a dense take on every lane is still one draw call, but
## its buffer is sized at build time.
const MAX_DRAWN_NOTES := 6000
## A note's least width, so a staccato note is a mark and not nothing.
const MIN_NOTE_WIDTH := 0.0008
## And least height: a millimetre is about a pixel at the distance the panel is read from, and a
## note thinner than that is not drawn at all. Neighbouring rows overlap rather than vanish.
const MIN_NOTE_HEIGHT := 0.0016
## An item's piano roll is at least this many semitones tall.
const MIN_NOTE_ROWS := 12
## A recorded take's waveform is drawn in columns this wide, each the loudest moment under it,
## and at most this many across the whole panel.
const WAVE_COLUMN := 0.0016
const MAX_DRAWN_WAVE := 1600

## The window onto the project, in seconds. Until the viewer zooms or scrolls, every rebuild
## fits the whole project; after that the viewer owns the window. Not "the first rebuild": with
## a live Reaper the first rebuild comes before the arrangement does, and fitting THAT pinned
## the window to a four-second stub of a four-minute song.
var view_start := 0.0
var _view_owned := false
## Index into the track list of the top lane shown.
var lane_first := 0
var _header: TimelineHeader
var _lane_slot: MeshInstance3D
var _lane_thumb: MeshInstance3D
var view_span := 0.0

var _playhead: Node3D
var _scrubber: TimelineScrubber
var _seek_strip: TimelineRuler
var _loop_strip: TimelineRuler
## The loop range drawn on the loop band: a bar between the two ends, lit while looping.
var _loop_bar: MeshInstance3D
var _lanes: TimelineLanes
var _split_key: PanelButton
var _split_caption: Label3D
var _save_key: PanelButton
var _save_caption: Label3D
## Copy and delete, in the corner under the track names: what is done to a selection once it is
## made, so beside where it is made.
var _copy_key: PanelButton
var _copy_caption: Label3D
var _delete_key: PanelButton
var _delete_caption: Label3D
## The selected item's gain, fades and notes, under the panel; see TimelineItemStrip.
var _item_controls: TimelineItemStrip
## Add, remove and name tracks, under the right-hand end; see TimelineTrackStrip.
var _track_controls: TimelineTrackStrip
## The track whose name was last pressed, for the track keys; 0 for none. This desk's own, not
## the DAW's selection: which track someone means to rename is not part of the mix.
var picked_track := 0
## [track, item, start] of an item being dragged, drawn there until it is let go; or empty.
var _preview: Array = []
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
## The notes of MIDI items, drawn on the items as a little piano roll. See _place_notes.
var _item_notes: MeshBank
## The loudness of recorded takes, drawn on their items. See _place_wave.
var _item_waves: MeshBank
## Where each lane sits, in build order, so items can be placed without walking the tree.
var _lane_y: Array[float] = []


func set_wide(wide: bool) -> void:
	var wanted := SCREEN_WIDTH if wide else WIDTH
	if not is_equal_approx(wanted, width):
		width = wanted
		mark_dirty()


func _ready() -> void:
	surface_kind = &"timeline"
	# Clear of the HUD line, above the desk.
	screen_top = 0.06
	if surface_id == &"":
		surface_id = &"timeline"
	super()
	DAW.timeline_changed.connect(mark_dirty)

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
	DAW.transport_changed.connect(_draw_loop)

	# The lanes, as one control: select, move, zoom. Built once, like the strips, because a move
	# is a held drag and every edit it makes rebuilds the panel under it.
	_lanes = TimelineLanes.new()
	_lanes.name = "Lanes"
	_lanes.surface = self
	add_child(_lanes)

	_header = TimelineHeader.new()
	_header.name = "Header"
	_header.surface = self
	add_child(_header)

	# Split, in the corner over the track names where the ruler has no numbers to show. Built
	# once for the same reason: pressing it changes the timeline, and a rebuild that freed the
	# key under the press would drop the release on the floor.
	_split_key = PanelButton.new()
	_split_key.name = "SplitKey"
	_split_key.led_colour = Color(0.95, 0.62, 0.32)
	_split_key.lamp_scale = Vector2(0.8, 0.5)
	_split_key.scale = Vector3(1.4, 1.4, 1.4)
	_split_key.pressed.connect(func(): DAW.split_selected(DAW.state.position_seconds))
	_split_key.describe_title = func() -> String: return "EDIT  SPLIT AT PLAYHEAD"
	_split_key.describe_value = func(_v: float) -> String:
		var n := _splittable()
		return "%d selected item(s) at %s" % [n, DAW.state.bar_beat(DAW.state.position_seconds)] \
				if n > 0 else "select an item under the playhead"
	add_child(_split_key)
	_split_caption = _text("SPLIT", 26, Color(0.62, 0.64, 0.68))
	_split_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_split_caption)
	DAW.transport_changed.connect(_light_split_key)
	DAW.timeline_changed.connect(_light_split_key)

	# Save, beside it: the arrangement is the project, and every DAW keeps save on its window.
	# Lit while pressing it does something; anyone in the room may, and the host's DAW decides
	# where it goes.
	_save_key = PanelButton.new()
	_save_key.name = "SaveKey"
	_save_key.led_colour = Color(0.45, 0.78, 0.95)
	_save_key.lamp_scale = Vector2(0.8, 0.5)
	_save_key.scale = Vector3(1.4, 1.4, 1.4)
	_save_key.pressed.connect(func(): DAW.save_project())
	_save_key.describe_title = func() -> String: return "PROJECT  SAVE"
	_save_key.describe_value = func(_v: float) -> String:
		if not DAW.can(DAWBackend.Capability.PROJECT_SAVE):
			return "this DAW cannot save from here"
		var file := DAW.project_file()
		return file.get_file() if not file.is_empty() else "where the host keeps it"
	add_child(_save_key)
	_save_caption = _text("SAVE", 26, Color(0.62, 0.64, 0.68))
	_save_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_save_caption)

	_copy_key = _selection_key("CopyKey", Color(0.55, 0.85, 0.55), "EDIT  DUPLICATE",
			func(): DAW.duplicate_selected())
	_copy_caption = _text("COPY", 26, Color(0.62, 0.64, 0.68))
	_copy_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_copy_caption)
	_delete_key = _selection_key("DeleteKey", Color(0.95, 0.38, 0.34), "EDIT  DELETE",
			func(): DAW.delete_selected())
	_delete_caption = _text("DEL", 26, Color(0.62, 0.64, 0.68))
	_delete_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_delete_caption)
	DAW.timeline_changed.connect(_light_selection_keys)

	_track_controls = TimelineTrackStrip.new()
	_track_controls.name = "TrackStrip"
	_track_controls.surface = self
	add_child(_track_controls)
	# A method, not a lambda: a method's connection goes when the surface does.
	DAW.tracks_renumbered.connect(_on_tracks_renumbered)

	_item_controls = TimelineItemStrip.new()
	_item_controls.name = "ItemStrip"
	_item_controls.surface = self
	add_child(_item_controls)


## A key that acts on the selected items, lit while there are any.
func _selection_key(key_name: String, colour: Color, title: String, act: Callable) -> PanelButton:
	var key := PanelButton.new()
	key.name = key_name
	key.led_colour = colour
	key.lamp_scale = Vector2(0.8, 0.5)
	key.scale = Vector3(1.4, 1.4, 1.4)
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String:
		var n := DAW.state.selected_items().size()
		return "%d selected item(s)" % n if n > 0 else "select an item first"
	add_child(key)
	return key


func _light_selection_keys() -> void:
	var any := not DAW.state.selected_items().is_empty()
	for key in [_copy_key, _delete_key]:
		if key != null:
			key.lit = any


func _process(delta: float) -> void:
	super(delta)
	_move_playhead()


func _rebuild() -> void:
	_clear_built()
	_playhead = null

	var indices := _shown()
	if indices.is_empty():
		return

	var lanes := indices.size()
	_height = RULER_HEIGHT + lanes * (LANE_HEIGHT + LANE_GAP) + LANE_GAP + SCRUBBER_BAND
	_top_y = _height * 0.5
	_lane_area_x = -width * 0.5 + HEADER_WIDTH
	_lane_area_width = width - HEADER_WIDTH - 0.006

	var project := DAW.state.timeline_length()
	if view_span <= 0.0 or not _view_owned:
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
	_item_notes = MeshBank.strips()
	_item_notes.name = "ItemNotes"
	_adopt(_item_notes)

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
	var total_notes := 0
	for index in indices:
		for item in DAW.state.track(index).items:
			total_notes += item.notes.size() / MidiTake.NOTE_WIDTH
	for i in mini(total_notes, MAX_DRAWN_NOTES):
		_item_notes.claim(Transform3D(), Color.WHITE)
	_item_notes.commit()
	_item_waves = MeshBank.strips()
	_item_waves.name = "ItemWaves"
	_adopt(_item_waves)
	var any_wave := false
	for index in indices:
		for item in DAW.state.track(index).items:
			any_wave = any_wave or not item.peaks.is_empty()
	if any_wave:
		for i in MAX_DRAWN_WAVE:
			_item_waves.claim(Transform3D(), Color.WHITE)
	_item_waves.commit()

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
	# Taller than the band it draws on, and only upward: above the top edge there is nothing
	# else to hit, and an eight-millimetre band seen across a forty-track room is a few pixels.
	_loop_strip.height = LOOP_BAND * 1.6
	_loop_strip.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			_top_y - LOOP_BAND + LOOP_BAND * 0.8, 0.0018)
	_loop_strip.refresh()

	var lanes_top := _top_y - RULER_HEIGHT
	var lanes_bottom := -_top_y + SCRUBBER_BAND
	_lanes.width = _lane_area_width
	_lanes.height = maxf(lanes_top - lanes_bottom, 0.001)
	_lanes.position = Vector3(_lane_area_x + _lane_area_width * 0.5,
			(lanes_top + lanes_bottom) * 0.5, 0.0018)
	_lanes.refresh()

	_header.width = HEADER_WIDTH - 0.010
	_header.height = _lanes.height
	_header.position = Vector3(-width * 0.5 + (HEADER_WIDTH - 0.010) * 0.5, _lanes.position.y, 0.0018)
	_header.refresh()
	_place_lane_ladder(lanes_top, lanes_bottom)

	var ruler_mid := _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5
	_split_key.position = Vector3(-width * 0.5 + 0.016, ruler_mid, 0.003)
	_split_caption.position = Vector3(-width * 0.5 + 0.030, ruler_mid, 0.0016)
	_save_key.position = Vector3(-width * 0.5 + 0.064, ruler_mid, 0.003)
	_save_caption.position = Vector3(-width * 0.5 + 0.078, ruler_mid, 0.0016)
	_save_key.lit = DAW.can(DAWBackend.Capability.PROJECT_SAVE)
	_light_split_key()
	var corner_mid := -_top_y + SCRUBBER_BAND * 0.5
	_copy_key.position = Vector3(-width * 0.5 + 0.016, corner_mid, 0.003)
	_copy_caption.position = Vector3(-width * 0.5 + 0.030, corner_mid, 0.0016)
	_delete_key.position = Vector3(-width * 0.5 + 0.064, corner_mid, 0.003)
	_delete_caption.position = Vector3(-width * 0.5 + 0.078, corner_mid, 0.0016)
	_light_selection_keys()
	_item_controls.position = Vector3(-width * 0.5 + 0.016, -_top_y - 0.016, 0.0)
	_track_controls.position = Vector3(width * 0.5 - 0.020 - 2 * TimelineTrackStrip.PITCH, -_top_y - 0.016, 0.0)
	_track_controls.refresh()


## Seconds under a point given in a strip's own x (centred on the lane area).
func _seconds_at_local_x(x: float) -> float:
	var from_left := x + _lane_area_width * 0.5
	return view_start + from_left / maxf(_lane_area_width, 0.0001) * view_span


## The tracks whose lanes are on the panel, top to bottom.
func _shown() -> Array:
	var all := DAW.state.track_indices()
	lane_first = clampi(lane_first, 0, maxi(all.size() - MAX_LANES, 0))
	return all.slice(lane_first, lane_first + MAX_LANES)


## Scroll the lanes by `lanes` (positive is further down the track list).
func scroll_lanes(lanes: int) -> bool:
	var before := lane_first
	lane_first += lanes
	_shown()
	if lane_first == before:
		return false
	mark_dirty()
	return true


## Selected items the playhead is inside: what a split would cut.
func _splittable() -> int:
	var n := 0
	var at := DAW.state.position_seconds
	for pair in DAW.state.selected_items():
		var item := DAW.state.item(pair[0], pair[1])
		if item != null and item.contains(at):
			n += 1
	return n


## Lit when pressing it would cut something. A split key that does nothing when pressed should
## say so before it is pressed, not after.
func _light_split_key() -> void:
	if _split_key != null:
		_split_key.lit = _splittable() > 0


## Which part of the track list is on the panel, drawn the way the bank selector draws it: a
## slot the length of the list and a lit block the length of what is shown. Only when there is
## more list than panel -- a ladder with nothing to scroll invites the question of why.
func _place_lane_ladder(top: float, bottom: float) -> void:
	if _lane_slot == null:
		_lane_slot = MeshInstance3D.new()
		_lane_slot.mesh = BoxMesh.new()
		_lane_slot.material_override = Materials.recess()
		add_child(_lane_slot)
		_lane_thumb = MeshInstance3D.new()
		var thumb := BoxMesh.new()
		thumb.size = Vector3(0.0024, 1.0, 0.0010)
		_lane_thumb.mesh = thumb
		_lane_thumb.material_override = Materials.indicator_bar(Color(0.38, 0.60, 0.92))
		add_child(_lane_thumb)
	var total := DAW.state.track_indices().size()
	var scrolls := total > MAX_LANES
	_lane_slot.visible = scrolls
	_lane_thumb.visible = scrolls
	if not scrolls:
		return
	var x := _lane_area_x - 0.0045
	var span := top - bottom - 0.004
	(_lane_slot.mesh as BoxMesh).size = Vector3(0.0034, span, 0.0008)
	_lane_slot.position = Vector3(x, (top + bottom) * 0.5, 0.0010)
	var tall := span * float(MAX_LANES) / float(total)
	var down := span * float(lane_first) / float(total)
	_lane_thumb.scale = Vector3(1, tall, 1)
	_lane_thumb.position = Vector3(x, top - 0.002 - down - tall * 0.5, 0.0016)


## Seconds under a point in the world, through the current window.
func seconds_at_point(global_point: Vector3) -> float:
	var local := to_local(global_point)
	return _seconds_at_local_x(local.x - (_lane_area_x + _lane_area_width * 0.5))


## [track, item] under a point in the world, or [] for bare lane.
func item_at_point(global_point: Vector3) -> Array:
	var local := to_local(global_point)
	var indices := _shown()
	var pitch := LANE_HEIGHT + LANE_GAP
	for i in mini(indices.size(), _lane_y.size()):
		if absf(local.y - _lane_y[i]) > pitch * 0.5:
			continue
		var at := seconds_at_point(global_point)
		for item in DAW.state.track(indices[i]).items:
			if at >= item.start and at <= item.end():
				return [indices[i], item.index]
		return []
	return []


## Which edge of the item under a point the point is on: -1 its left, 1 its right, 0 neither.
## The grip is a few millimetres of the item, and never more than a quarter of it, so a short item
## can still be picked up by its middle.
func item_edge_at_point(global_point: Vector3) -> int:
	var hit := item_at_point(global_point)
	if hit.is_empty():
		return 0
	var item := DAW.state.item(hit[0], hit[1])
	var x := to_local(global_point).x
	var left := _x_for(item.start)
	var right := _x_for(item.end())
	var grip := minf(EDGE_GRIP, (right - left) * 0.25)
	if x - left <= grip:
		return -1
	if right - x <= grip:
		return 1
	return 0


## The track whose lane is under a point in the world, or 0.
func track_at_point(global_point: Vector3) -> int:
	var local := to_local(global_point)
	var indices := _shown()
	for i in mini(indices.size(), _lane_y.size()):
		if absf(local.y - _lane_y[i]) <= (LANE_HEIGHT + LANE_GAP) * 0.5:
			return indices[i]
	return 0


func _on_tracks_renumbered(map: Dictionary) -> void:
	pick_track(int(map.get(picked_track, 0)))


## Pick a track for the track keys (0 for none). Its name is drawn lit.
func pick_track(index: int) -> void:
	if index == picked_track:
		return
	picked_track = index
	mark_dirty()
	if _track_controls != null:
		_track_controls.refresh()


## Whether there is a keyboard and a screen to type on: not in a headset.
func can_type() -> bool:
	return not get_viewport().use_xr


## A name typed for a track, on the monitor. The prompt, or null where there is nothing to type on.
func ask_track_name(index: int) -> NamePrompt:
	if not DAW.state.tracks.has(index) or not can_type():
		return null
	var prompt := NamePrompt.ask(self, "Name track %d" % index, DAW.state.track(index).name)
	prompt.answered.connect(func(text: String) -> void:
		if text != "" and DAW.state.tracks.has(index):
			DAW.rename_track(index, text))
	return prompt


## Draw an item somewhere other than where it is, for the length of a drag: moved to `start`, or
## trimmed to `start` and `length`. -1 clears.
func preview_item(track_index: int, item_index: int, start: float, length := -1.0) -> void:
	_preview = [] if track_index < 0 else [track_index, item_index, start, length]
	_relayout_view()


## Zoom the window by `factor` (under 1 is in), round the playhead when it is on screen and
## round the middle when not -- Reaper's own default, so a zoom never loses where you are.
func zoom_view(factor: float) -> void:
	var project := DAW.state.timeline_length()
	var at := DAW.state.position_seconds
	if at < view_start or at > view_start + view_span:
		at = view_start + view_span * 0.5
	var span := clampf(view_span * factor, TimelineScrubber.MIN_SPAN,
			maxf(project, TimelineScrubber.MIN_SPAN))
	set_view(at - (at - view_start) * span / maxf(view_span, 0.0001), span)


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
	band_mesh.size = Vector3(width, LOOP_BAND, 0.0012)
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
	_view_owned = true
	view_span = span
	view_start = start
	_clamp_view(DAW.state.timeline_length())
	_relayout_view()
	_place_scrubber(DAW.state.timeline_length())


func _on_view_changed(start: float, span: float) -> void:
	_view_owned = true
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
	mesh.size = Vector3(width, _height, DEPTH)
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
	gutter.position = Vector3(-width * 0.5 + HEADER_WIDTH * 0.5,
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

	# Bars through the tempo's changes; the label spacing goes by the bar at the left edge.
	var s := DAW.state
	var at_left := floorf(s.beat_at(view_start) / float(maxi(s.beats_per_bar, 1))) + 1.0
	var bar := s.bar_to_seconds(at_left + 1.0) - s.bar_to_seconds(at_left)
	var per_bar := bar / maxf(view_span, 0.0001) * _lane_area_width
	var step: int = LABEL_STEPS[-1]
	for candidate in LABEL_STEPS:
		if candidate * per_bar >= LABEL_CLEARANCE:
			step = candidate
			break
	var first := int(floor((at_left - 1.0) / step)) * step
	var last := int(ceil(s.beat_at(view_start + view_span) / float(maxi(s.beats_per_bar, 1))))

	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(width, NUMBERS_HEIGHT, 0.0012)
	strip.mesh = strip_mesh
	strip.position = Vector3(0, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0007)
	strip.material_override = Materials.recess()
	_ruler.add_child(strip)

	for n in range(first, last + 1, step):
		if n < 0:
			continue
		var x := _x_for(s.bar_to_seconds(n + 1.0))
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
	notice.position = Vector3(-width * 0.5 + 0.009, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0016)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_adopt(notice)


func _build_lane(t: MixState.TrackState, y: float, bed_bank: MeshBank,
		chip_bank: MeshBank) -> void:
	bed_bank.claim(Transform3D(Basis.IDENTITY,
			Vector3(_lane_area_x + _lane_area_width * 0.5, y, 0.0006)), Color.WHITE)
	# chip_colour and not lamp_colour, for the reason in Materials: this is the track's identity
	# and a clipped identity is no identity.
	chip_bank.claim(Transform3D(Basis.IDENTITY, Vector3(-width * 0.5 + 0.0035, y, 0.0014)),
			Materials.chip_colour(t.colour))

	# Half the lane's height, up from under a third: measured at 7px with the timeline focused
	# at 1600x900. The lane had the room; the header's width is what limits a long name, and
	# `fit` holds it there without letting it go below the size every name used to be.
	var name_label := _text(t.display_name(), 38,
			Color(1.0, 0.86, 0.55) if t.index == picked_track else Color(0.82, 0.84, 0.87))
	name_label.position = Vector3(-width * 0.5 + 0.009, y, 0.0016)
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
		flag_label.position = Vector3(_lane_area_x - 0.0085, y, 0.0016)
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

	var indices := _shown()
	var slot := 0
	var note_slot := 0
	var wave_slot := 0
	for i in indices.size():
		if i >= _lane_y.size():
			break
		var t := DAW.state.track(indices[i])
		for item in t.items:
			if slot >= _item_blocks.count():
				break
			var start: float = item.start
			var length: float = item.length
			# A trim draws the block at its new edges while its contents stay where they are in
			# the song; a move carries both.
			var content: float = item.start
			if not _preview.is_empty() and _preview[0] == indices[i] and _preview[1] == item.index:
				start = _preview[2]
				if _preview[3] >= 0.0:
					length = _preview[3]
				else:
					content = start
			if _place_item(item, start, t.colour, _lane_y[i], t.mute, slot, length):
				slot += 1
				note_slot = _place_notes(item, content, t.colour, _lane_y[i], item.muted or t.mute,
						note_slot)
				wave_slot = _place_wave(item, content, t.colour, _lane_y[i], item.muted or t.mute,
						wave_slot)
	# Items off the end of the window keep whatever they last held and are simply not drawn.
	_item_blocks.show_first(slot)
	_item_strips.show_first(slot)
	_item_notes.show_first(note_slot)
	_item_waves.show_first(wave_slot)
	_draw_loop()


## Put one item in the banks at `slot`, or report that it is not on screen.
##
## Returns false without writing anything when the item falls outside the window, which is what
## lets the caller pack the visible ones into the low slots.
func _place_item(item: MixState.ItemState, start: float, tint: Color, y: float,
		lane_muted: bool, slot: int, length := -1.0) -> bool:
	if length < 0.0:
		length = item.length
	# Inset, so that two sections that butt up against each other -- which is what an
	# arrangement mostly is -- read as two blocks rather than one long one. A hairline gap does
	# what the edge shading of a real arranger does, at a size where shading would be invisible.
	var left := _x_for(start) + EDGE_GAP
	var right := _x_for(start + length) - EDGE_GAP
	if right < _lane_area_x or left > _lane_right():
		return false
	# Clipped to the lane, not culled. An item that starts before the window and ends inside it
	# must still be drawn, or scrolling into the middle of a long block shows empty lane.
	left = maxf(left, _lane_area_x)
	right = minf(right, _lane_right())
	var span := right - left
	if span <= 0.0005:
		return false

	var dim := item.muted or lane_muted
	var block_height := LANE_HEIGHT - 0.0024
	# Tinted with the track's colour but well down in value: at twelve lanes the blocks are most
	# of the panel, and a wall of saturated colour buries the playhead and the markers, which
	# are the two things actually being read.
	var body := tint.darkened(0.40).lerp(Color(0.16, 0.17, 0.19), 0.30)
	if dim:
		body = body.darkened(0.55)
	# Selected reads the way it does in every arranger: the block lifts towards white. Lightened
	# rather than outlined, because an outline at a lane 17mm tall is a hairline nobody sees.
	if item.selected:
		body = body.lerp(Color(0.86, 0.88, 0.90), 0.34)
	# The bank holds unit cubes, so the size of an item IS its instance scale.
	_item_blocks.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(span, block_height, 0.0014)),
			Vector3(left + span * 0.5, y, 0.0014)))
	_item_blocks.set_colour(slot, body)

	# The take strip along the top edge, which is how a block reads as a block rather than a
	# bar on a chart.
	_item_strips.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(span, 0.0022, 0.0006)),
			Vector3(left + span * 0.5, y + block_height * 0.5 - 0.0011, 0.0022)))
	_item_strips.set_colour(slot, Materials.chip_colour(tint) if not dim
			else Materials.lamp_colour(tint, false))
	return true


## A MIDI item's notes, on the item, as an arranger draws them: time across, pitch up, the
## item's own range of pitches filling the block below its strip, so a bass line and a chord
## part both read as shapes rather than as a few dots at the bottom of a 128-note well. Clipped
## to the window like the block. Returns the next free slot.
func _place_notes(item: MixState.ItemState, start: float, tint: Color, y: float, dim: bool,
		slot: int) -> int:
	if item.notes.is_empty():
		return slot
	var layout := note_layout(item.notes)
	var low: int = layout["low"]
	var rows: int = layout["rows"]
	var block_height := LANE_HEIGHT - 0.0024
	# Below the take strip and clear of the block's bottom edge.
	var top := y + block_height * 0.5 - 0.0026
	var bottom := y - block_height * 0.5 + 0.0007
	var row := (top - bottom) / rows
	var left_edge := maxf(_x_for(start) + EDGE_GAP, _lane_area_x)
	var right_edge := minf(_x_for(start + item.length) - EDGE_GAP, _lane_right())
	# Ink on the block rather than light on it: the blocks are already the light thing on this
	# panel, and pale notes on a pale block read as a texture, not as notes.
	var colour := tint.darkened(0.62)
	if dim:
		colour = colour.darkened(0.6)
	var n := 0
	while n + MidiTake.NOTE_WIDTH <= item.notes.size() and slot < _item_notes.count():
		var on := start + item.notes[n]
		var off := start + item.notes[n + 1]
		var pitch := int(item.notes[n + 2])
		n += MidiTake.NOTE_WIDTH
		var left := maxf(_x_for(on), left_edge)
		var right := minf(maxf(_x_for(off), _x_for(on) + MIN_NOTE_WIDTH), right_edge)
		if right - left <= 0.0:
			continue
		var centre_y := bottom + (pitch - low + 0.5) * row
		_item_notes.move_slot(slot, Transform3D(
				Basis.IDENTITY.scaled(Vector3(right - left, maxf(row * 0.8, MIN_NOTE_HEIGHT), 0.0004)),
				Vector3((left + right) * 0.5, centre_y, 0.0022)))
		_item_notes.set_colour(slot, colour)
		slot += 1
	return slot


## A recorded take's loudness, on the item, as an arranger draws a waveform: a column for every
## few millimetres of panel, as tall as the loudest moment under it, mirrored about the middle
## of the block below its strip. Read from the item's overview (AudioTake.peaks), from where in
## the file the item starts, so the halves of a cut take each show their own part. Returns the
## next free slot.
func _place_wave(item: MixState.ItemState, start: float, tint: Color, y: float, dim: bool,
		slot: int) -> int:
	if item.peaks.is_empty():
		return slot
	var columns := wave_columns(item.peaks, item.source_offset, start, item.length,
			_x_for(start) + EDGE_GAP, _x_for(start + item.length) - EDGE_GAP,
			_lane_area_x, _lane_right(), WAVE_COLUMN)
	var block_height := LANE_HEIGHT - 0.0024
	var top := y + block_height * 0.5 - 0.0026
	var bottom := y - block_height * 0.5 + 0.0007
	var middle := (top + bottom) * 0.5
	var colour := tint.darkened(0.72)
	if dim:
		colour = colour.darkened(0.6)
	for c in columns:
		if slot >= _item_waves.count():
			break
		# On a square-root scale: a voice peaking at -12dB fills half the block, not a quarter,
		# so a take recorded at a sensible level is a shape and not a hairline.
		var height := maxf(sqrt(c[1]) * (top - bottom), MIN_NOTE_HEIGHT * 0.5)
		_item_waves.move_slot(slot, Transform3D(
				Basis.IDENTITY.scaled(Vector3(WAVE_COLUMN * 0.7, height, 0.0004)),
				Vector3(c[0], middle, 0.0022)))
		_item_waves.set_colour(slot, colour)
		slot += 1
	return slot


## The columns a take's overview draws as: [[x, loudness 0-1], ...], one per `column` of panel
## between `left` and `right`, clipped to [clip_left, clip_right]. Each is the loudest peak in
## the stretch of the file under it.
static func wave_columns(peaks: PackedByteArray, offset: float, start: float, length: float,
		left: float, right: float, clip_left: float, clip_right: float, column: float) -> Array:
	var out := []
	if peaks.is_empty() or right - left <= 0.0 or length <= 0.0:
		return out
	var per_metre := length / (right - left)
	var x := maxf(left, clip_left) + column * 0.5
	var end := minf(right, clip_right)
	while x < end:
		var from := offset + (x - column * 0.5 - left) * per_metre
		var to := offset + (x + column * 0.5 - left) * per_metre
		var a := clampi(int(floor(from * AudioTake.PEAKS_PER_SECOND)), 0, peaks.size())
		var b := clampi(int(ceil(to * AudioTake.PEAKS_PER_SECOND)), a, peaks.size())
		var loudest := 0
		for i in range(a, b):
			loudest = maxi(loudest, peaks[i])
		if b > a:
			out.append([x, loudest / 255.0])
		x += column
	return out


## The pitch rows an item's notes are drawn on: {low, rows}. At least an octave tall, so three
## notes a semitone apart do not fill the block like three bars.
static func note_layout(notes: PackedFloat32Array) -> Dictionary:
	var low := 127
	var high := 0
	var n := 0
	while n + MidiTake.NOTE_WIDTH <= notes.size():
		low = mini(low, int(notes[n + 2]))
		high = maxi(high, int(notes[n + 2]))
		n += MidiTake.NOTE_WIDTH
	if high < low:
		return {"low": 60, "rows": 12}
	var rows := high - low + 1
	if rows < MIN_NOTE_ROWS:
		low = maxi(0, low - (MIN_NOTE_ROWS - rows) / 2)
		rows = MIN_NOTE_ROWS
	return {"low": low, "rows": rows}


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
