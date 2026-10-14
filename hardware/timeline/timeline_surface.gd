class_name TimelineSurface
extends Surface

## The arrangement: a lane per track, the clips on it, and the playhead crossing them.
##
## THE ONE SURFACE THAT IS NOT HARDWARE, and not a screen either. Every other surface in this
## project is a thing you could buy; a timeline has no hardware ancestor, and drawn as a monitor
## it was a screen bolted into a room ("I hate the bars and the text and the whole screen concept
## ... we're in a 3d environment", 2026-10-14). So it is light and glass in the air, with no panel
## behind it (see TimelineFinish):
##
##   * each track a channel of smoked glass, a thread of its colour along its foot, and a cut gem
##     of that colour where its name is: dark when muted, ringed gold when soloed, red when armed;
##   * each clip a lit glass ingot standing out of its channel, its sound standing out of its face
##     as a relief -- louder stands further out -- and its notes as a skyline of bricks;
##   * the loop a wall of blue light behind the channels between its two ends;
##   * the playhead a blade of light through the whole depth of it, a bead riding along the top;
##   * the tools tokens on ledges under it, each its mark sculpted, not a word (TimelineDeck).
##
## Time still runs left to right and the tracks still stack, because that is how a song is read.
## It still defaults to SCREEN presentation on a monitor, and builds in metres like everything else.

## Panel geometry, in metres. Sized for a monitor at SCREEN_MARGIN and comfortable in the room.
const WIDTH := 0.86
## Given a wide frame the panel is wider than on its stand: the stand is built for WIDTH, but a
## screen is sixteen by nine and the band the timeline gets on it is short and long. More
## width is more time per lane, which is the one thing a timeline cannot have too much of.
const SCREEN_WIDTH := 1.30
var width := WIDTH
## Was 0.0168 -- measured illegible at normal play distance (2026-10-11: "everything is too
## damn hard to read... especially the timeline"). Raised toward LANE_HEIGHT_MAX; the grip still
## lets a person go bigger or smaller from here.
const LANE_HEIGHT := 0.0232
## How tall each lane is, and how wide the panel is against its own width for where it is shown:
## both the person's to choose, with the grip at the panel's bottom right corner.
var lane_height := LANE_HEIGHT
var width_scale := 1.0
const LANE_HEIGHT_MIN := 0.011
const LANE_HEIGHT_MAX := 0.032
const WIDTH_SCALE_MIN := 0.6
const WIDTH_SCALE_MAX := 1.6
## The panel was resized with the grip: the studio keeps the size in this person's layout.
signal size_chosen(width_scale: float, lane_height: float)
var _wide := false
var _grip: TimelineResizeGrip
const LANE_GAP := 0.0022
const HEADER_WIDTH := 0.16
## What a track name may use of the header: the header less the chip at its left and room for
## three state flags at its right.
const NAME_SPAN := HEADER_WIDTH - 0.036
## The ruler is two bands: the loop band along the top, where the loop range is drawn and
## dragged out, and the bar numbers under it, which are clicked and dragged to move the playhead.
## Two strips rather than one with a modifier key, because a headset has no shift key and a
## gesture that changes meaning with a key you cannot see is one people get wrong.
const LOOP_BAND := 0.008
const NUMBERS_HEIGHT := 0.024
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
## And the wall of its light behind the channels.
var _loop_veil: MeshInstance3D
static var _veil_looping: StandardMaterial3D
static var _veil_idle: StandardMaterial3D
const LOOP_COLOUR := Color(0.36, 0.62, 0.98)
var _lanes: TimelineLanes
## The controls under the arrangement: the tools and the pages (see TimelineDeck). The keys are
## kept by name too, since the surface lights them.
var deck: TimelineDeck
var item_page: TimelineItemPage
var track_page: TimelineTrackPage
var tempo_page: TimelineTempoPage
var render_page: TimelineRenderPage
var _undo_key: GlyphKey
var _redo_key: GlyphKey
var _split_key: GlyphKey
var _copy_key: GlyphKey
var _delete_key: GlyphKey
var _all_key: GlyphKey
var _zoom_out_key: GlyphKey
var _zoom_in_key: GlyphKey
var _fit_key: GlyphKey
var _lanes_key: GlyphKey
var _shelf_key: GlyphKey
var _road_key: GlyphKey
var _save_key: GlyphKey
## Where the song is, in bars, in the corner over the track names: the arrangement's own clock.
var _clock: Label3D
var _clock_said := ""
## The track whose name was last pressed, for the track keys; 0 for none. This desk's own, not
## the DAW's selection: which track someone means to rename is not part of the mix.
var picked_track := 0

## The shelf view: each track a shelf, each item a block standing on it that you can take hold
## of and slide along, or pick out and put on another shelf. The same arrangement as the flat
## view and the same edits; only how it is drawn changes, and the blocks are what you grab.
## Each person's own choice, like where they stand: nothing about it is shared.
var shelf := false
## How far a block stands out of the panel, and a selected one further, pulled off its shelf.
const BLOCK_DEPTH := 0.011
const PULL := 0.005
## The shelf board under each lane, out from the panel.
const SHELF_LIP := 0.013
## Between the lanes' right end and the panel's edge: the view keys that stood there went to the deck.
const RIGHT_MARGIN := 0.006
## The road view, instead of the lanes: see TimelineHighway. Each person's own, not shared.
var highway := false
var _highway: TimelineHighway
## The view key was pressed: the studio keeps the choice in this person's layout.
signal shelf_chosen(on: bool)
## The shelf boards, one per lane.
var _shelf_lips: MeshBank
## The item being dragged, which stands out of its shelf like a selected one: in the hand.
var _held_item: MixState.ItemState = null
## On the shelves, two per block: its shadow on the shelf behind it, and its bottom edge in
## shade. What makes a block read as standing out even seen straight on, as a screen is.
var _item_shades: MeshBank
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
## A line across each faded corner of an item, two slots an item. See _place_fades.
var _item_fades: MeshBank
## [track, item, fade in, fade out] drawn instead of the item's own while a fade is dragged.
var _fade_preview: Array = []
## How far down from a block's top its fade handles reach: the top of the block, where a fade's
## line ends, is the fade; the rest of the block's edge trims.
const FADE_GRIP_HEIGHT := 0.005
## An item's gain, written on it when it is not 0 dB: labels kept and reused as the window moves.
var _gain_labels: Node3D
## Item names, pooled as the gain labels are.
var _item_labels: Node3D
## The bottom edge of the lowest lane (or the automation row under it), where the grid stops.
var _lanes_bottom := 0.0
## Where each lane sits, in build order, so items can be placed without walking the tree.
var _lane_y: Array[float] = []

## The picked track's lane of automation, drawn over its own lane: the target shown, "" for none.
## See TimelineTrackStrip's LANE key, and TimelineLanes for editing it.
var shown_lane := ""
var _automation: MeshInstance3D
## The middle of the shown lane's row, or NAN while no lane is shown.
var _auto_row_y := NAN
## Points drawn instead of the lane's own during a drag; empty for none.
var _lane_preview: Array = []
const AUTOMATION_LINE := 0.0007
const AUTOMATION_DOT := 0.0026
## How near a point the pointer has to be to take hold of it, metres either way.
const AUTOMATION_GRIP := 0.003
const AUTOMATION_COLOUR := Color(1.0, 0.62, 0.22)
## The row the shown lane is drawn and edited in, under its track's own: two and a half lanes
## tall, as a lane the height of a track's put -4 and -18 dB a few millimetres apart. Derived
## from LANE_HEIGHT rather than a second constant, so the two cannot drift out of proportion
## again the way they did when LANE_HEIGHT alone was raised for legibility (2026-10-11).
const AUTOMATION_ROW := LANE_HEIGHT * 2.5


func set_wide(wide: bool) -> void:
	_wide = wide
	var wanted := (SCREEN_WIDTH if wide else WIDTH) * width_scale
	if not is_equal_approx(wanted, width):
		width = wanted
		mark_dirty()


## The panel's size: its width against the width it has where it is shown, and each lane's
## height. Kept within what stays readable and fits.
func set_size(scale: float, lane: float) -> void:
	scale = clampf(scale, WIDTH_SCALE_MIN, WIDTH_SCALE_MAX)
	lane = clampf(lane, LANE_HEIGHT_MIN, LANE_HEIGHT_MAX)
	if is_equal_approx(scale, width_scale) and is_equal_approx(lane, lane_height):
		return
	width_scale = scale
	lane_height = lane
	width = (SCREEN_WIDTH if _wide else WIDTH) * width_scale
	mark_dirty()


## The grip let go of: the size, as this person's choice.
func choose_size(scale: float, lane: float) -> void:
	set_size(scale, lane)
	size_chosen.emit(width_scale, lane_height)


