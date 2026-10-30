class_name ClipEditorSurface
extends Surface

## One clip, large: the place to trim a take to its hit, which the arrangement is the wrong size
## for (2026-10-30: "I'm trying to trim to transients and such. Maybe a dedicated clip editor").
##
## On the timeline a clip is a block a few centimetres long and a lane tall, its sound fifty
## loudnesses a second, and a millimetre of the hand is a sixteenth of a bar: a trim can be pulled
## onto an attack (TimelineLanes.magnet) but never placed between two. Here the clip has the whole
## panel. Its sound is drawn from the file itself (ClipWave), every sample once zoomed far enough,
## with what lies beyond its edges drawn faintly either side so a trim outward shows what it will
## uncover. Over it: a ruler in milliseconds from the clip's start and in bars and beats, the
## take's attacks as amber ticks (DAW.item_transients), the grid it snaps to, and the playhead.
##
## Five things to take hold of, on one control over the sound (Face): the START and END edges,
## which trim; the corners at the top, which are the fades; and the GAIN line across the clip,
## dragged up or down. A drag is magnetic exactly as the timeline's is -- onto an attack, else a
## grid line, when it comes within TimelineLanes.MAGNET of one on this panel, zoomed as it is now,
## so zoomed in to a few milliseconds the hand goes anywhere between them -- unless the panel is
## on FREE, or the hand is fine (Shift). ZERO X puts a trimmed edge on the nearest zero crossing
## of the sound, after any pull, so a cut with no fade does not click. Press bare sound to put the
## playhead there; drag it to scroll; the wheel zooms round the pointer, fine scrolls.
##
## The keys under it work on the selected handle (whichever was last taken hold of, or chosen
## with START / END / FADE IN / FADE OUT): ten milliseconds or one either way, or to the next
## attack or the one before. And they audition: PLAY from the start edge, TO END the last second
## up to the end edge and stop there, LOOP the clip.
##
## Every edit is a DAW verb the timeline already uses -- trim_item, set_item_fades,
## set_item_gain -- made once when a drag lets go or a key is pressed: one undo step, sent to a
## session's guests (or asked of the host by one), refused for a locked item as the desk refuses
## it. Nothing here keeps a copy of the clip; it reads DAW.state and draws a preview of the drag
## until the edit lands.
##
## One editor, opened on a clip by a double click on the timeline or the item page's EDIT CLIP
## key (TimelineSurface.edit_asked), retargeted by opening another, closed by its CLOSE key.
## Closed, it is not there at all: nothing drawn, nothing to hit (process_mode DISABLED takes
## its controls out of the physics world). A MIDI clip has no sound to draw: its notes are drawn
## and its edges trim them; fades and gain are an audio clip's.
##
## All its lettering lies on its own face, never in the air (the hover card too, HoverCard).

signal opened(track: int, index: int)
signal closed()

## The board, in metres, before the studio scales it. Its face is z = 0, its centre the origin.
## Wide and short, to fit where it hangs: under the timeline's lanes, right of its deck.
const WIDE := 0.84
const TOP := 0.20
const BOTTOM := -0.22
const MARGIN := 0.016
## The sound, on the left; the readouts in a column to its right.
const WAVE_LEFT := -WIDE * 0.5 + MARGIN
const WAVE_RIGHT := 0.20
const WAVE_WIDE := WAVE_RIGHT - WAVE_LEFT
const READ_LEFT := WAVE_RIGHT + 0.022
const READ_RIGHT := WIDE * 0.5 - MARGIN
## The rows, top down: the title, the ruler, the sound, a band left bare for the hover card, two
## rows of keys, and a band under them for their cards.
const TITLE_Y := TOP - 0.019
const RULER_TOP := TOP - 0.036
const RULER_BOTTOM := TOP - 0.072
const BEATS_Y := RULER_TOP - 0.009
const MS_Y := RULER_BOTTOM + 0.009
const WAVE_TOP := RULER_BOTTOM - 0.004
const WAVE_BOTTOM := -0.05
const WAVE_MID := (WAVE_TOP + WAVE_BOTTOM) * 0.5
const WAVE_HALF := (WAVE_TOP - WAVE_BOTTOM) * 0.5
const KEYS_Y := [WAVE_BOTTOM - 0.066, WAVE_BOTTOM - 0.108]
const KEY_SIZE := Vector2(0.052, 0.036)
const KEY_GAP := 0.005
const GROUP_GAP := 0.016

## Columns the sound is drawn in across the panel.
const COLUMNS := 480
## Fewer frames than this a column, and the sound is a line through its samples, not columns.
const LINE_BELOW := 1.5
## How tall the loudest moment of the file is drawn, of the half height: the take is drawn at its
## own scale, so a quiet one is still a shape, and its gain shows as that shape growing.
const DRAWN_PEAK := 0.9
## The narrowest and widest the view goes: a few milliseconds across, and a few minutes.
const MIN_SPAN := 0.004
const MAX_SPAN := 600.0
## A wheel notch's zoom, and a fine notch's scroll (of the view).
const ZOOM_STEP := 0.8
const SCROLL_STEP := 0.1
## How much of the view either side of the clip a fit leaves.
const FIT_MARGIN := 0.12

## The handles. NONE is bare sound.
enum { NONE, START, END, FADE_IN, FADE_OUT, GAIN }
const HANDLE_NAMES := {NONE: "", START: "START", END: "END", FADE_IN: "FADE IN", FADE_OUT: "FADE OUT", GAIN: "GAIN"}
## How near an edge, a fade's corner or the gain line a press must be to take it (m).
const EDGE_GRIP := 0.006
const FADE_GRIP := 0.010
const GAIN_GRIP := 0.007
## The gain line's height: from GAIN_LOW at the middle of the sound to GAIN_HIGH at its top, as the
## item page's rail spans it (TimelineItemPage), and how far a drag of the full half height moves it.
const GAIN_LOW := TimelineItemPage.GAIN_LOW
const GAIN_HIGH := TimelineItemPage.GAIN_HIGH
## A gain drag lands on whole tenths of a decibel, and on 0 dB within this of it, unless free.
const GAIN_DETENT := 0.5
## The nudges, in seconds.
const NUDGE_SMALL := 0.001
const NUDGE_LARGE := 0.010
## TO END plays this long up to the end edge.
const TAIL_SECONDS := 1.0
## How far a ZERO X edge may move to find a crossing (s).
const ZERO_REACH := 0.005
## A click this close to the playhead line in time (m of panel) still counts as on it.
const CLICK_SLOP := 0.0025

const PIXEL := 0.0001
const BOARD := Color(0.055, 0.06, 0.072)
const BED := Color(0.03, 0.034, 0.044)
const INK := Color(0.94, 0.95, 0.97)
const DIM := Color(0.62, 0.66, 0.72)
const AMBER := Color(1.0, 0.66, 0.22)
const EDGE_INK := Color(0.98, 0.94, 0.82)
const HELD_INK := Color(1.0, 0.80, 0.30)
const FADE_INK := Color(0.55, 0.85, 1.0)
const GAIN_INK := Color(0.70, 1.0, 0.62)
const GRID_INK := Color(0.17, 0.19, 0.24)
const BAR_INK := Color(0.32, 0.36, 0.44)
const BEYOND := Color(0.30, 0.32, 0.36)
const PLAYHEAD_INK := Color(1.0, 0.92, 0.62)

## [track, item] open, or [] while closed.
var target: Array = []
## The window onto the song, in seconds.
var view_start := 0.0
var view_span := 1.0
## Pulled onto attacks and the grid (SNAP), or left wherever the hand lets go (FREE).
var snapping := true
## Trimmed edges put on the nearest zero crossing of the sound.
var zero_crossings := false
## The handle the nudge keys move.
var selected := START
## Where in the editor's local frame the arm it hangs from meets its stand, or INF for none: the
## studio says, since it is the studio that stands it on the timeline's stand.
var arm_to := Vector3.INF
## A drag's values, drawn instead of the item's until it lets go: {start, end, fade_in, fade_out,
## gain}; empty when nothing is held.
var preview: Dictionary = {}
## What the last pull put the dragged value on: "attack", "grid", "zero crossing", "" (free).
var pulled_onto := ""
## The handle under the pointer, for its highlight.
var hovered_handle := NONE

var _wide := false
var _face: Face
var _keys: Dictionary = {}
var _mesh: MeshInstance3D
var _playhead: MeshInstance3D
var _title: Label3D
var _status: Label3D
var _captions: Array[Label3D] = []
var _values: Array[Label3D] = []
var _message: Label3D
var _beat_labels: Array[Label3D] = []
var _ms_labels: Array[Label3D] = []
var _stale := true
var _attacks := PackedFloat32Array()
var _attacks_asked := 0
## TO END's stop: the song time it stops at, and the time it started from; NAN for none.
var _stop_at := NAN
var _stop_from := 0.0
const LABELS := 9


func _ready() -> void:
	surface_kind = &"clip_editor"
	if surface_id == &"":
		surface_id = &"clip_editor"
	# On a monitor, if it is put on the glass, low in the frame and short, so the timeline it works
	# with stays in view above it.
	screen_top = 0.52
	screen_band = 0.42
	parks = false
	super()
	DAW.timeline_changed.connect(_on_timeline_changed)
	DAW.transport_changed.connect(func() -> void: _light_keys())
	DAW.tracks_renumbered.connect(_on_tracks_renumbered)
	DAW.project_replaced.connect(close)
	_shut()


func set_wide(wide: bool) -> void:
	if _wide != wide:
		_wide = wide
		mark_dirty()


# --- opening and closing ---------------------------------------------------------------------

func is_open() -> bool:
	return not target.is_empty()


## Open on track `track`'s item `index`, or retarget to it: the view fitted to the clip, its start
## edge selected. A clip that is not there leaves the editor as it was.
func open(track: int, index: int) -> void:
	if DAW.state == null or DAW.state.item(track, index) == null:
		return
	var again := is_open()
	target = [track, index]
	preview = {}
	pulled_onto = ""
	_attacks = PackedFloat32Array()
	_attacks_asked = 0
	_stop_at = NAN
	if is_midi() and selected in [FADE_IN, FADE_OUT]:
		selected = START
	fit()
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if not again:
		_clear_built()
		_rebuild()
		rebuilt.emit()
	_stale = true
	_redraw()
	opened.emit(track, index)


func close() -> void:
	if not is_open():
		return
	target = []
	preview = {}
	_stop_at = NAN
	_shut()
	closed.emit()


## Nothing drawn and nothing to hit: hidden, its controls freed and the rest out of the physics
## world, so no ray stops on an editor that is not there.
func _shut() -> void:
	_clear_built()
	_face = null
	_mesh = null
	_playhead = null
	_keys.clear()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


func item() -> MixState.ItemState:
	if target.is_empty() or DAW.state == null:
		return null
	return DAW.state.item(target[0], target[1])


func is_midi() -> bool:
	var it := item()
	return it != null and it.source.is_empty() and not it.notes.is_empty()


func _on_timeline_changed() -> void:
	if not is_open():
		return
	if item() == null:
		close()
		return
	_stale = true


func _on_tracks_renumbered(map: Dictionary) -> void:
	if not is_open():
		return
	var now := int(map.get(target[0], 0))
	if now <= 0:
		close()
	else:
		target = [now, target[1]]
		_stale = true


# --- the view --------------------------------------------------------------------------------

## The view round the clip, a little either side.
func fit() -> void:
	var it := item()
	if it == null:
		return
	var span := clampf(it.length * (1.0 + 2.0 * FIT_MARGIN), MIN_SPAN, MAX_SPAN)
	set_view(it.start - (span - it.length) * 0.5, span)


func set_view(start: float, span: float) -> void:
	view_span = clampf(span, MIN_SPAN, MAX_SPAN)
	view_start = maxf(start, -view_span * 0.5)
	_stale = true


## Zoomed by `factor` (under 1 is in), keeping `around` (song seconds) where it is on the panel.
func zoom(factor: float, around := NAN) -> void:
	if is_nan(around):
		around = view_start + view_span * 0.5
	var at := (around - view_start) / view_span
	var span := clampf(view_span * factor, MIN_SPAN, MAX_SPAN)
	set_view(around - at * span, span)


## Scrolled by `fraction` of the view (negative is earlier).
func scroll(fraction: float) -> void:
	set_view(view_start + fraction * view_span, view_span)


func seconds_per_metre() -> float:
	return view_span / WAVE_WIDE


func x_for(seconds: float) -> float:
	return WAVE_LEFT + (seconds - view_start) / view_span * WAVE_WIDE


func seconds_at_x(x: float) -> float:
	return view_start + (x - WAVE_LEFT) / WAVE_WIDE * view_span


## The point on the panel's face (global) over song time `seconds`, `up` of the way from the
## middle of the sound to its top (negative toward the bottom): for a hand, or a test.
func point_for(seconds: float, up := 0.0) -> Vector3:
	return to_global(Vector3(x_for(seconds), WAVE_MID + up * WAVE_HALF, 0.002))


# --- the clip as drawn: the item, or the drag's preview of it --------------------------------

func shown(field: String) -> float:
	if preview.has(field):
		return float(preview[field])
	var it := item()
	if it == null:
		return 0.0
	match field:
		"start": return it.start
		"end": return it.end()
		"fade_in": return it.fade_in
		"fade_out": return it.fade_out
		"gain": return it.gain_db
	return 0.0


## A handle's place in song time (the gain's: the middle of the clip).
func handle_time(handle: int) -> float:
	match handle:
		START: return shown("start")
		END: return shown("end")
		FADE_IN: return shown("start") + shown("fade_in")
		FADE_OUT: return shown("end") - shown("fade_out")
		GAIN: return (shown("start") + shown("end")) * 0.5
	return NAN


func gain_y(db: float) -> float:
	return WAVE_MID + clampf((db - GAIN_LOW) / (GAIN_HIGH - GAIN_LOW), 0.0, 1.0) * WAVE_HALF


## Where the item's file is heard: song time to seconds into the sound, through a loop.
static func file_time(it: MixState.ItemState, seconds: float) -> float:
	var f := it.source_offset + seconds - it.start
	if it.is_looped() and f >= it.loop_end:
		f = it.loop_start + fposmod(f - it.loop_start, it.loop_end - it.loop_start)
	return f


## How long the item's file is (s): read, or from its overview until then; 0 for none.
func file_seconds() -> float:
	var it := item()
	if it == null or it.source.is_empty():
		return 0.0
	var sound := _sound()
	if sound.has("seconds"):
		return float(sound["seconds"])
	return float(it.peaks.size()) / float(AudioTake.PEAKS_PER_SECOND)


func _sound() -> Dictionary:
	return ClipWave.soon(DAW.item_file(target[0], target[1]), item().reversed) if item() != null else {}


## The handle at `local` (the editor's frame), NONE for bare sound. Fades first (they sit in the
## top corners, over the edges), then the edges, then the gain line.
func handle_at(local: Vector3) -> int:
	var it := item()
	if it == null or local.y < WAVE_BOTTOM or local.y > WAVE_TOP or local.x < WAVE_LEFT - EDGE_GRIP or local.x > WAVE_RIGHT + EDGE_GRIP:
		return NONE
	var midi := is_midi()
	if not midi:
		for h in [FADE_IN, FADE_OUT]:
			if absf(local.x - x_for(handle_time(h))) <= FADE_GRIP and WAVE_TOP - local.y <= FADE_GRIP * 1.6:
				return h
	var to_start := absf(local.x - x_for(shown("start")))
	var to_end := absf(local.x - x_for(shown("end")))
	if minf(to_start, to_end) <= EDGE_GRIP:
		return START if to_start <= to_end else END
	if not midi and absf(local.y - gain_y(shown("gain"))) <= GAIN_GRIP \
			and local.x > x_for(shown("start")) and local.x < x_for(shown("end")):
		return GAIN
	return NONE