func _ready() -> void:
	surface_kind = &"timeline"
	# Clear of the HUD line, above the desk.
	screen_top = 0.06
	# Surface's own default (0.33) was never tuned to the timeline's own width: at MAX_LANES and
	# the default lane height the panel needs about 0.51 of the view's height before its WIDTH
	# becomes the tighter constraint instead (matching how the console, the rack and the bay are
	# already framed), so 0.33 left it a third further from the eye than its own width already
	# allowed -- a bigger loss than any single lane's font size (2026-10-11: "the timeline is
	# still just ungodly unreadable"). Raised to 0.40: short of that 0.51 crossover on purpose,
	# because past about 0.42 the panel's own screen footprint grows down far enough to cover the
	# tape deck's tempo knob and, at a wider desk, Rig Roulette's wall -- a seat-click miss the
	# audit caught (`_seat_audit`), not a guess. 0.40 measured clean on every track count tried.
	screen_band = 0.40
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
	DAW.transport_changed.connect(_on_tempo_maybe_changed)

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

	# The resize grip, at the right-hand end of the scrubber's band: the panel's bottom right corner.
	_grip = TimelineResizeGrip.new()
	_grip.name = "ResizeGrip"
	_grip.surface = self
	add_child(_grip)

	_highway = TimelineHighway.new()
	_highway.name = "Highway"
	_highway.visible = false
	add_child(_highway)

	DAW.tracks_renumbered.connect(_on_tracks_renumbered)
	DAW.track_changed.connect(_on_track_changed)
	DAW.master_changed.connect(_on_master_changed)
	_automation = MeshInstance3D.new()
	_automation.name = "Automation"
	_automation.mesh = ImmediateMesh.new()
	var line := Materials.led(AUTOMATION_COLOUR, true).duplicate() as StandardMaterial3D
	line.cull_mode = BaseMaterial3D.CULL_DISABLED
	_automation.material_override = line
	_automation.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_automation)

	_clock = _text("1.1.00", 40, RULER_TEXT)
	_clock.name = "Clock"
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_clock)

	# Built once, every key in it, for the reason the strips are: a press rebuilds the panel, and a
	# rebuild that freed the key under the press would drop the release on the floor.
	_build_deck()


## The deck under the arrangement: its tools, then its pages. See TimelineDeck.
func _build_deck() -> void:
	deck = TimelineDeck.new()
	deck.name = "Deck"
	deck.surface = self
	add_child(deck)
	_undo_key = _tool("UndoKey", &"undo", TOOL_INK, "EDIT  UNDO", func(): DAW.undo(),
			func() -> String: return "the last edit", true)
	_redo_key = _tool("RedoKey", &"redo", TOOL_INK, "EDIT  REDO", func(): DAW.redo(),
			func() -> String: return "the edit undone last")
	_split_key = _tool("SplitKey", &"split", Color(0.95, 0.62, 0.32), "EDIT  SPLIT AT PLAYHEAD",
			func(): DAW.split_selected(DAW.state.position_seconds),
			func() -> String:
				var n := _splittable()
				return "%d selected item(s) at %s" % [n, DAW.state.bar_beat(DAW.state.position_seconds)] \
						if n > 0 else "select an item under the playhead", true)
	_copy_key = _tool("CopyKey", &"duplicate", Color(0.55, 0.85, 0.55), "EDIT  DUPLICATE",
			func(): DAW.duplicate_selected(), _selection_text)
	_delete_key = _tool("DeleteKey", &"delete", Color(0.95, 0.38, 0.34), "EDIT  DELETE",
			func(): DAW.delete_selected(), _selection_text)
	_all_key = _tool("SelectAllKey", &"select_all", Color(0.55, 0.7, 0.95), "EDIT  SELECT ALL",
			func(): DAW.select_all_items(), func() -> String: return "every item on every track")
	_zoom_out_key = _tool("ZoomOutKey", &"zoom_out", TOOL_INK, "VIEW  ZOOM OUT", func(): zoom_view(1.5),
			func() -> String: return "more of the song across the lanes", true)
	_zoom_in_key = _tool("ZoomInKey", &"zoom_in", TOOL_INK, "VIEW  ZOOM IN", func(): zoom_view(1.0 / 1.5),
			func() -> String: return "less of the song, bigger, round the playhead")
	_fit_key = _tool("FitKey", &"fit", TOOL_INK, "VIEW  FIT", fit_view,
			func() -> String: return "the whole song across the lanes")
	_lanes_key = _tool("LanesKey", &"lanes", VIEW_INK, "VIEW  LANES", func(): _choose_view(false, false),
			func() -> String: return "flat lanes of blocks", true)
	_lanes_key.toggle = true
	_shelf_key = _tool("ShelfKey", &"shelves", VIEW_INK, "VIEW  SHELVES", func(): _choose_view(true, false),
			func() -> String: return "blocks on shelves: drag one along, or onto another shelf")
	_shelf_key.toggle = true
	_road_key = _tool("RoadKey", &"road", VIEW_INK, "VIEW  ROAD", func(): _choose_view(shelf, true),
			func() -> String: return "the song coming down a road into the playhead")
	_road_key.toggle = true
	_save_key = _tool("SaveKey", &"save", Color(0.45, 0.78, 0.95), "PROJECT  SAVE", func(): DAW.save_project(),
			func() -> String:
				if not DAW.can(DAWBackend.Capability.PROJECT_SAVE):
					return "this DAW cannot save from here"
				var file := DAW.project_file()
				return file.get_file() if not file.is_empty() else "where the host keeps it", true)
	item_page = TimelineItemPage.new()
	item_page.name = "ItemPage"
	track_page = TimelineTrackPage.new()
	track_page.name = "TrackPage"
	tempo_page = TimelineTempoPage.new()
	tempo_page.name = "TempoPage"
	render_page = TimelineRenderPage.new()
	render_page.name = "RenderPage"
	for page in [item_page, track_page, tempo_page, render_page]:
		page.surface = self
		page.tab_name = {item_page: "ITEM", track_page: "TRACK", tempo_page: "TEMPO", render_page: "RENDER"}[page]
		page.tab_glyph = {item_page: &"item", track_page: &"track", tempo_page: &"tempo", render_page: &"render"}[page]
		deck.add_page(page)
	deck.show_page(item_page)
	DAW.transport_changed.connect(_light_split_key)
	DAW.timeline_changed.connect(_light_split_key)
	DAW.timeline_changed.connect(_light_selection_keys)
	_light_view_keys()


const TOOL_INK := Color(0.70, 0.74, 0.82)
const VIEW_INK := Color(0.98, 0.80, 0.42)


func _tool(key_name: String, mark: StringName, colour: Color, title: String, act: Callable,
		what: Callable, group := false) -> GlyphKey:
	var key := GlyphKey.new()
	key.name = key_name
	key.glyph = mark
	key.label = title
	key.led_colour = colour
	key.pressed.connect(act)
	key.describe_title = func() -> String: return title
	key.describe_value = func(_v: float) -> String: return what.call()
	deck.add_tool(key, group)
	return key


func _selection_text() -> String:
	var n := DAW.state.selected_items().size()
	return "%d selected item(s)" % n if n > 0 else "select an item first"


func _light_selection_keys() -> void:
	var any := not DAW.state.selected_items().is_empty()
	for key in [_copy_key, _delete_key]:
		if key != null:
			key.lit = any
	if _all_key != null:
		_all_key.lit = DAW.state.track_indices().any(func(i): return not DAW.state.track(i).items.is_empty())


## The three views as one choice: lanes, shelves, or the road over either.
func _choose_view(shelves: bool, road: bool) -> void:
	set_highway(road)
	if shelves != shelf:
		set_shelf(shelves)
		shelf_chosen.emit(shelf)
	_light_view_keys()


func _light_view_keys() -> void:
	if _lanes_key == null:
		return
	_lanes_key.lit = not shelf and not highway
	_shelf_key.lit = shelf and not highway
	_road_key.lit = highway


## The whole song across the lanes, as the panel shows it before anyone zooms.
func fit_view() -> void:
	set_view(0.0, DAW.state.timeline_length())


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
	# The master's lanes, shown while no track is picked, have their row under the last track.
	var auto_row := shown_lane != "" and (picked_track == 0 or indices.has(picked_track))
	_height = RULER_HEIGHT + lanes * (lane_height + LANE_GAP) + LANE_GAP + SCRUBBER_BAND \
			+ ((AUTOMATION_ROW + LANE_GAP) if auto_row else 0.0)
	_top_y = _height * 0.5
	_lane_area_x = -width * 0.5 + HEADER_WIDTH
	_lane_area_width = width - HEADER_WIDTH - RIGHT_MARGIN

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
	# Self-lit glass ingots (see TimelineFinish), the same on the shelves and off them.
	_item_blocks = TimelineFinish.ingots(0.0011)
	_item_blocks.name = "ItemBlocks"
	_adopt(_item_blocks)
	_item_strips = MeshBank.strips()
	_item_strips.name = "ItemStrips"
	_adopt(_item_strips)
	_item_notes = TimelineFinish.ingots(0.00035, 1.15)
	_item_notes.name = "ItemNotes"
	_adopt(_item_notes)

	var bed_bank := TimelineFinish.glass_bank()
	bed_bank.name = "LaneBeds"
	_adopt(bed_bank)
	var thread_bank := MeshBank.strips()
	thread_bank.name = "LaneThreads"
	_adopt(thread_bank)
	var chip_bank := MeshBank.meshed(_gem_mesh())
	chip_bank.material_override = TimelineFinish.gem()
	chip_bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chip_bank.name = "LaneChips"
	_adopt(chip_bank)

	_lane_y.clear()
	_auto_row_y = NAN
	var y := _top_y - RULER_HEIGHT - LANE_GAP - lane_height * 0.5
	for index in indices:
		_lane_y.append(y)
		_build_lane(DAW.state.track(index), y, bed_bank, chip_bank, thread_bank)
		y -= lane_height + LANE_GAP
		if auto_row and (index == picked_track or (picked_track == 0 and index == indices[-1])):
			_auto_row_y = y + lane_height * 0.5 - AUTOMATION_ROW * 0.5
			_build_automation_row(_auto_row_y)
			y -= AUTOMATION_ROW + LANE_GAP
	bed_bank.commit()
	chip_bank.commit()
	thread_bank.commit()
	_build_shelf_lips()
	_lanes_bottom = y + lane_height * 0.5 + LANE_GAP

	# One slot per item, claimed now and positioned by _relayout_view. A claim needs a transform
	# and the window has not been applied yet, so they start folded flat and are never drawn in
	# that state -- show_first(0) until the first layout.
	for i in total_items:
		_item_blocks.claim(Transform3D(), Color.WHITE)
		_item_strips.claim(Transform3D(), Color.WHITE)
	_item_blocks.commit()
	_item_strips.commit()
	_item_shades = TimelineFinish.glass_bank()
	_item_shades.name = "ItemShades"
	_adopt(_item_shades)
	for i in total_items * 2:
		_item_shades.claim(Transform3D(), Color.WHITE)
	_item_shades.commit()
	_item_fades = MeshBank.strips()
	_item_fades.name = "ItemFades"
	_adopt(_item_fades)
	for i in total_items * 2:
		_item_fades.claim(Transform3D(), Color.WHITE)
	_item_fades.commit()
	_gain_labels = Node3D.new()
	_gain_labels.name = "GainLabels"
	_adopt(_gain_labels)
	_item_labels = Node3D.new()
	_item_labels.name = "ItemLabels"
	_adopt(_item_labels)
	var total_notes := 0
	for index in indices:
		for item in DAW.state.track(index).items:
			total_notes += item.notes.size() / MidiTake.NOTE_WIDTH
	for i in mini(total_notes, MAX_DRAWN_NOTES):
		_item_notes.claim(Transform3D(), Color.WHITE)
	_item_notes.commit()
	_item_waves = TimelineFinish.ingots(0.0002, 1.2)
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
	_sync_highway()


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
	# Out to the blocks' faces on the shelves, so a press on a block is a press on the block.
	_lanes.front = (0.0007 + BLOCK_DEPTH + PULL) - TimelineLanes.DEPTH * 0.5 - 0.0018 if shelf else 0.0
	_lanes.refresh()

	_header.width = HEADER_WIDTH - 0.010
	_header.height = _lanes.height
	_header.position = Vector3(-width * 0.5 + (HEADER_WIDTH - 0.010) * 0.5, _lanes.position.y, 0.0018)
	_header.refresh()
	_place_lane_ladder(lanes_top, lanes_bottom)

	_grip.position = Vector3(width * 0.5 - RIGHT_MARGIN - TimelineResizeGrip.SIZE.x * 0.5,
			-_top_y + SCRUBBER_BAND * 0.5 + 0.001, 0.0016)
	_clock.position = Vector3(-width * 0.5 + 0.010, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.5, 0.0016)
	_save_key.lit = DAW.can(DAWBackend.Capability.PROJECT_SAVE)
	_light_split_key()
	_light_selection_keys()
	_light_view_keys()
	_place_deck()


## What the camera frames is the arrangement, not the deck under it: the deck is drawn as big
## as its keys need, and framing it too would shrink the lanes it is there to work on. It sits
## below the frame, in the empty wall under the arrangement.
func content_aabb() -> AABB:
	var was := deck.visible if deck != null else false
	if deck != null:
		deck.visible = false
	var box := super()
	if deck != null:
		deck.visible = was
	return box


## The deck under the panel, from its left edge, as wide as it may be.
func _place_deck() -> void:
	if deck == null:
		return
	# From where the lanes start, not the panel's left edge: under the names, the deck's first
	# tokens sat over the rack's handle as seen from the seat.
	deck.width = width * TimelineDeck.SHARE - HEADER_WIDTH * 0.6
	deck.layout()
	deck.position = Vector3(-width * 0.5 + HEADER_WIDTH * 0.6, -_top_y - DECK_DROP, 0.0)


## Between the arrangement's bottom edge and the deck's top: the two read as one display, a seam
## apart, rather than as a screen with a box hung under it.
const DECK_DROP := 0.004


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
	var pitch := lane_height + LANE_GAP
	for i in mini(indices.size(), _lane_y.size()):
		if absf(local.y - _lane_y[i]) > pitch * 0.5:
			continue
		var at := seconds_at_point(global_point)
		for item in DAW.state.track(indices[i]).items:
			if at >= item.start and at <= item.end():
				return [indices[i], item.index]
		return []
	return []


## Which fade's handle a point is on: -1 the fade in's, 1 the fade out's, 0 neither. A handle is
## where its line ends at the block's top -- the block's top corner for a fade of nothing -- a
## few millimetres either side, as an edge's grip is.
func fade_handle_at_point(global_point: Vector3) -> int:
	var hit := item_at_point(global_point)
	if hit.is_empty():
		return 0
	var row := _shown().find(hit[0])
	if row < 0 or row >= _lane_y.size():
		return 0
	var local := to_local(global_point)
	var top := _lane_y[row] + (lane_height - 0.0024) * 0.5
	if local.y < top - FADE_GRIP_HEIGHT:
		return 0
	var item := DAW.state.item(hit[0], hit[1])
	var in_at := _x_for(item.start + minf(item.fade_in, item.length)) + (EDGE_GAP if item.fade_in <= 0.0 else 0.0)
	var out_at := _x_for(item.end() - minf(item.fade_out, item.length)) - (EDGE_GAP if item.fade_out <= 0.0 else 0.0)
	var grip := minf(EDGE_GRIP, (_x_for(item.end()) - _x_for(item.start)) * 0.25)
	var to_in := absf(local.x - in_at)
	var to_out := absf(local.x - out_at)
	if to_in <= grip and to_in <= to_out:
		return -1
	if to_out <= grip:
		return 1
	return 0


## The fades an item is drawn with while they are dragged; (-1, -1) for none.
func preview_fades(track_index: int, item_index: int, fade_in := 0.0, fade_out := 0.0) -> void:
	_fade_preview = [] if track_index < 0 else [track_index, item_index, fade_in, fade_out]
	_relayout_view()


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
		if absf(local.y - _lane_y[i]) <= (lane_height + LANE_GAP) * 0.5:
			return indices[i]
	return 0


## The ruler counts bars through the tempo and the time signature, so a new tempo, a new map or
## a new signature draws it again.
## The time signature's changes and the SIG key that makes them.
const SIGNATURE_COLOUR := Color(0.75, 0.6, 0.95)
var _drawn_tempo: Array = []


func _on_tempo_maybe_changed() -> void:
	var now: Array = [DAW.state.tempo, DAW.state.tempo_points, DAW.state.beats_per_bar, DAW.state.beat_unit,
			DAW.state.time_signature_points]
	if now == _drawn_tempo:
		return
	_drawn_tempo = now.duplicate(true)
	if _ruler != null:
		_relayout_view()


func _on_tracks_renumbered(map: Dictionary) -> void:
	pick_track(int(map.get(picked_track, 0)))


## Pick a track for the track keys (0 for none). Its name is drawn lit.
func pick_track(index: int) -> void:
	if index == picked_track:
		return
	var was := picked_track
	picked_track = index
	# Picking a track or putting it down passes between a track's lanes and the master's (shown
	# while nothing is picked): the lane shown belongs to neither.
	if (was == 0) != (index == 0) or not lane_targets(index).has(shown_lane):
		shown_lane = ""
	_lane_preview = []
	_draw_automation()
	mark_dirty()
	if track_page != null:
		track_page.refresh()
		if index > 0 and deck != null:
			deck.show_page(track_page)


func _on_track_changed(index: int, field: StringName) -> void:
	if index == picked_track and shown_lane != "" and field in [&"automation", &"volume", &"pan", &"mute", &"sends", &"send"]:
		_draw_automation()


func _on_master_changed(field: StringName) -> void:
	if picked_track == 0 and shown_lane != "" and field in [&"automation", &"volume", &"pan"]:
		_draw_automation()


# --- automation ----------------------------------------------------------------------------