# --- where a dragged or nudged value lands -----------------------------------------------------

## The take's attacks (song seconds), asked for until there are some: found in the background.
func attacks() -> PackedFloat32Array:
	if _attacks.is_empty() and is_open() and Time.get_ticks_msec() - _attacks_asked > 200:
		_attacks_asked = Time.get_ticks_msec()
		_attacks = DAW.item_transients(target[0], target[1])
	return _attacks


## `seconds` pulled the way the timeline pulls (TimelineLanes.pull), within MAGNET of this panel
## as it is zoomed now: onto an attack, else a grid line, when that near; left alone when FREE or
## fine. Says what it landed on in `pulled_onto`.
func magnet(seconds: float, fine: bool) -> float:
	var free := fine or not snapping
	var reach := TimelineLanes.MAGNET * seconds_per_metre()
	var got := TimelineLanes.pull(seconds, free, reach, attacks())
	pulled_onto = ""
	if not free and not is_equal_approx(got, maxf(seconds, 0.0)):
		var attack := DawKitTransients.nearest(attacks(), seconds)
		pulled_onto = "attack" if not is_nan(attack) and is_equal_approx(attack, got) else "grid"
	return got


## An edge's song time put on the sound's nearest zero crossing, when ZERO X is on and the file
## is here; as it was otherwise.
func to_zero(seconds: float) -> float:
	var it := item()
	if not zero_crossings or it == null or it.source.is_empty():
		return seconds
	var sound := _sound()
	if not sound.has("mono"):
		return seconds
	var f := file_time(it, seconds)
	var crossing := ClipWave.zero_crossing(sound, f, ZERO_REACH)
	if is_nan(crossing):
		return seconds
	pulled_onto = "zero crossing" if pulled_onto == "" else pulled_onto + ", zero crossing"
	return seconds + crossing - f


## Where `handle` goes for song time `seconds`, kept a real clip: an edge no nearer the other than
## the shortest item, never before the file begins or after it ends (outside a loop), a fade
## within the clip. As the fields of `preview`.
func placed(handle: int, seconds: float) -> Dictionary:
	var it := item()
	var start := shown("start")
	var end := shown("end")
	var out := {}
	match handle:
		START:
			var earliest := 0.0
			if not it.source.is_empty() and not it.is_looped():
				earliest = maxf(it.start - it.source_offset, 0.0)
			out["start"] = clampf(seconds, earliest, end - DAWBackend.MIN_ITEM_SECONDS)
		END:
			var latest := INF
			var length := file_seconds()
			if not it.source.is_empty() and not it.is_looped() and length > 0.0:
				latest = it.start - it.source_offset + length
			out["end"] = clampf(seconds, start + DAWBackend.MIN_ITEM_SECONDS, maxf(latest, start + DAWBackend.MIN_ITEM_SECONDS))
		FADE_IN:
			out["fade_in"] = clampf(seconds - start, 0.0, end - start)
		FADE_OUT:
			out["fade_out"] = clampf(end - seconds, 0.0, end - start)
	return out


## The edit for `fields` (placed's), made: one DAW verb, one undo step. Nothing when it would
## change nothing.
func commit(fields: Dictionary) -> void:
	var it := item()
	if it == null or fields.is_empty():
		return
	var t: int = target[0]
	var i: int = target[1]
	if fields.has("start") or fields.has("end"):
		var s := float(fields.get("start", it.start))
		var e := float(fields.get("end", it.end()))
		if not is_equal_approx(s, it.start) or not is_equal_approx(e, it.end()):
			DAW.trim_item(t, i, s, e)
	elif fields.has("fade_in") or fields.has("fade_out"):
		var fi := float(fields.get("fade_in", it.fade_in))
		var fo := float(fields.get("fade_out", it.fade_out))
		if not is_equal_approx(fi, it.fade_in) or not is_equal_approx(fo, it.fade_out):
			DAW.set_item_fades(t, i, fi, fo)
	elif fields.has("gain"):
		if not is_equal_approx(float(fields["gain"]), it.gain_db):
			DAW.set_item_gain(t, i, float(fields["gain"]))


## Whether the clip may be edited here at all: open, and not locked.
func editable() -> bool:
	var it := item()
	return it != null and not it.locked


## The selected handle moved by `seconds` (a nudge key): exactly that far, no pull.
func nudge_by(seconds: float) -> void:
	if not editable() or selected == GAIN:
		return
	pulled_onto = ""
	commit(placed(selected, handle_time(selected) + seconds))


## The selected handle onto the next attack after it (`direction` 1) or the one before (-1), and
## for an edge then onto a zero crossing if ZERO X is on. False when there is none that way.
func nudge_to_attack(direction: int) -> bool:
	if not editable() or selected == GAIN:
		return false
	var now := handle_time(selected)
	var found := NAN
	for a in attacks():
		if direction > 0 and a > now + 0.0005:
			found = a
			break
		if direction < 0 and a < now - 0.0005:
			found = a
	if is_nan(found):
		return false
	pulled_onto = "attack"
	if selected in [START, END]:
		found = to_zero(found)
	commit(placed(selected, found))
	return true


func select_handle(handle: int) -> void:
	if handle in [START, END, FADE_IN, FADE_OUT, GAIN]:
		selected = handle
		_light_keys()
		_stale = true


# --- listening -------------------------------------------------------------------------------

## From the start edge.
func audition_start() -> void:
	var it := item()
	if it == null:
		return
	_stop_at = NAN
	DAW.seek(it.start)
	DAW.transport_play()


## The last TAIL_SECONDS up to the end edge, stopping there: is the tail cut where it should be.
func audition_end() -> void:
	var it := item()
	if it == null:
		return
	_stop_from = maxf(it.start, it.end() - TAIL_SECONDS)
	_stop_at = it.end()
	DAW.seek(_stop_from)
	DAW.transport_play()


## The loop set to the clip's edges and played, or, while it already loops just the clip, the
## loop switched off.
func audition_loop() -> void:
	var it := item()
	if it == null:
		return
	_stop_at = NAN
	if looping_clip():
		DAW.set_looping(false)
		return
	DAW.set_loop_range(it.start, it.end())
	if not DAW.state.looping:
		DAW.set_looping(true)
	DAW.seek(it.start)
	DAW.transport_play()


func looping_clip() -> bool:
	var it := item()
	var s := DAW.state
	return it != null and s.looping and absf(s.loop_start - it.start) < 0.0005 and absf(s.loop_end - it.end()) < 0.0005


# --- building --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	if not is_open() or _mesh == null:
		return
	if _attacks.is_empty() and not attacks().is_empty():
		_stale = true
	if _stale:
		_redraw()
	_move_playhead()
	_watch_tail()


func _watch_tail() -> void:
	if is_nan(_stop_at):
		return
	var s := DAW.state
	if not s.playing:
		_stop_at = NAN
	elif s.position_seconds >= _stop_at:
		_stop_at = NAN
		DAW.transport_stop()
	elif s.position_seconds < _stop_from - 0.25:
		# Somebody put the song somewhere else: not this listen's to stop any more.
		_stop_at = NAN