## What a track's LANE key steps through: its fader, pan and mute, each send, and any other lane
## it already has (a plugin's parameter, written by touch or latch or read from a file). Track 0 is
## the master, whose fader and pan are all it has.
static func lane_targets(index: int) -> Array:
	if index == 0:
		return ["volume", "pan"]
	if not DAW.state.tracks.has(index):
		return []
	var t := DAW.state.track(index)
	var out: Array = ["volume", "pan", "mute"]
	var slots: Array = t.sends.keys()
	slots.sort()
	for slot in slots:
		var sd: MixState.SendState = t.sends[slot]
		var dest := sd.resolve(DAW.state)
		if dest > 0 and not sd.key and not out.has("send:%d" % dest):
			out.append("send:%d" % dest)
	var others: Array = t.automation.keys()
	others.sort()
	for target in others:
		if not out.has(target):
			out.append(target)
	return out


## Shows `target` on the picked track ("" for none).
func show_lane(target: String) -> void:
	var row_changes := target != shown_lane
	shown_lane = target
	_lane_preview = []
	_draw_automation()
	# The row opens or closes under the track, and the lanes below it move: a rebuild.
	if row_changes:
		mark_dirty()


## The shown lane's points as drawn: the preview while one is being dragged.
func shown_points() -> Array:
	if not _lane_preview.is_empty():
		return _lane_preview
	if shown_lane == "":
		return []
	if picked_track == 0:
		return DAW.state.master.automation.get(shown_lane, [])
	if not DAW.state.tracks.has(picked_track):
		return []
	return DAW.state.track(picked_track).automation.get(shown_lane, [])


func preview_lane(points: Array) -> void:
	_lane_preview = points
	_draw_automation()


## Whether a press here is on the shown lane.
func on_shown_lane(global_point: Vector3) -> bool:
	if shown_lane == "" or is_nan(_auto_row_y):
		return false
	return absf(to_local(global_point).y - _auto_row_y) <= AUTOMATION_ROW * 0.5


## Where a control is with no lane: what the lane is drawn at until it has a point. Track 0 is
## the master.
static func control_value(index: int, target: String) -> float:
	if index == 0:
		return DAW.state.master.volume_db if target == "volume" else DAW.state.master.pan * 2.0 - 1.0
	var t := DAW.state.track(index)
	match DawKitAutomation.kind_of(target):
		"volume":
			return t.volume_db
		"pan":
			return t.pan * 2.0 - 1.0
		"mute":
			return 1.0 if t.mute else 0.0
		"send":
			for slot in t.sends:
				var sd: MixState.SendState = t.sends[slot]
				if sd.resolve(DAW.state) == int(target.substr(5)):
					return DAW.taper_to_db(sd.volume)
		"fx":
			var parts := target.split(":")
			var f := DAW.state.fx(index, int(parts[1]), false)
			if f != null:
				return float(f.params.get(int(parts[2]), 0.0))
	return 0.0


## The decibels a level's lane spans, bottom to top. Straight in dB rather than along the fader's
## travel: on a lane a centimetre and a half tall the fader's taper puts -4 and -18 dB a millimetre
## apart. The bottom is silence.
const LANE_DB_LOW := -48.0
const LANE_DB_HIGH := 12.0


## How far up its lane a value is drawn, 0 to 1: a level in dB, pan with left at the top and a
## mute with heard at the top, as Reaper draws them.
static func lane_fraction(target: String, v: float) -> float:
	match DawKitAutomation.kind_of(target):
		"volume", "send":
			return clampf((v - LANE_DB_LOW) / (LANE_DB_HIGH - LANE_DB_LOW), 0.0, 1.0)
		"pan":
			return (1.0 - v) * 0.5
		"mute":
			return 1.0 - v
	return clampf(v, 0.0, 1.0)


static func lane_value(target: String, f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	match DawKitAutomation.kind_of(target):
		"volume", "send":
			return -150.0 if f <= 0.001 else lerpf(LANE_DB_LOW, LANE_DB_HIGH, f)
		"pan":
			return 1.0 - f * 2.0
		"mute":
			return 1.0 if f < 0.5 else 0.0
	return f


static func lane_text(target: String, v: float) -> String:
	match DawKitAutomation.kind_of(target):
		"volume", "send":
			return "-inf dB" if v <= -149.0 else "%+.1f dB" % v
		"pan":
			if absf(v) < 0.005:
				return "centre"
			return "%d%% %s" % [roundi(absf(v) * 100.0), "left" if v < 0.0 else "right"]
		"mute":
			return "muted" if v >= 0.5 else "heard"
	return "%.3f" % v


static func lane_name(target: String) -> String:
	match DawKitAutomation.kind_of(target):
		"volume", "pan", "mute":
			return target.to_upper()
		"send":
			var to := int(target.substr(5))
			return "SEND TO %s" % (DAW.state.track(to).display_name().to_upper() if DAW.state.tracks.has(to) else str(to))
		"fx":
			var parts := target.split(":")
			return "FX %d  PARAM %d" % [int(parts[1]), int(parts[2])]
	return target.to_upper()


## The row the shown lane belongs to: its track's, or the last track's for the master.
func _picked_row() -> int:
	if picked_track == 0:
		return _lane_y.size() - 1
	return _shown().find(picked_track)


## The lane's drawing height: inside its row, clear of the edges.
func _automation_y(_row: int, v: float) -> float:
	return _auto_row_y + (lane_fraction(shown_lane, v) - 0.5) * (AUTOMATION_ROW - 0.004)


## The value at a point's height on the shown lane.
func value_at_point(global_point: Vector3) -> float:
	var row := _picked_row()
	if row < 0 or row >= _lane_y.size() or is_nan(_auto_row_y):
		return 0.0
	var f := (to_local(global_point).y - _auto_row_y) / (AUTOMATION_ROW - 0.004) + 0.5
	return lane_value(shown_lane, f)


## The shown lane's point under a point in the world, or -1.
func automation_point_at(global_point: Vector3) -> int:
	var row := _picked_row()
	if row < 0 or row >= _lane_y.size() or is_nan(_auto_row_y):
		return -1
	var local := to_local(global_point)
	var points := shown_points()
	var best := -1
	var nearest := AUTOMATION_GRIP
	for i in points.size():
		var d := absf(_x_for(float(points[i][0])) - local.x)
		if d <= nearest and absf(_automation_y(row, float(points[i][1])) - local.y) <= AUTOMATION_GRIP * 2.0:
			nearest = d
			best = i
	return best


## The shown lane through the window: a line, stepped where a point holds, and a dot per point.
func _draw_automation() -> void:
	if _automation == null:
		return
	var mesh := _automation.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var row := _picked_row()
	if shown_lane == "" or row < 0 or row >= _lane_y.size() or view_span <= 0.0 or is_nan(_auto_row_y):
		return
	var points := shown_points()
	var fallback := control_value(picked_track, shown_lane)
	var from := view_start
	var to := view_start + view_span
	var path: Array[Vector2] = []
	path.append(Vector2(_x_for(from), _automation_y(row, DawKitAutomation.value_in(points, from, fallback))))
	for pt in points:
		var at := float(pt[0])
		if at <= from or at >= to:
			continue
		path.append(Vector2(_x_for(at), _automation_y(row, DawKitAutomation.value_in(points, at - 0.000001, fallback))))
		path.append(Vector2(_x_for(at), _automation_y(row, float(pt[1]))))
	path.append(Vector2(_x_for(to), _automation_y(row, DawKitAutomation.value_in(points, to, fallback))))
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := 0.0030
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		if a.distance_to(b) < 0.00001:
			continue
		var n := (b - a).normalized().orthogonal() * AUTOMATION_LINE * 0.5
		_quad(mesh, a - n, a + n, b + n, b - n, z)
	for pt in points:
		var at := float(pt[0])
		if at < from or at > to:
			continue
		var c := Vector2(_x_for(at), _automation_y(row, float(pt[1])))
		var h := AUTOMATION_DOT * 0.5
		_quad(mesh, c + Vector2(-h, -h), c + Vector2(-h, h), c + Vector2(h, h), c + Vector2(h, -h), z + 0.0002)
	mesh.surface_end()


static func _quad(mesh: ImmediateMesh, a: Vector2, b: Vector2, c: Vector2, d: Vector2, z: float) -> void:
	for v in [a, b, c, a, c, d]:
		mesh.surface_set_normal(Vector3(0, 0, 1))
		mesh.surface_add_vertex(Vector3(v.x, v.y, z))


## Whether there is a keyboard and a screen to type on: not in a headset.
## Type on the keypad in the room rather than the monitor's keyboard. Always so in a headset.
var type_on_desk := false
## The keypad open now, if any: one at a time.
var _pad: TypingPad = null


## Whether a name is typed on the monitor's keyboard; otherwise on a TypingPad in front of the
## panel.
func types_on_screen() -> bool:
	return not type_on_desk and not get_viewport().use_xr


## A name typed for a track: on the monitor, or in a headset on a keypad in front of the panel.
## The NamePrompt or TypingPad, or null for no such track.
func ask_track_name(index: int) -> Node:
	if not DAW.state.tracks.has(index):
		return null
	var title := "Name track %d" % index
	var asker: Node
	if types_on_screen():
		asker = NamePrompt.ask(self, title, DAW.state.track(index).name)
	else:
		if is_instance_valid(_pad):
			_pad.queue_free()
		# Below the panel's middle and towards whoever is at it, tipped up to face them.
		var where := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(_lane_area_x + _lane_area_width * 0.5,
				_top_y - _height - 0.13, 0.09))
		_pad = TypingPad.ask(self, title, DAW.state.track(index).name, where)
		asker = _pad
	asker.answered.connect(_rename_to.bind(index))
	return asker