func _rebuild() -> void:
	_clear_built()
	_keys.clear()
	_captions.clear()
	_values.clear()
	_beat_labels.clear()
	_ms_labels.clear()
	if not is_open():
		_face = null
		_mesh = null
		_playhead = null
		return
	var board := MeshInstance3D.new()
	board.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(WIDE, TOP - BOTTOM, 0.02)
	board.mesh = box
	board.position = Vector3(0, (TOP + BOTTOM) * 0.5, -0.0101)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = BOARD
	paint.roughness = 0.9
	board.material_override = paint
	_adopt(board)
	GearTrim.edges(board)
	if not _wide and arm_to != Vector3.INF:
		_build_arm()

	_mesh = MeshInstance3D.new()
	_mesh.name = "Drawing"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.material_override = _ink_material()
	_adopt(_mesh)
	_playhead = MeshInstance3D.new()
	_playhead.name = "Playhead"
	var line := BoxMesh.new()
	line.size = Vector3(0.0012, RULER_TOP - WAVE_BOTTOM, 0.0006)
	_playhead.mesh = line
	_playhead.material_override = Materials.led(PLAYHEAD_INK, true)
	_playhead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_adopt(_playhead)

	_title = _words("", 0.0145, INK)
	_title.position = Vector3(WAVE_LEFT, TITLE_Y, 0.0015)
	_adopt(_title)
	_status = _words("", 0.012, AMBER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.position = Vector3(READ_RIGHT, TITLE_Y, 0.0015)
	_adopt(_status)
	# The readouts, a column right of the sound: a caption on the left, its value on the right.
	var fields := ["START", "END", "LENGTH", "FADE IN", "FADE OUT", "GAIN"]
	var pitch := (RULER_TOP - WAVE_BOTTOM) / fields.size()
	_quad_board(READ_LEFT - 0.008, WAVE_BOTTOM, READ_RIGHT + 0.006, RULER_TOP)
	for k in fields.size():
		var y := RULER_TOP - (k + 0.5) * pitch
		var caption := _words(fields[k], 0.0115, DIM)
		caption.position = Vector3(READ_LEFT, y, 0.0015)
		_adopt(caption)
		_captions.append(caption)
		var value := _words("", 0.0165, INK)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.position = Vector3(READ_RIGHT, y, 0.0015)
		_adopt(value)
		_values.append(value)
	for k in LABELS:
		var b := _words("", 0.011, DIM)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_adopt(b)
		_beat_labels.append(b)
		var m := _words("", 0.011, INK)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_adopt(m)
		_ms_labels.append(m)
	_message = _words("", 0.0125, DIM)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.position = Vector3((WAVE_LEFT + WAVE_RIGHT) * 0.5, WAVE_TOP - 0.022, 0.0025)
	_adopt(_message)

	_face = Face.new()
	_face.name = "Face"
	_face.editor = self
	_adopt(_face)
	_build_keys()
	_light_keys()
	_stale = true
	_redraw()


## A bracket back to the stand the editor hangs from: a bar from the back of the board, straight
## behind it, to `arm_to` on the stand's leg, so the panel is held by something.
func _build_arm() -> void:
	var to := arm_to
	var from := Vector3(clampf(to.x, -WIDE * 0.5 + 0.02, WIDE * 0.5 - 0.02), clampf(to.y, BOTTOM + 0.02, TOP - 0.02), -0.02)
	var bar := MeshInstance3D.new()
	bar.name = "Arm"
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.022, 0.022, length)
	bar.mesh = mesh
	bar.material_override = Materials.brushed_metal()
	var middle := (from + to) * 0.5
	bar.transform = Transform3D(Basis.looking_at((to - from).normalized(), Vector3.UP if absf((to - from).normalized().y) < 0.95 else Vector3.RIGHT), middle)
	bar.add_to_group(&"presentation_chrome")
	_adopt(bar)


## The keys, two rows: what the nudges work on and the nudges, then the view and listening.
func _build_keys() -> void:
	var rows := [
		[["start", "START", "CLIP  SELECT START", "the start edge is what the nudges move", func(): select_handle(START)],
		["end", "END", "CLIP  SELECT END", "the end edge is what the nudges move", func(): select_handle(END)],
		["fade_in", "FADE IN", "CLIP  SELECT FADE IN", "the fade in's end is what the nudges move", func(): select_handle(FADE_IN)],
		["fade_out", "FADE OUT", "CLIP  SELECT FADE OUT", "the fade out's start is what the nudges move", func(): select_handle(FADE_OUT)],
		null,
		["minus_10", "-10 ms", "CLIP  NUDGE -10 ms", "the selected handle ten milliseconds earlier", func(): nudge_by(-NUDGE_LARGE)],
		["minus_1", "-1 ms", "CLIP  NUDGE -1 ms", "the selected handle a millisecond earlier", func(): nudge_by(-NUDGE_SMALL)],
		["plus_1", "+1 ms", "CLIP  NUDGE +1 ms", "the selected handle a millisecond later", func(): nudge_by(NUDGE_SMALL)],
		["plus_10", "+10 ms", "CLIP  NUDGE +10 ms", "the selected handle ten milliseconds later", func(): nudge_by(NUDGE_LARGE)],
		null,
		["hit_back", "◀ HIT", "CLIP  TO THE ATTACK BEFORE", "the selected handle onto the take's attack before it", func(): nudge_to_attack(-1)],
		["hit_on", "HIT ▶", "CLIP  TO THE NEXT ATTACK", "the selected handle onto the take's next attack", func(): nudge_to_attack(1)],
		null,
		["snap", "SNAP", "CLIP  SNAP OR FREE", "", func(): set_snapping(not snapping)],
		["zero", "ZERO X", "CLIP  TO ZERO CROSSINGS", "", func(): set_zero_crossings(not zero_crossings)]],
		[["zoom_out", "ZOOM -", "CLIP  ZOOM OUT", "see more of the song; the wheel zooms round the pointer", func(): zoom(1.0 / ZOOM_STEP)],
		["zoom_in", "ZOOM +", "CLIP  ZOOM IN", "see less of it, closer: down to a few milliseconds across", func(): zoom(ZOOM_STEP)],
		["fit", "FIT", "CLIP  FIT", "the whole clip, a little either side", func(): fit()],
		["back", "◀", "CLIP  SCROLL EARLIER", "a quarter of the view earlier; fine wheel scrolls", func(): scroll(-0.25)],
		["on", "▶", "CLIP  SCROLL LATER", "a quarter of the view later", func(): scroll(0.25)],
		null,
		["play", "PLAY", "CLIP  PLAY FROM THE START", "the song from the clip's start edge", func(): audition_start()],
		["tail", "TO END", "CLIP  PLAY TO THE END", "the last second up to the end edge, and stop there", func(): audition_end()],
		["loop", "LOOP", "CLIP  LOOP IT", "", func(): audition_loop()],
		null,
		["close", "CLOSE", "CLIP  CLOSE", "put the clip editor away", func(): close()]],
	]
	for r in rows.size():
		var specs: Array = rows[r]
		var x := WAVE_LEFT + KEY_SIZE.x * 0.5
		for spec in specs:
			if spec == null:
				x += GROUP_GAP
				continue
			var key := EditKey.new()
			key.name = "Key" + String(spec[0]).capitalize().replace(" ", "")
			key.legend = spec[1]
			key.says = spec[3]
			key.size = KEY_SIZE
			key.position = Vector3(x, KEYS_Y[r], 0.0)
			var title: String = spec[2]
			key.describe_title = func() -> String: return title
			key.pressed.connect(spec[4])
			key.pressed.connect(func() -> void:
				_stale = true
				_light_keys())
			_adopt(key)
			_keys[StringName(spec[0])] = key
			x += KEY_SIZE.x + KEY_GAP
	(_keys[&"snap"] as EditKey).says_now = func() -> String:
		return "on: drags pull onto attacks and the grid when close; press for free" if snapping \
				else "free: drags land where they are let go; press to snap"
	(_keys[&"zero"] as EditKey).says_now = func() -> String:
		return "on: a trimmed edge goes to the sound's nearest zero crossing" if zero_crossings \
				else "off: press to put trimmed edges on zero crossings, so a cut does not click"
	(_keys[&"loop"] as EditKey).says_now = func() -> String:
		return "looping the clip: press to stop looping" if looping_clip() else "loop the song over the clip and play it"


func key(key_name: StringName) -> EditKey:
	return _keys.get(key_name)


func set_snapping(on: bool) -> void:
	snapping = on
	_light_keys()
	_stale = true


func set_zero_crossings(on: bool) -> void:
	zero_crossings = on
	_light_keys()
	_stale = true


func _light_keys() -> void:
	if _keys.is_empty():
		return
	var it := item()
	var can := editable()
	var midi := is_midi()
	var audio := it != null and not it.source.is_empty()
	var picks := {&"start": START, &"end": END, &"fade_in": FADE_IN, &"fade_out": FADE_OUT}
	for k in picks:
		(_keys[k] as EditKey).lit = selected == picks[k]
	(_keys[&"fade_in"] as EditKey).available = not midi
	(_keys[&"fade_out"] as EditKey).available = not midi
	for k in [&"minus_10", &"minus_1", &"plus_1", &"plus_10"]:
		(_keys[k] as EditKey).available = can and selected != GAIN
	for k in [&"hit_back", &"hit_on"]:
		(_keys[k] as EditKey).available = can and audio and selected != GAIN
	var snap := _keys[&"snap"] as EditKey
	snap.lit = snapping
	snap.legend = "SNAP" if snapping else "FREE"
	var zero := _keys[&"zero"] as EditKey
	zero.lit = zero_crossings
	zero.available = audio
	(_keys[&"loop"] as EditKey).lit = looping_clip()


static var _ink: StandardMaterial3D


static func _ink_material() -> StandardMaterial3D:
	if _ink == null:
		_ink = StandardMaterial3D.new()
		_ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ink.vertex_color_use_as_albedo = true
		_ink.vertex_color_is_srgb = true
	return _ink


## A recessed plate behind the readouts, so they read as one instrument.
func _quad_board(x0: float, y0: float, x1: float, y1: float) -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Readouts"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x1 - x0, y1 - y0, 0.001)
	plate.mesh = mesh
	plate.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 0.0004)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = BED
	paint.roughness = 0.95
	plate.material_override = paint
	_adopt(plate)


func _words(text: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Flat on the board, read from the front: lettering on the gear, never a sign in the air.
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.render_priority = 2
	l.set_meta(&"largest", l.font_size)
	Lettering.range_to_legibility(l)
	return l


# --- drawing ---------------------------------------------------------------------------------

## Everything that follows the clip and the view, in one mesh, and the lettering over it.
func _redraw() -> void:
	_stale = false
	if _mesh == null or not is_open():
		return
	var it := item()
	if it == null:
		return
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var tint: Color = DAW.state.track(target[0]).colour if DAW.state.tracks.has(target[0]) else Color(0.55, 0.6, 0.7)
	var start := shown("start")
	var end := shown("end")
	var left := clampf(x_for(start), WAVE_LEFT, WAVE_RIGHT)
	var right := clampf(x_for(end), WAVE_LEFT, WAVE_RIGHT)
	# The bed, the clip's body over it, and the middle line.
	_quad(v, c, WAVE_LEFT, WAVE_BOTTOM, WAVE_RIGHT, WAVE_TOP, 0.0004, BED)
	if right > left:
		_quad(v, c, left, WAVE_BOTTOM, right, WAVE_TOP, 0.0006, Color.from_hsv(tint.h, tint.s * 0.5, 0.16))
	_quad(v, c, WAVE_LEFT, WAVE_MID - 0.0003, WAVE_RIGHT, WAVE_MID + 0.0003, 0.0007, GRID_INK)
	_quad(v, c, WAVE_LEFT, RULER_BOTTOM, WAVE_RIGHT, RULER_TOP, 0.0004, BED.lightened(0.04))
	_draw_grid(v, c)
	var message := ""
	if is_midi():
		_draw_notes(v, c, it, tint)
		message = "MIDI: drag an edge to trim the notes; fades and gain are an audio clip's"
	elif it.source.is_empty():
		message = "no sound file: drag the edges and corners as on the timeline"
	else:
		message = _draw_sound(v, c, it, tint)
	_draw_attacks(v, c)
	_draw_handles(v, c, it)
	if it.locked:
		message = "LOCKED: unlock it on the item page to edit it"
	if message != "":
		# A dark strip behind the words, so notes or a loud passage under them do not eat them.
		var y := WAVE_TOP - 0.022
		_quad(v, c, WAVE_LEFT + 0.01, y - 0.011, WAVE_RIGHT - 0.01, y + 0.011, 0.0021, BED)
	var mesh := ArrayMesh.new()
	if not v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_COLOR] = c
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh
	_message.text = message
	_message.visible = message != ""
	Lettering.fit(_message, WAVE_WIDE * 0.9, _message.get_meta(&"largest"), 40)
	_write_words(it)
	_light_keys()


func _quad(v: PackedVector3Array, c: PackedColorArray, x0: float, y0: float, x1: float, y1: float,
		z: float, colour: Color) -> void:
	v.append_array([Vector3(x0, y0, z), Vector3(x1, y1, z), Vector3(x1, y0, z),
			Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z)])
	for _k in 6:
		c.append(colour)


## A line `width` wide from `a` to `b` (x, y), at `z`.
func _segment(v: PackedVector3Array, c: PackedColorArray, a: Vector2, b: Vector2, width: float,
		z: float, colour: Color) -> void:
	var along := (b - a)
	if along.length() < 0.00001:
		along = Vector2(1, 0) * 0.00001
	var side := Vector2(-along.y, along.x).normalized() * width * 0.5
	# Wound as _quad's are (a's lower corner, b's upper, b's lower; then a's lower, a's upper, b's
	# upper), so the face is toward the room and not culled.
	var p := [a - side, a + side, b + side, b - side]
	v.append_array([Vector3(p[0].x, p[0].y, z), Vector3(p[2].x, p[2].y, z), Vector3(p[3].x, p[3].y, z),
			Vector3(p[0].x, p[0].y, z), Vector3(p[1].x, p[1].y, z), Vector3(p[2].x, p[2].y, z)])
	for _k in 6:
		c.append(colour)


## The lines of the grid a drag snaps to (TimelineLanes.grid), bars brighter, while they are no
## nearer each other than a few millimetres; and the ruler's lettering.
func _draw_grid(v: PackedVector3Array, c: PackedColorArray) -> void:
	var s := DAW.state
	var to := view_start + view_span
	# Bars and beats along the ruler's top, one in so many lettered.
	var first_beat := ceilf(s.beat_at(maxf(view_start, 0.0)))
	var last_beat := floorf(s.beat_at(maxf(to, 0.0)))
	var beats := int(last_beat - first_beat) + 1
	var step := 1
	while beats / step > LABELS - 1:
		step *= 2
	var lettered := 0
	if beats > 0 and beats < 4000:
		for k in range(0, beats):
			var b := first_beat + k
			var at := s.seconds_at_beat(b)
			var x := x_for(at)
			var is_bar := absf(s.bar_at(at) - roundf(s.bar_at(at))) < 0.0005
			if beats <= 400:
				_quad(v, c, x - 0.00035, RULER_TOP - 0.010, x + 0.00035, RULER_TOP, 0.0008, BAR_INK if is_bar else GRID_INK.lightened(0.2))
			if int(b) % step == 0 and lettered < LABELS:
				var l := _beat_labels[lettered]
				l.text = s.bar_beat(at)
				l.position = Vector3(x, BEATS_Y, 0.0015)
				l.visible = x > WAVE_LEFT + 0.012 and x < WAVE_RIGHT - 0.012
				lettered += 1
	for k in range(lettered, LABELS):
		_beat_labels[k].visible = false
	# The grid through the sound.
	var g := TimelineLanes.grid
	if g != TimelineLanes.OFF:
		var lines: Array[float] = []
		if g == TimelineLanes.BAR:
			var bar := ceilf(s.bar_at(maxf(view_start, 0.0)))
			while lines.size() < 400 and s.bar_to_seconds(bar) <= to:
				lines.append(s.bar_to_seconds(bar))
				bar += 1.0
		else:
			var b := ceilf(s.beat_at(maxf(view_start, 0.0)) / g) * g
			while lines.size() < 400 and s.seconds_at_beat(b) <= to:
				lines.append(s.seconds_at_beat(b))
				b += g
		var apart := WAVE_WIDE / maxf(lines.size(), 1)
		if lines.size() < 400 and apart > 0.003:
			for at in lines:
				var x := x_for(at)
				var bar_line := absf(s.bar_at(at) - roundf(s.bar_at(at))) < 0.0005
				_quad(v, c, x - 0.0003, WAVE_BOTTOM, x + 0.0003, WAVE_TOP, 0.0009, BAR_INK if bar_line else GRID_INK)
	# Milliseconds from the clip's start, under the beats.
	var it := item()
	var zero := it.start if it != null else 0.0
	var tick := _tick_step(view_span)
	var n0 := ceilf((view_start - zero) / tick)
	var k := 0
	while k < LABELS:
		var at := zero + (n0 + k) * tick
		if at > to:
			break
		var x := x_for(at)
		_quad(v, c, x - 0.0004, RULER_BOTTOM, x + 0.0004, RULER_BOTTOM + 0.004, 0.0008, INK)
		var l := _ms_labels[k]
		l.text = time_words(at - zero, tick)
		l.position = Vector3(x, MS_Y, 0.0015)
		l.visible = x > WAVE_LEFT + 0.014 and x < WAVE_RIGHT - 0.014
		k += 1
	for rest in range(k, LABELS):
		_ms_labels[rest].visible = false