func _rename_to(text: String, index: int) -> void:
	if text != "" and DAW.state.tracks.has(index):
		DAW.rename_track(index, text)


## Draw an item somewhere other than where it is, for the length of a drag: moved to `start`, or
## trimmed to `start` and `length`. -1 clears.
func preview_item(track_index: int, item_index: int, start: float, length := -1.0, to_track := -1) -> void:
	_preview = [] if track_index < 0 else [track_index, item_index, start, length, to_track]
	_held_item = null if track_index < 0 else DAW.state.item(track_index, item_index)
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


## The loop range: a rod of light along the loop band between its ends, and a wall of the same
## light behind the channels, so the loop is seen through the whole arrangement and not only along
## its top edge. Moved, not rebuilt, and only when it changed.
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
		_loop_veil.visible = false
		return
	var left := maxf(_x_for(s.loop_start), _lane_area_x)
	var right := minf(_x_for(s.loop_end), _lane_right())
	_loop_bar.visible = right > left and not highway
	_loop_veil.visible = _loop_bar.visible
	if right <= left:
		return
	_loop_bar.scale = Vector3(right - left, 1, 1)
	_loop_bar.position = Vector3((left + right) * 0.5, _top_y - LOOP_BAND * 0.5, 0.004)
	_loop_bar.material_override = Materials.led(LOOP_COLOUR if s.looping else Color(0.34, 0.40, 0.52), s.looping)
	var top := _top_y - RULER_HEIGHT
	_loop_veil.scale = Vector3(right - left, maxf(top - _lanes_bottom, 0.001), 1)
	_loop_veil.position = Vector3((left + right) * 0.5, (top + _lanes_bottom) * 0.5, VEIL_Z)
	_loop_veil.material_override = _veil_looping if s.looping else _veil_idle


func _build_loop_bar() -> void:
	_loop_bar = MeshInstance3D.new()
	var rod := BoxMesh.new()
	# Unit length, scaled to the range, so moving the range is a transform and not a mesh.
	rod.size = Vector3(1.0, LOOP_BAND * 0.4, LOOP_BAND * 0.4)
	_loop_bar.mesh = rod
	_loop_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adopt(_loop_bar)
	_loop_veil = MeshInstance3D.new()
	_loop_veil.name = "LoopVeil"
	var wall := BoxMesh.new()
	wall.size = Vector3(1, 1, 0.0002)
	_loop_veil.mesh = wall
	_loop_veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _veil_looping == null:
		_veil_looping = TimelineFinish.glow(Color(LOOP_COLOUR.r, LOOP_COLOUR.g, LOOP_COLOUR.b, 0.30))
		_veil_idle = TimelineFinish.glow(Color(0.5, 0.55, 0.65, 0.07))
	_loop_veil.material_override = _veil_idle
	_loop_veil.visible = false
	_adopt(_loop_veil)
	_drawn_loop = Vector3(-1, -1, -1)
	_draw_loop()


func _place_scrubber(project: float) -> void:
	# Short of the lanes' right end by the resize grip, which has that corner.
	var room := _lane_area_width - TimelineResizeGrip.SIZE.x - 0.004
	_scrubber.width = room
	_scrubber.project_length = project
	_scrubber.view_start = view_start
	_scrubber.view_span = view_span
	_scrubber.position = Vector3(_lane_area_x + room * 0.5,
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


## Nothing: there is no panel (see the top of this file). The header's gutter, the screen's
## face and the chassis behind them went with it.
func _build_carcass() -> void:
	pass


## The cut stone each track's gem is: an octahedron, points up and down, flat facets for the
## light to catch. One mesh, every lane's gem an instance of it.
static var _gem: Mesh


static func _gem_mesh() -> Mesh:
	if _gem == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := Vector3(0, 0.5, 0)
		var bottom := Vector3(0, -0.5, 0)
		var ring := [Vector3(0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(-0.5, 0, 0), Vector3(0, 0, -0.5)]
		for k in 4:
			var a: Vector3 = ring[k]
			var b: Vector3 = ring[(k + 1) % 4]
			for tri in [[top, b, a], [bottom, a, b]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				for v in tri:
					st.set_normal(n)
					st.add_vertex(v)
		_gem = st.commit()
	return _gem


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
	var at_left := floorf(s.bar_at(view_start)) + 1.0
	var bar := s.bar_to_seconds(at_left + 1.0) - s.bar_to_seconds(at_left)
	var per_bar := bar / maxf(view_span, 0.0001) * _lane_area_width
	var step: int = LABEL_STEPS[-1]
	for candidate in LABEL_STEPS:
		if candidate * per_bar >= LABEL_CLEARANCE:
			step = candidate
			break
	var first := int(floor((at_left - 1.0) / step)) * step
	var last := int(ceil(s.bar_at(view_start + view_span)))

	# The grid down the lanes, behind the blocks: a line on every bar while bars are far enough
	# apart to tell from each other, brighter on the numbered ones, and the sections' lines over
	# them, so where the chorus starts reads straight down the arrangement.
	var grid_step: int = step
	for candidate in LABEL_STEPS:
		if candidate * per_bar >= 0.006:
			grid_step = mini(candidate, step)
			break
	var grid := MeshBank.strips()
	grid.name = "Grid"
	_ruler.add_child(grid)
	var grid_top := _top_y - RULER_HEIGHT
	var grid_height := grid_top - _lanes_bottom
	var gfirst := int(floor((at_left - 1.0) / grid_step)) * grid_step
	var lines: Array = []
	for n in range(gfirst, last + 1, grid_step):
		if n < 0 or n % step == 0:
			continue
		lines.append([_x_for(s.bar_to_seconds(n + 1.0)), GRID_BEAT, 0.0005])
	for n in range(first, last + 1, step):
		if n >= 0:
			lines.append([_x_for(s.bar_to_seconds(n + 1.0)), GRID_BAR, 0.0006])
	for at in DAW.state.markers:
		lines.append([_x_for(float(at)), MARKER_COLOUR.darkened(0.45), 0.0007])
	# One line per place, the later (a section's over a bar's) taking it.
	var at_x := {}
	for line in lines:
		at_x[roundi(float(line[0]) * 20000.0)] = line
	for line in at_x.values():
		var lx: float = line[0]
		if lx < _lane_area_x - 0.0001 or lx > _lane_right() or grid_height <= 0.0:
			continue
		grid.claim(Transform3D(Basis.from_scale(Vector3(line[2], grid_height, 0.0001)),
				Vector3(lx, (grid_top + _lanes_bottom) * 0.5, GRID_Z)), (line[1] as Color).srgb_to_linear())
	grid.commit()

	# Where the section names are written: no bar number under one.
	var named: Array = []
	for at in DAW.state.markers:
		var nx := _x_for(float(at))
		named.append(Vector2(nx - 0.003, nx + 0.006 + str(DAW.state.markers[at]).length() * 0.0072))
	for n in range(first, last + 1, step):
		if n < 0:
			continue
		var x := _x_for(s.bar_to_seconds(n + 1.0))
		if x < _lane_area_x - 0.0001 or x > _lane_right():
			continue
		var under := false
		for span in named:
			under = under or (x > span.x and x < span.y)
		# Stopping just short of the strip's lower edge, not on it: a tick's bottom face in the
		# strip's bottom face's plane flickers, once the timeline is scaled up to stand in a room.
		_ruler.add_child(_flat_box(Vector3(0.0006, NUMBERS_HEIGHT * 0.5 - 0.0006, 0.0008),
				Vector3(x, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.75 + 0.0003, 0.0014), RULER_TICK))

		if under:
			continue
		var label := _text(str(n + 1), 48, RULER_TEXT)
		label.position = Vector3(x + 0.0022, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.28, 0.0016)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_ruler.add_child(label)

	# Where the tempo changes, and to what, in the colour of the tempo keys.
	var points: Array = s.tempo_points
	for i in range(1, points.size()):
		var tx := _x_for(s.seconds_at_beat(float(points[i][0])))
		if tx < _lane_area_x - 0.0001 or tx > _lane_right():
			continue
		var ramped: bool = int(points[i - 1][2]) != DawKitTempoMap.HOLD
		var change := _text(("/%d" if ramped else "%d") % roundi(float(points[i][1])), 26, Color(0.9, 0.8, 0.4))
		change.position = Vector3(tx - 0.002, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.74, 0.0016)
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ruler.add_child(change)

	# Where the time signature changes, and to what, in the colour of the SIG key: by the bar
	# number, left of the bar line.
	var sigs: Array = s.time_signature_points
	for i in range(1, sigs.size()):
		var sx := _x_for(s.seconds_at_beat(float(sigs[i][0])))
		if sx < _lane_area_x - 0.0001 or sx > _lane_right():
			continue
		var sig := _text("%d/%d" % [int(sigs[i][1]), int(sigs[i][2])], 26, SIGNATURE_COLOUR)
		sig.position = Vector3(sx - 0.002, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.26, 0.0016)
		sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_ruler.add_child(sig)

	# Section markers sit on the ruler, where the arrangement is actually named.
	for at in DAW.state.markers:
		var mx := _x_for(float(at))
		if mx < _lane_area_x - 0.0001 or mx > _lane_right():
			continue
		# Not the bar tick's height: a marker is mostly on a bar line, and two ticks with the same
		# ends draw their ends in the same plane.
		_ruler.add_child(_flat_box(Vector3(0.0008, NUMBERS_HEIGHT * 0.58, 0.0008),
				Vector3(mx, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.69, 0.0015), MARKER_COLOUR))
		var flag := _text(str(DAW.state.markers[at]).to_upper(), 40, MARKER_COLOUR)
		flag.position = Vector3(mx + 0.0022, _top_y - LOOP_BAND - NUMBERS_HEIGHT * 0.74, 0.0016)
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
		chip_bank: MeshBank, thread_bank: MeshBank) -> void:
	var tint := t.shown_colour()
	var picked := t.index == picked_track
	# The channel: smoked glass a breath of the track's colour, clearer and lighter when picked.
	var bed := CHANNEL.lerp(tint, 0.30 if picked else 0.14)
	# Dark enough that a lamp in the room behind does not bloom through it.
	bed.a = 0.92 if picked else 0.86
	bed_bank.claim(Transform3D(Basis.from_scale(Vector3(_lane_area_width, lane_height, CHANNEL_DEPTH)),
			Vector3(_lane_area_x + _lane_area_width * 0.5, y, CHANNEL_Z)),
			Color(bed.r * bed.r, bed.g * bed.g, bed.b * bed.b, bed.a))
	# The thread of its colour along its foot, which carries the track's colour the length of the
	# song, so a clip far from its name is still followed back to it. Dark while muted.
	var thread := Materials.chip_colour(tint) * (1.0 if picked else 0.62)
	if t.mute:
		thread = Materials.lamp_colour(tint, false)
	thread_bank.claim(Transform3D(Basis.from_scale(Vector3(_lane_area_width, THREAD, THREAD)),
			Vector3(_lane_area_x + _lane_area_width * 0.5, y - lane_height * 0.5 + THREAD * 0.5, THREAD_Z)),
			Color(thread.r, thread.g, thread.b, 1.0))
	# The gem, where the name starts: chip_colour and not lamp_colour, for the reason in
	# Materials -- this is the track's identity, and a clipped identity is no identity.
	var gem := lane_height * (0.62 if picked else 0.5)
	var gem_x := -width * 0.5 + 0.007
	chip_bank.claim(Transform3D(Basis.from_scale(Vector3(gem * 0.78, gem, gem * 0.78)),
			Vector3(gem_x, y, 0.004)),
			Materials.chip_colour(tint) * (0.22 if t.mute else 1.0))
	# Soloed, armed: a ring round the gem, gold or red -- marks, not letters.
	var rings: Array = []
	if t.solo:
		rings.append(Color(1.0, 0.82, 0.35))
	if t.rec_arm:
		rings.append(Color(1.0, 0.25, 0.22))
	for k in rings.size():
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var r := lane_height * (0.40 + k * 0.10)
		torus.inner_radius = r - 0.0007
		torus.outer_radius = r
		torus.rings = 28
		torus.ring_segments = 6
		ring.mesh = torus
		ring.rotation = Vector3(PI * 0.5, 0, 0)
		ring.position = Vector3(gem_x, y, 0.004 + k * 0.0003)
		ring.material_override = Materials.led(rings[k], true)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_adopt(ring)

	# The name, light in the air beside its gem, outlined so it holds against whatever is behind.
	var name_label := _text(t.display_name(), 44,
			Color(1.0, 0.88, 0.60) if picked else (Color(0.60, 0.62, 0.68) if t.mute else Color(0.95, 0.96, 0.98)))
	name_label.position = Vector3(-width * 0.5 + 0.0145, y, 0.0042)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Lettering.fit(name_label, NAME_SPAN, 44 * 4, 24 * 4)
	_adopt(name_label)


## The shown lane's row: a bed the width of the lanes, and the lane's name where the track names are.
func _build_automation_row(y: float) -> void:
	var bed := MeshInstance3D.new()
	bed.name = "AutomationRow"
	var box := BoxMesh.new()
	box.size = Vector3(_lane_area_width, AUTOMATION_ROW, CHANNEL_DEPTH)
	bed.mesh = box
	var glass := CHANNEL.lerp(AUTOMATION_COLOUR, 0.10)
	bed.material_override = _smoke(Color(glass.r, glass.g, glass.b, 0.7))
	bed.position = Vector3(_lane_area_x + _lane_area_width * 0.5, y, CHANNEL_Z)
	_adopt(bed)
	var label := _text(("MASTER  " if picked_track == 0 else "") + lane_name(shown_lane), 26, AUTOMATION_COLOUR)
	label.position = Vector3(-width * 0.5 + 0.012, y, 0.0016)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Lettering.fit(label, NAME_SPAN, 26 * 4, 18 * 4)
	_adopt(label)


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
	var fade_slot := 0
	var gain_label := 0
	var name_label := 0
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
			var y: float = _lane_y[i]
			if not _preview.is_empty() and _preview[0] == indices[i] and _preview[1] == item.index:
				# Drawn on the lane it is being dragged over, until it is let go there.
				var row := indices.find(_preview[4]) if _preview.size() > 4 else -1
				if row >= 0 and row < _lane_y.size():
					y = _lane_y[row]
				start = _preview[2]
				if _preview[3] >= 0.0:
					length = _preview[3]
				else:
					content = start
			if _place_item(item, start, t.shown_colour(), y, t.mute, slot, length):
				slot += 1
				note_slot = _place_notes(item, content, t.shown_colour(), y, item.muted or t.mute,
						note_slot)
				wave_slot = _place_wave(item, content, t.shown_colour(), y, item.muted or t.mute,
						wave_slot)
				# Fades and gain belong to the block: they move with it and follow a trim.
				fade_slot = _place_fades(item, start, length, t.shown_colour(), y, fade_slot)
				gain_label = _place_gain(item, start, length, y, gain_label)
				name_label = _place_name(item, start, length, y, name_label, t.display_name(), item.muted or t.mute)
	# Items off the end of the window keep whatever they last held and are simply not drawn.
	_item_blocks.show_first(slot)
	_item_strips.show_first(slot)
	_item_shades.show_first(slot * 2)
	_item_notes.show_first(note_slot)
	_item_waves.show_first(wave_slot)
	_item_fades.show_first(fade_slot)
	for k in range(gain_label, _gain_labels.get_child_count()):
		(_gain_labels.get_child(k) as Label3D).visible = false
	for k in range(name_label, _item_labels.get_child_count()):
		(_item_labels.get_child(k) as Label3D).visible = false
	_draw_loop()
	_draw_automation()


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
	var block_height := lane_height - 0.0024
	# Tinted with the track's colour, held to a middling value so what stands out of its face
	# (its sound, its notes) is the bright thing on it; lifted toward white when selected.
	var body := item_body(tint, dim, item.selected).srgb_to_linear()
	var back := _back(item)
	var depth := _depth()
	var face := back + depth
	var mid := left + span * 0.5
	# The bank holds unit cubes, so the size of an item IS its instance scale.
	_item_blocks.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(span, block_height, depth)),
			Vector3(mid, y, back + depth * 0.5)))
	_item_blocks.set_colour(slot, body)
	# Its shadow on the channel behind it, down and to the right, further for one pulled out;
	# and a line of light along its top edge, where glass catches it.
	var off := 0.0012 + (0.0012 if _pulled(item) else 0.0)
	_item_shades.move_slot(slot * 2, Transform3D(
			Basis.IDENTITY.scaled(Vector3(span, block_height, 0.0001)),
			Vector3(mid + off, y - off, HALO_Z)))
	_item_shades.set_colour(slot * 2, Color(0, 0, 0, 0.6))
	_item_shades.move_slot(slot * 2 + 1, Transform3D(
			Basis.IDENTITY.scaled(Vector3(maxf(span - 0.0016, 0.0002), 0.0003, depth * 0.6)),
			Vector3(mid, y + block_height * 0.5 + 0.0004, back + depth * 0.5)))
	_item_shades.set_colour(slot * 2 + 1, Color(1, 1, 1, 0.12 if dim else 0.45))

	# A thread of its track's colour along its foot, out on its face: which track it is on, read
	# at the clip and not only at the name.
	_item_strips.move_slot(slot, Transform3D(
			Basis.IDENTITY.scaled(Vector3(maxf(span - 0.0012, 0.0002), 0.0009, 0.0005)),
			Vector3(mid, y - block_height * 0.5 + 0.0011, face + 0.00035)))
	_item_strips.set_colour(slot, Materials.chip_colour(tint) * 1.2 if not dim
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
	var block_height := lane_height - 0.0024
	# Below the take strip (3mm down from the block's top) and clear of the block's bottom edge.
	# Wholly below it, not reaching into it: a top note clamped to the block's left or right edge
	# had its end in the strip's end's plane, which flickers once the timeline is scaled up.
	var top := y + block_height * 0.5 - 0.0018
	var bottom := y - block_height * 0.5 + 0.0020
	var row := (top - bottom) / rows
	var left_edge := maxf(_x_for(start) + EDGE_GAP, _lane_area_x) + INSET
	var right_edge := minf(_x_for(start + item.length) - EDGE_GAP, _lane_right()) - INSET
	# Light standing out of the clip, as a skyline of bricks: each note sunk into the face and
	# standing out of it as far as it was played hard.
	var colour := Materials.chip_colour(tint.lightened(0.55)).srgb_to_linear()
	if dim:
		colour = tint.darkened(0.5).srgb_to_linear()
	var face := _back(item) + _depth()
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
		var hard := clampf(item.notes[n - MidiTake.NOTE_WIDTH + 3] / 127.0, 0.0, 1.0)
		var out := NOTE_RISE * (0.35 + 0.65 * hard)
		_item_notes.move_slot(slot, Transform3D(
				Basis.IDENTITY.scaled(Vector3(right - left, maxf(row * 0.8, MIN_NOTE_HEIGHT), out + SUNK)),
				Vector3((left + right) * 0.5, centre_y, face + (out - SUNK) * 0.5)))
		_item_notes.set_colour(slot, colour)
		slot += 1
	return slot


## An item's fades, drawn as an arranger draws them: a line from silence in the block's bottom
## corner to full level at the top, where the fade ends, over each faded end. Clipped to the
## window. Returns the next free slot.
func _place_fades(item: MixState.ItemState, start: float, length: float, tint: Color, y: float,
		slot: int) -> int:
	var block_height := lane_height - 0.0024
	var low := y - block_height * 0.5 + 0.0006
	var high := y + block_height * 0.5 - 0.0006
	var left := _x_for(start) + EDGE_GAP
	var right := _x_for(start + length) - EDGE_GAP
	var fade_in := minf(item.fade_in, length)
	var fade_out := minf(item.fade_out, length)
	if not _fade_preview.is_empty() and _fade_preview[1] == item.index and DAW.state.item(_fade_preview[0], _fade_preview[1]) == item:
		fade_in = minf(float(_fade_preview[2]), length)
		fade_out = minf(float(_fade_preview[3]), length)
	var lines: Array = []
	if fade_in > 0.0:
		lines.append([Vector2(left, low), Vector2(minf(_x_for(start + fade_in), right), high)])
	if fade_out > 0.0:
		lines.append([Vector2(maxf(_x_for(start + length - fade_out), left), high), Vector2(right, low)])
	var colour := Color(1.6, 1.6, 1.7)
	var z := _back(item) + _depth() + NOTE_RISE + 0.0006
	for line in lines:
		if slot >= _item_fades.count():
			break
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		# Clipped to the lane area, along the line.
		var x0 := maxf(a.x, _lane_area_x)
		var x1 := minf(b.x, _lane_right())
		if x1 - x0 <= 0.0002 or b.x - a.x <= 0.0:
			continue
		var p0 := a.lerp(b, (x0 - a.x) / (b.x - a.x))
		var p1 := a.lerp(b, (x1 - a.x) / (b.x - a.x))
		var along := p1 - p0
		_item_fades.move_slot(slot, Transform3D(
				Basis(Vector3.BACK, along.angle()) * Basis.from_scale(Vector3(along.length(), 0.0007, 0.0005)),
				Vector3((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, z)))
		_item_fades.set_colour(slot, colour)
		slot += 1
	return slot


## An item's gain written in its top right corner, under the strip and clear of its fades, when
## it is not 0 dB and there is room between them. Returns the next free label.
func _place_gain(item: MixState.ItemState, start: float, length: float, y: float, used: int) -> int:
	if absf(item.gain_db) < 0.05:
		return used
	# Clear of the fade out's line, which comes down to the same corner.
	var right := minf(_x_for(start + length - minf(item.fade_out, length)) - EDGE_GAP, _lane_right())
	var left := maxf(_x_for(start + minf(item.fade_in, length)) + EDGE_GAP, _lane_area_x)
	if right - left < 0.03:
		return used
	var l: Label3D
	if used < _gain_labels.get_child_count():
		l = _gain_labels.get_child(used)
	else:
		l = _text("", 20, Color(0.92, 0.93, 0.95))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_gain_labels.add_child(l)
	l.text = "%+.1f dB" % item.gain_db
	l.position = Vector3(right - 0.0012, y + (lane_height - 0.0024) * 0.5 - 0.0046, _label_z(item))
	l.visible = true
	return used + 1


## An item's name in its top left corner, under the strip, cut to fit the block -- and left off
## a block too short to hold a few letters of it. Returns the next free label.
const ITEM_NAME_SIZE := 38
const MIN_NAMED_WIDTH := 0.014


func _place_name(item: MixState.ItemState, start: float, length: float, y: float, used: int,
		track_name := "", dim := false) -> int:
	var shown := shown_item_name(item.name, track_name)
	if shown.is_empty():
		return used
	var left := maxf(_x_for(start) + EDGE_GAP, _lane_area_x)
	var right := minf(_x_for(start + length) - EDGE_GAP, _lane_right())
	if absf(item.gain_db) >= 0.05:
		right -= 0.03
	var room := right - left - 0.003
	if room < MIN_NAMED_WIDTH:
		return used
	var l: Label3D
	if used < _item_labels.get_child_count():
		l = _item_labels.get_child(used)
	else:
		l = _text("", ITEM_NAME_SIZE, ITEM_NAME_COLOUR)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_item_labels.add_child(l)
	# Light in front of the clip, outlined dark: it floats over the relief standing out of the
	# clip's face, and has to read over the bright parts of it and the dark alike.
	l.modulate = Color(0.75, 0.76, 0.80) if dim else ITEM_NAME_LIGHT
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.text = fit_text(shown, room / l.pixel_size, l.font_size)
	l.position = Vector3(left + 0.0016, y + (lane_height - 0.0024) * 0.5 - 0.0050, _label_z(item))
	l.visible = not l.text.is_empty()
	return used + 1


## An item's name as its block shows it: without its track's name in front, which the lane's
## header already says -- "Kick Verse 1" on the Kick lane is "Verse 1".
static func shown_item_name(item_name: String, track_name: String) -> String:
	if track_name != "" and item_name.length() > track_name.length() \
			and item_name.to_lower().begins_with(track_name.to_lower() + " "):
		return item_name.substr(track_name.length() + 1).strip_edges()
	return item_name


## `text` cut with an ellipsis to fit `room` pixels at `size`, or "" when not even a letter does.
static func fit_text(text: String, room: float, size: int) -> String:
	var font := ThemeDB.fallback_font
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
		return text
	var n := text.length() - 1
	while n > 0:
		var cut := text.left(n).strip_edges() + "…"
		if font.get_string_size(cut, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= room:
			return cut
		n -= 1
	return ""


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
			_x_for(start) + EDGE_GAP + INSET, _x_for(start + item.length) - EDGE_GAP - INSET,
			_lane_area_x + INSET, _lane_right() - INSET, WAVE_COLUMN)
	var block_height := lane_height - 0.0024
	var top := y + block_height * 0.5 - 0.0012
	var bottom := y - block_height * 0.5 + 0.0020
	var middle := (top + bottom) * 0.5
	# Light standing out of the clip as a relief: as tall as it is loud, and standing out of the
	# face as far, so a loud passage is a ridge and a quiet one barely breaks the glass.
	var colour := Materials.chip_colour(tint.lightened(0.5)).srgb_to_linear()
	if dim:
		colour = tint.darkened(0.5).srgb_to_linear()
	var face := _back(item) + _depth()
	for c in columns:
		if slot >= _item_waves.count():
			break
		# As it is heard: through the item's gain and fades, so a fade is seen in the take.
		var heard: float = minf(c[1] * db_to_linear(item.level_db(item.start + _seconds_at_x(c[0]) - start)), 1.0)
		# On a square-root scale: a voice peaking at -12dB fills half the block, not a quarter,
		# so a take recorded at a sensible level is a shape and not a hairline.
		var height := maxf(sqrt(heard) * (top - bottom), MIN_NOTE_HEIGHT * 0.5)
		var out := NOTE_RISE * (0.15 + 0.85 * sqrt(heard))
		_item_waves.move_slot(slot, Transform3D(
				Basis.IDENTITY.scaled(Vector3(WAVE_COLUMN * 0.7, height, out + SUNK)),
				Vector3(c[0], middle, face + (out - SUNK) * 0.5)))
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
	var tall := _height - RULER_HEIGHT * 0.4
	var mid := -(RULER_HEIGHT * 0.2)
	var deep := _back(null) + BLOCK_DEPTH + PULL + NOTE_RISE + 0.004

	# The blade: a sheet of light through the whole depth of the arrangement, edge on to the
	# song, so it cuts through every clip it crosses -- a line seen straight on, a plane of light
	# seen from a seat off to the side.
	var line := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.0016, tall, deep)
	line.mesh = mesh
	line.position = Vector3(0, mid, deep * 0.5)
	line.material_override = Materials.led(PLAYHEAD_COLOUR, true)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_playhead.add_child(line)

	# Its glow either side, in front of everything, so it is found across a room as a lit seam.
	var halo := MeshInstance3D.new()
	var halo_mesh := BoxMesh.new()
	halo_mesh.size = Vector3(0.012, tall, 0.0001)
	halo.mesh = halo_mesh
	halo.position = Vector3(0, mid, deep + 0.0004)
	halo.material_override = _halo_finish()
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_playhead.add_child(halo)

	# The bead it hangs from, riding the ruler.
	var head := MeshInstance3D.new()
	var bead := SphereMesh.new()
	bead.radius = 0.0045
	bead.height = 0.009
	bead.radial_segments = 18
	bead.rings = 9
	head.mesh = bead
	head.position = Vector3(0, _top_y - LOOP_BAND - 0.0040, 0.006)
	head.material_override = Materials.led(PLAYHEAD_COLOUR, true)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_playhead.visible = x >= _lane_area_x and x <= _lane_right() and not highway
	_playhead.position.x = x
	# What the blade is passing through is lit by it (see TimelineFinish.ingot).
	if is_inside_tree():
		var axis := global_basis.x
		TimelineFinish.light_beam(to_global(Vector3(x, 0, 0)) if _playhead.visible else Vector3(0, -1000, 0),
				axis.normalized(), BEAM_REACH * axis.length())


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


## The song's seconds at a panel x, the inverse of _x_for.
func _seconds_at_x(x: float) -> float:
	return view_start + (x - _lane_area_x) / maxf(_lane_area_width, 0.0001) * view_span


func _lane_right() -> float:
	return _lane_area_x + _lane_area_width


## The lanes, or the road. Nothing is rebuilt: the lanes keep their shape under it, and the road is
## laid over the same area.
func set_highway(on: bool) -> void:
	if on == highway:
		return
	highway = on
	_light_view_keys()
	_sync_highway()


## Show whichever of the two is chosen, and let only that one take a press.
func _sync_highway() -> void:
	if _highway == null:
		return
	for child in get_children():
		if child.get_meta("built", false) and child is Node3D:
			(child as Node3D).visible = not highway
	for node in [_lane_slot, _lane_thumb, _automation]:
		if node != null:
			(node as Node3D).visible = not highway and (node != _lane_slot and node != _lane_thumb
					or DAW.state.track_indices().size() > MAX_LANES)
	for control in [_lanes, _header, _seek_strip, _loop_strip]:
		if control != null:
			(control as ControlAffordance).collision_layer = 0 if highway else 2
	_highway.visible = highway
	# Shown above with everything built, the loop's rod and wall included: they show only what
	# the loop range says, whatever was shown with them.
	_drawn_loop = Vector3(-1, -1, -1)
	_draw_loop()
	if highway and not _lane_y.is_empty():
		_highway.configure(_lane_area_x, _lane_area_width, -_top_y + SCRUBBER_BAND + 0.002,
				_top_y - 0.002, _shown())


## Flat lanes or shelves of blocks. Each person's own view; rebuilt, since the blocks are a
## different bank.
func set_shelf(on: bool) -> void:
	if on == shelf:
		return
	shelf = on
	_light_view_keys()
	mark_dirty()


## Where a clip's back is: just in front of its channel, and pulled further out while it is
## selected or in the hand -- taken out of its row, as a thing is that has been picked up.
func _back(item: MixState.ItemState) -> float:
	return ITEM_Z + (PULL if item != null and _pulled(item) else 0.0)


## How deep a clip's ingot is: deeper on the shelves, where it is a block to take hold of.
func _depth() -> float:
	return BLOCK_DEPTH if shelf else ITEM_DEPTH


## In front of everything standing out of a clip's face: where words about it float.
func _label_z(item: MixState.ItemState) -> float:
	return _back(item) + _depth() + NOTE_RISE + 0.0012


## Out of its shelf: selected, or in the hand.
func _pulled(item: MixState.ItemState) -> bool:
	return item.selected or (item == _held_item and _held_item != null)


static func _halo_finish() -> StandardMaterial3D:
	return TimelineFinish.glow(Color(1.0, 0.85, 0.45, 0.16))


## The shelf boards: smoked glass, lit along their front edge as the deck's ledges are.
static func _board_finish() -> StandardMaterial3D:
	return GlyphKey.puck_finish()


## The board under each lane that its blocks stand on. Nothing in the flat view.
func _build_shelf_lips() -> void:
	_shelf_lips = null
	if not shelf or _lane_y.is_empty():
		return
	_shelf_lips = MeshBank.boxes(_board_finish())
	_shelf_lips.name = "ShelfLips"
	_adopt(_shelf_lips)
	var tall := LANE_GAP + 0.0012
	for y in _lane_y:
		# Its top where the block's bottom is.
		var top := y - lane_height * 0.5 + 0.0012
		# A millimetre short of the lane's channel at each end, whose ends would be its ends' plane.
		_shelf_lips.claim(Transform3D(Basis.from_scale(Vector3(_lane_area_width - 0.002, tall, SHELF_LIP)),
				Vector3(_lane_area_x + _lane_area_width * 0.5, top - tall * 0.5, ITEM_Z - 0.0003 + SHELF_LIP * 0.5)),
				Color.WHITE)
	_shelf_lips.commit()


## Its colours, sRGB. Self-lit, as TimelineFinish says why.
## The channels' smoked glass, before a track's colour is breathed into it.
const CHANNEL := Color(0.030, 0.034, 0.046)
## Kept for what tests compare clips against: the darkest a channel reads.
const LANE_BED := Color(0.105, 0.113, 0.136)
const GRID_BEAT := Color(0.13, 0.15, 0.19)
const GRID_BAR := Color(0.30, 0.34, 0.42)
const RULER_TEXT := Color(0.90, 0.92, 0.96)
const RULER_TICK := Color(0.55, 0.60, 0.70)
const MARKER_COLOUR := Color(1.0, 0.80, 0.42)
const PLAYHEAD_COLOUR := Color(1.0, 0.92, 0.62)
## How far either side of the playhead a clip it is cutting through is lit by it.
const BEAM_REACH := 0.010
const ITEM_NAME_COLOUR := Color(0.97, 0.97, 0.98)
const ITEM_NAME_LIGHT := Color(0.96, 0.97, 0.99)
## How deep the layers stand, front to back, in metres out of the timeline's plane.
const VEIL_Z := 0.0002
const CHANNEL_Z := 0.0008
const CHANNEL_DEPTH := 0.0008
const GRID_Z := 0.00135
const THREAD := 0.0009
const THREAD_Z := 0.0017
const HALO_Z := 0.00225
const ITEM_Z := 0.0026
const ITEM_DEPTH := 0.006
## How far out of a clip's face its loudest sound and hardest note stand, and how far into it
## they are sunk so they grow out of it rather than sit on it.
const NOTE_RISE := 0.0048
const SUNK := 0.0004
## Between a clip's ends and what is drawn on its face.
const INSET := 0.0004
static var _flats := {}


## An unlit material in one colour, shared by everything on the screen drawn in it.
static func flat(colour: Color) -> StandardMaterial3D:
	if not _flats.has(colour):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = colour
		_flats[colour] = m
	return _flats[colour]


## A box drawn in one flat colour.
func _flat_box(size: Vector3, at: Vector3, colour: Color) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	box.material_override = flat(colour)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return box


## An item block's body: the track's colour, held to a value white type reads on, darker for a
## muted item and lifted toward white for a selected one -- the way every arranger draws them.
static func item_body(tint: Color, dim: bool, selected: bool) -> Color:
	var body := Color.from_hsv(tint.h, clampf(tint.s * 1.05, 0.50, 0.86), clampf(tint.v * 0.88, 0.58, 0.80))
	if dim:
		body = Color.from_hsv(tint.h, tint.s * 0.30, 0.26)
	if selected:
		body = body.lerp(Color(1.0, 1.0, 1.0), 0.45)
	return body


func _text(content: String, size: int, tint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = content
	l.font_size = size * 4
	# Was 0.000055, scaled up with LANE_HEIGHT's own increase (2026-10-11: too small to read).
	l.pixel_size = 0.000078
	l.modulate = tint
	# Outlined dark: there is no panel behind it, only the room.
	l.outline_size = maxi(8, size / 3)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Lettering.range_to_legibility(l)
	return l


static var _smokes := {}


## Smoked glass in one colour, for a loose piece (the automation row's channel).
static func _smoke(colour: Color) -> StandardMaterial3D:
	if not _smokes.has(colour):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = colour
		_smokes[colour] = m
	return _smokes[colour]