## A round step for the ruler's ticks: no more than LABELS - 1 across `span` seconds.
static func _tick_step(span: float) -> float:
	for step in [0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5,
			1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 60.0, 120.0]:
		if span / step <= LABELS - 1:
			return step
	return 300.0


## `seconds` from the clip's start as the ruler letters it, to the precision of `step`: "+250 ms",
## "-1.5 ms", "+2 s".
static func time_words(seconds: float, step: float) -> String:
	if absf(seconds) < step * 0.01:
		return "0"
	var sign := "+" if seconds > 0.0 else "-"
	var a := absf(seconds)
	if step >= 1.0:
		return "%s%d s" % [sign, roundi(a)]
	if step >= 0.1:
		return "%s%.1f s" % [sign, a]
	if step >= 0.001:
		return "%s%d ms" % [sign, roundi(a * 1000.0)]
	return "%s%.1f ms" % [sign, a * 1000.0]


## The sound, from its file: columns of its lowest and highest, or a line through its samples
## once a column is narrower than a frame or two; beyond the clip's edges faint, inside them as
## heard (through the gain and fades). What to letter over it, or "".
func _draw_sound(v: PackedVector3Array, c: PackedColorArray, it: MixState.ItemState, tint: Color) -> String:
	var sound := _sound()
	var from_file := sound.has("mono")
	var message := ""
	var peak := 1.0
	var here := not DAW.item_file(target[0], target[1]).is_empty()
	if from_file:
		var lo2: PackedFloat32Array = sound["lo2"]
		var hi2: PackedFloat32Array = sound["hi2"]
		peak = 0.0001
		for k in lo2.size():
			peak = maxf(peak, maxf(-lo2[k], hi2[k]))
	elif sound.has("error"):
		message = "the file could not be read: %s" % sound["error"]
	elif here:
		# Being read: its overview meanwhile.
		message = "reading the file..."
	else:
		message = "the file is not on this machine: drawn from its overview, a fiftieth of a second a column"
	if not from_file and it.peaks.is_empty():
		return message
	var length := file_seconds()
	var inside := Color.from_hsv(tint.h, clampf(tint.s * 0.7, 0.25, 0.7), 0.95)
	var column := WAVE_WIDE / COLUMNS
	var per := view_span / COLUMNS
	var rate := float(sound.get("rate", AudioTake.PEAKS_PER_SECOND))
	var as_line := from_file and per * rate < LINE_BELOW
	var start := shown("start")
	var end := shown("end")
	var last := Vector2.INF
	var last_inside := false
	for k in COLUMNS:
		var s0 := view_start + k * per
		var mid := s0 + per * 0.5
		var f := file_time(it, s0)
		if f + per < 0.0 or (not it.is_looped() and f > length):
			last = Vector2.INF
			continue
		var heard := mid >= start and mid <= end
		var scale := DRAWN_PEAK / peak
		if heard:
			scale *= minf(db_to_linear(_level_db(it, mid)), 4.0)
		var colour := inside if heard else BEYOND
		var x := WAVE_LEFT + (k + 0.5) * column
		if as_line:
			var p := Vector2(x, WAVE_MID + clampf(ClipWave.sample_at(sound, f + per * 0.5) * scale, -1.0, 1.0) * WAVE_HALF)
			if last != Vector2.INF:
				_segment(v, c, last, p, 0.0011, 0.0012, colour if heard or last_inside == heard else BEYOND)
			last = p
			last_inside = heard
			continue
		var span := Vector2.ZERO
		if from_file:
			span = ClipWave.span(sound, f, f + per)
		else:
			var a := clampi(int(floor(f * AudioTake.PEAKS_PER_SECOND)), 0, it.peaks.size() - 1)
			var b := clampi(int(ceil((f + per) * AudioTake.PEAKS_PER_SECOND)), a + 1, it.peaks.size())
			var loudest := 0
			for n in range(a, b):
				loudest = maxi(loudest, it.peaks[n])
			span = Vector2(-loudest / 255.0, loudest / 255.0)
		var lo := WAVE_MID + clampf(span.x * scale, -1.0, 1.0) * WAVE_HALF
		var hi := WAVE_MID + clampf(span.y * scale, -1.0, 1.0) * WAVE_HALF
		if hi - lo < 0.0005:
			lo -= 0.00025
			hi += 0.00025
		_quad(v, c, x - column * 0.5, lo, x + column * 0.5, hi, 0.0012, colour)
	return message


## The clip's own level at song time `seconds` as drawn (dB): the drag's gain and fades.
func _level_db(it: MixState.ItemState, seconds: float) -> float:
	var through := 1.0
	var fi := shown("fade_in")
	var fo := shown("fade_out")
	if fi > 0.0:
		through = minf(through, DawKitClip.fade_gain((seconds - shown("start")) / fi, it.fade_shape))
	if fo > 0.0:
		through = minf(through, DawKitClip.fade_gain((shown("end") - seconds) / fo, it.fade_out_shape))
	return shown("gain") + linear_to_db(clampf(through, 0.0001, 1.0))


func _draw_notes(v: PackedVector3Array, c: PackedColorArray, it: MixState.ItemState, tint: Color) -> void:
	var layout := TimelineSurface.note_layout(it.notes)
	var rows := float(layout["rows"])
	var row_h := (WAVE_TOP - WAVE_BOTTOM - 0.02) / rows
	var n := 0
	while n + MidiTake.NOTE_WIDTH <= it.notes.size():
		var on := it.start + it.notes[n]
		var off := it.start + it.notes[n + 1]
		var x0 := clampf(x_for(on), WAVE_LEFT, WAVE_RIGHT)
		var x1 := clampf(x_for(off), WAVE_LEFT, WAVE_RIGHT)
		if x1 > x0:
			var y := WAVE_BOTTOM + 0.01 + (float(it.notes[n + 2]) - float(layout["low"]) + 0.5) * row_h
			var heard := on >= shown("start") and on < shown("end")
			_quad(v, c, x0, y - row_h * 0.4, maxf(x1, x0 + 0.0008), y + row_h * 0.4, 0.0012,
					tint.lightened(0.35) if heard else BEYOND)
		n += MidiTake.NOTE_WIDTH


## The take's attacks: an amber tick down from the top of the sound and a faint line through it.
func _draw_attacks(v: PackedVector3Array, c: PackedColorArray) -> void:
	var drawn := 0
	for a in attacks():
		if a < view_start or a > view_start + view_span:
			continue
		var x := x_for(a)
		_quad(v, c, x - 0.0006, WAVE_TOP - 0.009, x + 0.0006, WAVE_TOP, 0.0016, AMBER)
		_quad(v, c, x - 0.0002, WAVE_BOTTOM, x + 0.0002, WAVE_TOP - 0.009, 0.0013, AMBER.darkened(0.55))
		drawn += 1
		if drawn > 600:
			break


## The edges, the fades' lines and corners, and the gain line, each lit when it is the one held,
## under the pointer, or selected.
func _draw_handles(v: PackedVector3Array, c: PackedColorArray, it: MixState.ItemState) -> void:
	var start := shown("start")
	var end := shown("end")
	var held := _face.held if _face != null else NONE
	var ink := func(handle: int, base: Color) -> Color:
		if handle == held:
			return HELD_INK
		if handle == hovered_handle:
			return base.lightened(0.35)
		return base
	for h in [START, END]:
		var x := x_for(start if h == START else end)
		if x < WAVE_LEFT - 0.001 or x > WAVE_RIGHT + 0.001:
			continue
		var wide := 0.0022 if h == selected or h == held else 0.0014
		var colour: Color = ink.call(h, EDGE_INK)
		_quad(v, c, x - wide * 0.5, WAVE_BOTTOM, x + wide * 0.5, WAVE_TOP, 0.0017, colour)
		# A tab at its foot, pointing into the clip, to take hold of.
		var into := 1.0 if h == START else -1.0
		_quad(v, c, minf(x, x + into * 0.009), WAVE_BOTTOM, maxf(x, x + into * 0.009), WAVE_BOTTOM + 0.014, 0.0017, colour)
	if is_midi():
		return
	# The fades: the envelope over the sound, and a corner to hold at each one's end.
	for h in [FADE_IN, FADE_OUT]:
		var length := shown("fade_in" if h == FADE_IN else "fade_out")
		var colour: Color = ink.call(h, FADE_INK)
		if length > 0.0:
			var last := Vector2.INF
			for k in 25:
				var t := k / 24.0
				var at := start + t * length if h == FADE_IN else end - length + t * length
				var g := DawKitClip.fade_gain(t if h == FADE_IN else 1.0 - t, it.fade_shape if h == FADE_IN else it.fade_out_shape)
				var p := Vector2(clampf(x_for(at), WAVE_LEFT, WAVE_RIGHT), WAVE_MID + g * WAVE_HALF)
				if last != Vector2.INF:
					_segment(v, c, last, p, 0.0011, 0.0018, colour)
				last = p
		var x := x_for(handle_time(h))
		if x >= WAVE_LEFT - 0.001 and x <= WAVE_RIGHT + 0.001:
			var r := 0.0055 if h == held or h == hovered_handle or h == selected else 0.0042
			_quad(v, c, x - r, WAVE_TOP - r * 2.0, x + r, WAVE_TOP, 0.0019, colour)
	# The gain line across the clip, a bead in its middle.
	var y := gain_y(shown("gain"))
	var l := clampf(x_for(start), WAVE_LEFT, WAVE_RIGHT)
	var r2 := clampf(x_for(end), WAVE_LEFT, WAVE_RIGHT)
	if r2 > l:
		var colour: Color = ink.call(GAIN, GAIN_INK)
		_quad(v, c, l, y - 0.0006, r2, y + 0.0006, 0.0018, colour.darkened(0.15))
		var mx := (l + r2) * 0.5
		var bead := 0.006 if GAIN in [held, hovered_handle, selected] else 0.0045
		_quad(v, c, mx - bead, y - bead * 0.7, mx + bead, y + bead * 0.7, 0.0019, colour)


func _move_playhead() -> void:
	if _playhead == null:
		return
	var at := DAW.state.position_seconds
	var x := x_for(at)
	_playhead.visible = x >= WAVE_LEFT and x <= WAVE_RIGHT
	_playhead.position = Vector3(x, (RULER_TOP + WAVE_BOTTOM) * 0.5, 0.0024)


## The title, what the panel is set to, and the six readouts.
func _write_words(it: MixState.ItemState) -> void:
	var track_name := DAW.state.track(target[0]).display_name() if DAW.state.tracks.has(target[0]) else "?"
	_title.text = "CLIP  %s  ·  %s" % [track_name.to_upper(), it.name if it.name != "" else "(unnamed)"]
	Lettering.fit(_title, WAVE_WIDE * 0.9, _title.get_meta(&"largest"), 60)
	var says: PackedStringArray = []
	if it.locked:
		says.append("LOCKED")
	says.append("SNAP" if snapping else "FREE")
	if zero_crossings:
		says.append("ZERO X")
	says.append("NUDGING %s" % HANDLE_NAMES[selected])
	_status.text = "  ·  ".join(says)
	Lettering.fit(_status, READ_RIGHT - WAVE_LEFT - 0.36, _status.get_meta(&"largest"), 60)
	var start := shown("start")
	var end := shown("end")
	var texts := ["%.3f s" % start, "%.3f s" % end, length_words(end - start),
			"%.1f ms" % (shown("fade_in") * 1000.0), "%.1f ms" % (shown("fade_out") * 1000.0),
			"%+.1f dB" % shown("gain")]
	if is_midi():
		texts[3] = "-"
		texts[4] = "-"
		texts[5] = "-"
	for k in _values.size():
		_values[k].text = texts[k]
		_values[k].modulate = HELD_INK if not preview.is_empty() and _field_of(k) in preview else INK
		Lettering.fit(_values[k], READ_RIGHT - READ_LEFT - 0.06, _values[k].get_meta(&"largest"), 80)


static func _field_of(k: int) -> String:
	return ["start", "end", "end", "fade_in", "fade_out", "gain"][k]


static func length_words(seconds: float) -> String:
	return "%.1f ms" % (seconds * 1000.0) if seconds < 10.0 else "%.3f s" % seconds


## The panel's own words for the readouts, for the suite: START, END, LENGTH, FADE IN, FADE OUT, GAIN.
func readouts() -> PackedStringArray:
	var out: PackedStringArray = []
	for l in _values:
		out.append(l.text)
	return out


func title_text() -> String:
	return _title.text if _title != null else ""


func message_text() -> String:
	return _message.text if _message != null and _message.visible else ""


# --- the controls ----------------------------------------------------------------------------

## The sound, as something to take hold of: the edges, the fades' corners and the gain line, and
## bare sound to put the playhead on or to scroll. One control over all of it, as the timeline's
## lanes are one (TimelineLanes), so a redraw never drops a drag.
class Face extends ControlAffordance:
	var editor: ClipEditorSurface
	## The handle held, NONE for bare sound or nothing.
	var held := ClipEditorSurface.NONE
	var _grab := Vector3.ZERO
	var _grab_seconds := 0.0
	var _grab_view := 0.0
	var _grab_gain := 0.0
	var _offset := 0.0
	var _dragged := false
	var _shape: CollisionShape3D

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		_shape = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(ClipEditorSurface.WAVE_WIDE, ClipEditorSurface.RULER_TOP - ClipEditorSurface.WAVE_BOTTOM, 0.01)
		_shape.shape = box
		_shape.position = Vector3((ClipEditorSurface.WAVE_LEFT + ClipEditorSurface.WAVE_RIGHT) * 0.5,
				(ClipEditorSurface.RULER_TOP + ClipEditorSurface.WAVE_BOTTOM) * 0.5, 0.004)
		add_child(_shape)

	func personal() -> bool:
		return true

	func network_key() -> String:
		return "CLIP EDITOR"

	func _fine() -> bool:
		return held_by != null and held_by.has_method("fine") and held_by.fine()

	func _local(at: Vector3) -> Vector3:
		return editor.to_local(at)

	func _on_grab_begin(at: Vector3) -> void:
		_grab = _local(at)
		_grab_seconds = editor.seconds_at_x(_grab.x)
		_grab_view = editor.view_start
		_dragged = false
		held = editor.handle_at(_grab)
		if held != ClipEditorSurface.NONE and not editor.editable():
			held = ClipEditorSurface.NONE
		if held != ClipEditorSurface.NONE:
			editor.select_handle(held)
			_offset = editor.handle_time(held) - _grab_seconds
			_grab_gain = editor.shown("gain")
		editor.pulled_onto = ""
		editor._stale = true

	func _on_grab_move(at: Vector3) -> void:
		var p := _local(at)
		if not _dragged and absf(p.x - _grab.x) < ClipEditorSurface.CLICK_SLOP and absf(p.y - _grab.y) < ClipEditorSurface.CLICK_SLOP:
			return
		_dragged = true
		var fine := _fine()
		match held:
			ClipEditorSurface.NONE:
				# Bare sound dragged: the view, held under the hand.
				editor.set_view(_grab_view - (p.x - _grab.x) * editor.seconds_per_metre(), editor.view_span)
			ClipEditorSurface.GAIN:
				var per_metre := (ClipEditorSurface.GAIN_HIGH - ClipEditorSurface.GAIN_LOW) / ClipEditorSurface.WAVE_HALF
				var db := _grab_gain + (p.y - _grab.y) * per_metre * (0.1 if fine else 1.0)
				db = clampf(db, DAWBackend.ITEM_GAIN_MIN, DAWBackend.ITEM_GAIN_MAX)
				if editor.snapping and not fine:
					db = 0.0 if absf(db) < ClipEditorSurface.GAIN_DETENT else roundf(db * 10.0) / 10.0
				editor.preview = {"gain": db}
			_:
				var seconds := editor.magnet(editor.seconds_at_x(p.x) + _offset, fine)
				if held in [ClipEditorSurface.START, ClipEditorSurface.END]:
					seconds = editor.to_zero(seconds)
				editor.preview = editor.placed(held, seconds)
		editor._stale = true

	func _on_grab_end() -> void:
		if not _dragged and held == ClipEditorSurface.NONE:
			DAW.seek(maxf(_grab_seconds, 0.0))
		elif _dragged and held != ClipEditorSurface.NONE:
			var fields := editor.preview
			editor.preview = {}
			editor.commit(fields)
		editor.preview = {}
		held = ClipEditorSurface.NONE
		_dragged = false
		editor._stale = true

	func _on_nudge(notches: int, fine: bool) -> bool:
		if fine:
			editor.scroll(notches * ClipEditorSurface.SCROLL_STEP)
		else:
			editor.zoom(pow(ClipEditorSurface.ZOOM_STEP, notches), _pointer_seconds())
		return true

	func _pointer() -> Node:
		return held_by if held_by != null else (_hovered_by[0] if not _hovered_by.is_empty() else null)

	func _pointer_seconds() -> float:
		var by := _pointer()
		if by == null or not ("hover_point" in by):
			return NAN
		return editor.seconds_at_x(_local(by.hover_point).x)

	func _pointer_handle() -> int:
		if held != ClipEditorSurface.NONE:
			return held
		var by := _pointer()
		if by == null or not ("hover_point" in by):
			return ClipEditorSurface.NONE
		return editor.handle_at(_local(by.hover_point))

	func _process(_delta: float) -> void:
		var h := _pointer_handle() if is_hovered() or held_by != null else ClipEditorSurface.NONE
		if h != editor.hovered_handle:
			editor.hovered_handle = h
			editor._stale = true

	func _default_title() -> String:
		var h := _pointer_handle()
		var it := editor.item()
		if h == ClipEditorSurface.NONE or it == null:
			return "CLIP EDITOR"
		return "CLIP  %s%s" % [ClipEditorSurface.HANDLE_NAMES[h], "  LOCKED" if it.locked else ""]

	func _default_readout() -> String:
		var it := editor.item()
		if it == null:
			return ""
		var h := _pointer_handle()
		var s := DAW.state
		var onto := "" if editor.pulled_onto == "" else "  on the %s" % editor.pulled_onto
		match h:
			ClipEditorSurface.START, ClipEditorSurface.END:
				var at := editor.handle_time(h)
				var moved := (at - (it.start if h == ClipEditorSurface.START else it.end())) * 1000.0
				return "%.3f s  (%s)%s%s" % [at, s.bar_beat(at), "  %+.1f ms" % moved if absf(moved) >= 0.05 else "", onto]
			ClipEditorSurface.FADE_IN:
				return "%.1f ms%s" % [editor.shown("fade_in") * 1000.0, onto]
			ClipEditorSurface.FADE_OUT:
				return "%.1f ms%s" % [editor.shown("fade_out") * 1000.0, onto]
			ClipEditorSurface.GAIN:
				return "%+.1f dB" % editor.shown("gain")
		var at := _pointer_seconds()
		if is_nan(at):
			return "view %.3f - %.3f s" % [editor.view_start, editor.view_start + editor.view_span]
		return "%.3f s  (%s)  %s from the clip's start" % [at, s.bar_beat(at), ClipEditorSurface.time_words(at - it.start, 0.0001)]

	func hint() -> String:
		var h := _pointer_handle()
		match h:
			ClipEditorSurface.START, ClipEditorSurface.END:
				return "drag to trim; pulled onto an attack or the grid when close (SNAP), fine (shift) or FREE for anywhere"
			ClipEditorSurface.FADE_IN, ClipEditorSurface.FADE_OUT:
				return "drag to set the fade; pulled onto an attack or the grid when close, fine for free"
			ClipEditorSurface.GAIN:
				return "drag up or down for the clip's gain; fine for tenths"
		return "click to put the playhead here, drag to scroll; wheel zooms round the pointer, fine wheel scrolls"


## A key on the editor's face: a dark cap with its words on it, a lamp under them when lit.
class EditKey extends ControlAffordance:
	signal pressed()
	var legend := "":
		set(v):
			legend = v
			if _legend != null:
				_legend.text = v
				Lettering.fit(_legend, size.x - 0.006, _legend.get_meta(&"largest"), 50)
	var says := ""
	## () -> String, for a key whose card changes with what it is set to; over `says`.
	var says_now: Callable = Callable()
	var size := Vector2(0.052, 0.036)
	var lit := false:
		set(v):
			lit = v
			_refresh()
	var available := true:
		set(v):
			available = v
			collision_layer = 2 if v else 0
			_refresh()
	var _legend: Label3D
	var _lamp: MeshInstance3D
	var _cap: MeshInstance3D

	func _ready() -> void:
		collision_layer = 2 if available else 0
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.012)
		shape.shape = box
		shape.position = Vector3(0, 0, 0.006)
		add_child(shape)
		_cap = MeshInstance3D.new()
		_cap.name = "Cap"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x - 0.003, size.y - 0.003, 0.006)
		_cap.mesh = mesh
		_cap.position = Vector3(0, 0, 0.003)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.12, 0.125, 0.14)
		paint.roughness = 0.7
		_cap.material_override = paint
		add_child(_cap)
		_legend = Label3D.new()
		_legend.name = "Legend"
		_legend.pixel_size = ClipEditorSurface.PIXEL
		_legend.font_size = roundi(0.0125 / ClipEditorSurface.PIXEL)
		_legend.set_meta(&"largest", _legend.font_size)
		_legend.position = Vector3(0, 0.002, 0.0062)
		_legend.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_legend.double_sided = false
		_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Lettering.range_to_legibility(_legend)
		add_child(_legend)
		_lamp = MeshInstance3D.new()
		_lamp.name = "Lamp"
		var bar := BoxMesh.new()
		bar.size = Vector3(size.x * 0.5, 0.003, 0.001)
		_lamp.mesh = bar
		_lamp.position = Vector3(0, -size.y * 0.5 + 0.0055, 0.0062)
		add_child(_lamp)
		legend = legend
		hover_changed.connect(func(_on: bool) -> void: _refresh())
		_refresh()

	func _refresh() -> void:
		if _legend == null:
			return
		_legend.modulate = (Color(1.0, 0.86, 0.5) if lit else ClipEditorSurface.INK) if available else Color(0.36, 0.38, 0.42)
		_lamp.material_override = Materials.led(ClipEditorSurface.AMBER, true)
		_lamp.visible = lit and available
		_cap.position.z = 0.003 + (0.0015 if is_hovered() and available else 0.0)

	func hint() -> String:
		return says_now.call() if says_now.is_valid() else says

	func dwell_activates() -> bool:
		return available

	func personal() -> bool:
		return true

	func _default_readout() -> String:
		return ""

	func _foley_contact() -> AudioStream:
		return Foley.button_click()

	func _on_grab_begin(_at: Vector3) -> void:
		if available:
			pressed.emit()
