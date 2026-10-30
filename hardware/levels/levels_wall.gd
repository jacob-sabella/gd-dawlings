class_name LevelsWall
extends Surface

## LEVELS (docs/spatial_loop.md part three, F): a wall of every track's level, set into a niche in
## the control room's front wall left of the timeline, a whole stretch of wall (2026-10-30: "it would
## make more sense as its own like divet in the wall so it can be an entire wall in each of the
## venues"); where a venue has no walls, the niche is a cabinet standing in from the edge.
##
## THE TRACKS. A column a track, side by side, against three fixed lines across them all: −18
## dBFS (where a track sits with room to spare), −6 and 0. Each column is the track's peak after its
## fader, falling FALL_DB a second, with its peak held HOLD_MSEC as a tick and as a number over it
## ("−4.2", red "+1.3" over 0 dBFS), the track's name under it, and its fader's setting as a notch
## down its side. A compressor's gain reduction pushes the column down from the top: a bar hanging
## from the top of the scale as many decibels long as it takes, lettered "GR −4.1" -- on the
## built-in engine worked out from its probes, on Reaper what ReaComp and its kind report
## (SignalGraph). Taken hold of and dragged up or down (a desk's click-drag, a hand's pinch), a column
## is that track's fader: the column follows the hand, a decibel for every decibel of the scale;
## one undo step a drag; the wheel 0.5 dB, Shift 0.1. Every write is DAW's, so a guest's is an
## intent its host carries out and the host's word stands. More tracks than fit scroll: drag or
## wheel the names, or the ◀ ▶ keys; the foot says which are shown ("TRACKS 1-16 OF 40").
##
## THE MASTER, on the right. Its loudness as BS.1770 measures it (LoudnessMeter, on the built-in
## engine's master tap; MixState.MasterState.lufs_s and the rest, a guest's the host's): short-term
## large, integrated (since the transport last started, or RESET) and momentary under it, as a bar
## against the TARGET chosen with its key -- STREAMING −14, CLUB −8, BROADCAST −23, or CUSTOM, set
## with the wheel over the key -- and in words: "+1.2 LU OVER STREAMING −14", "ON TARGET". Its
## true-ish peak ("≈ −0.8 dBTP", amber over −1, red over 0), and the phase: a needle from −1 to +1,
## in words -- MONO-SAFE, WIDE, or OUT OF PHASE, which in mono cancels. On Reaper the loudness and
## the phase are not measured, and it says so; the peak is Reaper's master meter.
##
## It reads only while someone is near enough to read it (`wanted`): the meters it needs (the
## stage meters for the gain reduction, the loudness) cost the engine work, so they are asked for
## (DAWBackend.want_signal_meters, want_loudness) only then. Nothing is made while it runs: its
## bars are one bank, its letters a pool laid out at the build, their texts set only when they change.
##
## Its frame: the origin is the floor under the board's middle, +Y up, +Z out of its face. The
## board is laid out in the metres below and drawn FACE times over (`_face`), so a wall's worth: every
## measure here is the board's own, and `room_*` turns one into the room's.

## The board drawn this many times its own measures, to fill a wall read from the seat 5 m off.
const FACE := 1.3
## The board, and where on it the scale is (board metres).
const WIDE := 2.3
const BOTTOM := 0.42
const TALL := 1.5
const BORDER := 0.04
## The board's edge either side, the lettered margin left of the columns, the columns' share and
## the master's.
const EDGE := 0.05
const MARGIN := 0.15
const COLUMNS_WIDE := 1.2
const MASTER_WIDE := 0.85
## A column's pitch, least and most (m).
const PITCH := Vector2(0.075, 0.12)
## The strips under and over the scale: names under, numbers over.
const NAME_STRIP := 0.22
const NUMBER_STRIP := 0.07
## The scale, as the bay's meters and the pipes (SignalGraph.FLOOR_DB to TOP_DB).
const FLOOR_DB := SignalGraph.FLOOR_DB
const TOP_DB := SignalGraph.TOP_DB
const LINES_DB := [-18.0, -6.0, 0.0]
## A column falls this fast after a peak (dB/s); its peak holds this long (ms).
const FALL_DB := 24.0
const HOLD_MSEC := 1500
const METER_HZ := 30.0
const WORDS_HZ := 10.0
const CALM_HZ := 1.0
## dB a wheel notch on a column, and Shift's.
const STEP_DB := 0.5
const FINE_DB := 0.1
## The loudness targets, in the order the key steps through them.
const TARGETS := [["STREAMING", -14.0], ["CLUB", -8.0], ["BROADCAST", -23.0], ["CUSTOM", -16.0]]
## On target within this (LU).
const ON_TARGET := 1.0
## The master's loudness bar: from here to here (LUFS).
const LUFS_LOW := -40.0
const LUFS_HIGH := 0.0
## The master's peak and phase bars, this far down from the board's top (m).
const PEAK_ROW := 0.62
const PHASE_ROW := 0.84
## Under this correlation a mono sum loses something; under OUT_OF_PHASE it cancels.
const WIDE_UNDER := 0.5
const OUT_OF_PHASE := -0.3
## Read only while someone stands within this of it and faces it (m).
const READ_REACH := 7.0
const PIXEL := 0.0004
const NAME_CAP := 0.046
const NUMBER_CAP := 0.036
const LINE_CAP := 0.032
const MASTER_CAP := 0.04
const BIG_CAP := 0.06
const AMBER := Color(1.0, 0.64, 0.16)
const RED := Color(1.0, 0.16, 0.1)
const INK := Color(0.92, 0.92, 0.88)
const DIM := Color(0.6, 0.62, 0.66)
const GR_INK := Color(0.45, 0.68, 1.0)
## Where the plaque's top is in the niche, on the face of the sill under the board (room metres).
const PLAQUE_TOP := 0.35

## () -> float, Ergonomics.motion_scale: at 0 the columns move once a second.
var motion: Callable = func() -> float: return 1.0
## () -> bool: whether anyone here is reading the wall now. Unset, whenever this view's camera is
## within READ_REACH of it and turned toward it.
var wanted: Callable = Callable()
## The surface handle's size (SurfaceHandle.reposition): it is read from the seat five metres off.
var handle_scale := 1.7
## At the board's left end: its right is behind the timeline's shoulder from the seat.
var handle_left := true
## The target chosen (an index into TARGETS) and CUSTOM's level. This player's, not the room's.
var target := 0
var custom_db := -16.0
## The first track shown, and how many show.
var first := 0
var shown_count := 0

var columns: Array[Column] = []
## What the board is built in: this node, FACE times over.
var _face: Node3D
var _bank: MeshBank
var _names: Array[Label3D] = []
var _numbers: Array[Label3D] = []
var _grs: Array[Label3D] = []
var _foot: Label3D
var _short: Label3D
var _integrated: Label3D
var _verdict: Label3D
var _peak: Label3D
var _phase: Label3D
var _target_words: Label3D
var _say: Label3D
var _target_key: TargetKey
var _reset_key: EqWall.WallKey
var _left_key: EqWall.WallKey
var _right_key: EqWall.WallKey
var _names_strip: NameStrip
var _pitch := 0.1
## A track's column as shown, by track: [shown dB, held dB, held until msec].
var _level := {}
var _meter_clock := 0.0
var _words_clock := 0.0
var _calm_clock := 0.0
## How many slots the columns take in the bank, and where the master's start.
var _master_slot := 0
## For the suite: the texts the master shows.
var short_words := ""
var integrated_words := ""
var verdict_words := ""
var peak_words := ""
var phase_words := ""


func _ready() -> void:
	surface_kind = &"levels"
	if surface_id == &"":
		surface_id = &"levels"
	# A place, 2 m wide: visited, or brought on its own, and never parked in the arc.
	parks = false
	super()
	DAW.track_changed.connect(func(_i: int, field: StringName) -> void:
		if field == &"name" or field == &"colour":
			_words_clock = 1000.0)
	DAW.project_replaced.connect(mark_dirty)


func _process(delta: float) -> void:
	super(delta)
	if _bank == null:
		return
	var reading := is_visible_in_tree() and (bool(wanted.call()) if wanted.is_valid() else looked_at())
	if not reading:
		return
	DAW.backend.want_signal_meters()
	DAW.backend.want_loudness()
	if columns.size() != _shown_for(DAW.state.track_indices().size()):
		mark_dirty()
		return
	_meter_clock += delta
	_words_clock += delta
	var calm := float(motion.call()) <= 0.0
	if calm:
		_calm_clock += delta
		if _calm_clock < 1.0 / CALM_HZ:
			return
		_calm_clock = 0.0
	if _meter_clock >= 1.0 / METER_HZ or calm:
		read(minf(_meter_clock, 0.1) if not calm else 0.0)
		_meter_clock = 0.0


## Whether this view's camera is near enough to read the wall and turned toward it.
func looked_at() -> bool:
	var eye := get_viewport().get_camera_3d() if is_inside_tree() else null
	if eye == null:
		return false
	var to := global_position + global_basis.y * room_y(BOTTOM + TALL * 0.5) - eye.global_position
	return to.length() < READ_REACH and to.dot(-eye.global_basis.z) > 0.0


# --- the arithmetic of the wall ---------------------------------------------------------------

## A height on the board (board metres) as a height in the room.
static func room_y(board_y: float) -> float:
	return board_y * FACE


## The scale's foot and its height (m).
static func scale_foot() -> float:
	return BOTTOM + NAME_STRIP


static func scale_tall() -> float:
	return TALL - NAME_STRIP - NUMBER_STRIP


## How high up the board `db` dBFS is (m from the floor).
static func y_of(db: float) -> float:
	var share := clampf((db - FLOOR_DB) / (TOP_DB - FLOOR_DB), 0.0, 1.0) if is_finite(db) else 0.0
	return scale_foot() + scale_tall() * share


## How many decibels a metre of the scale is.
static func db_per_m() -> float:
	return (TOP_DB - FLOOR_DB) / scale_tall()


## The columns' left edge, and the master section's. The master on the left, the columns on the
## right with their dBFS lettered in the MARGIN between: from the seat the board's right is behind
## the timeline's shoulder, and what is read most while playing is the master's loudness.
static func columns_left() -> float:
	return WIDE * 0.5 - EDGE - COLUMNS_WIDE


static func master_left() -> float:
	return -WIDE * 0.5 + EDGE


## How many columns show for `tracks` tracks: all of them, down to PITCH.x apart, and past that
## the window scrolls.
static func _shown_for(tracks: int) -> int:
	return mini(tracks, floori(COLUMNS_WIDE / PITCH.x + 0.0001))


## The target's level (LUFS) and name: "STREAMING −14".
func target_db() -> float:
	return custom_db if TARGETS[target][0] == "CUSTOM" else float(TARGETS[target][1])


func target_name() -> String:
	return "%s %s" % [TARGETS[target][0], _signed(target_db(), 0 if TARGETS[target][0] != "CUSTOM" else 1)]


static func _signed(v: float, places := 1) -> String:
	if not is_finite(v):
		return "−∞"
	var f := ("%." + str(places) + "f") % absf(v)
	return ("−" if v < 0.0 and f.to_float() != 0.0 else ("+" if v > 0.0 and f.to_float() != 0.0 else "")) + f


## The loudness against the target, in words: "+1.2 LU OVER STREAMING −14", "ON TARGET",
## "3.4 LU UNDER". "" with nothing measured.
static func verdict(lufs: float, against: float, called: String) -> String:
	if not is_finite(lufs):
		return "NOTHING PLAYING: no loudness to read yet"
	var by := lufs - against
	if absf(by) <= ON_TARGET:
		return "ON TARGET: %s LU from %s" % [_signed(by), called]
	if by > 0.0:
		return "%s LU OVER %s" % [_signed(by), called]
	return "%.1f LU UNDER %s" % [-by, called]


## The phase in words: MONO-SAFE, WIDE, OUT OF PHASE.
static func phase_verdict(correlation: float) -> String:
	if is_nan(correlation):
		return "PHASE: no signal"
	if correlation < OUT_OF_PHASE:
		return "PHASE %s · OUT OF PHASE: in mono it cancels" % _signed(correlation, 2)
	if correlation < WIDE_UNDER:
		return "PHASE %s · WIDE: check it in mono" % _signed(correlation, 2)
	return "PHASE %s · MONO-SAFE" % _signed(correlation, 2)


## A track's deepest gain reduction (dB, 0 or less), NAN where nothing reports one.
static func gain_reduction(t: MixState.TrackState) -> float:
	var most := NAN
	for g in t.meter_gr:
		if not is_nan(g):
			most = g if is_nan(most) else minf(most, g)
	return most


## A track as the wall names it: "2 KICK".
static func title_of(track: int) -> String:
	var t := DAW.state.track(track, false) if DAW.state != null else null
	return "%d %s" % [DAW.state.bank_offset + track, (t.display_name() if t != null else "Track %d" % track).to_upper()]


# --- building ---------------------------------------------------------------------------------

func _rebuild() -> void:
	_clear_built()
	_face = null
	var face := Node3D.new()
	face.name = "Face"
	face.scale = Vector3.ONE * FACE
	_adopt(face)
	_face = face
	columns.clear()
	_names.clear()
	_numbers.clear()
	_grs.clear()
	_level.clear()
	var tracks := DAW.state.track_indices().size()
	shown_count = _shown_for(tracks)
	first = clampi(first, 0, maxi(tracks - shown_count, 0))
	_pitch = clampf(COLUMNS_WIDE / maxf(shown_count, 1), PITCH.x, PITCH.y)

	var plate := MeshInstance3D.new()
	plate.name = "Board"
	var box := BoxMesh.new()
	box.size = Vector3(WIDE + BORDER * 2.0, TALL + BORDER * 2.0 + 0.14, 0.03)
	plate.mesh = box
	plate.position = Vector3(0, BOTTOM + TALL * 0.5 - 0.03, -0.016)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.05, 0.055, 0.068)
	paint.roughness = 0.92
	plate.material_override = paint
	_adopt(plate)

	_bank = MeshBank.strips()
	_bank.name = "Bars"
	_bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Five slots a column (ground, level, held tick, gain reduction, fader notch), the lines, and the
	# master's: its loudness bar's ground, fill and target band, its peak's ground and fill, the
	# phase's ground and needle.
	for i in shown_count * 5 + LINES_DB.size() + 7:
		_bank.claim(PinMatrix._hidden(), Color.BLACK)
	_adopt(_bank)
	_bank.commit()
	_master_slot = shown_count * 5 + LINES_DB.size()

	var x0 := columns_left()
	for n in LINES_DB.size():
		var db: float = LINES_DB[n]
		var slot := shown_count * 5 + n
		_bank.move_slot(slot, Transform3D(Basis.from_scale(Vector3(COLUMNS_WIDE, 0.003, 0.0006)),
				Vector3(x0 + COLUMNS_WIDE * 0.5, y_of(db), 0.003)))
		_bank.set_colour(slot, (RED if db == 0.0 else (AMBER if db == -6.0 else Color(0.55, 0.6, 0.68))) * 0.9)
		var mark := _label("%s dBFS" % _signed(db, 0) if db != 0.0 else "0 dBFS", LINE_CAP, DIM)
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mark.position = Vector3(x0 - 0.01, y_of(db), 0.002)
		Lettering.fit(mark, MARGIN - 0.015, mark.font_size, 12)
		_adopt(mark)

	for n in shown_count:
		var c := Column.new()
		c.wall = self
		c.slot = n
		c.name = "Column%d" % n
		c.position = Vector3(x0 + (n + 0.5) * _pitch, scale_foot() + scale_tall() * 0.5, 0.0)
		c.size = Vector2(_pitch * 0.9, scale_tall())
		_adopt(c)
		columns.append(c)
		var name_label := _label("", NAME_CAP, INK)
		# Up the column, read bottom to top, so a name has the strip's height and not a column's width.
		name_label.rotation.z = PI * 0.5
		name_label.position = Vector3(c.position.x, BOTTOM + NAME_STRIP * 0.5, 0.004)
		_adopt(name_label)
		_names.append(name_label)
		var number := _label("", NUMBER_CAP, INK)
		number.position = Vector3(c.position.x, scale_foot() + scale_tall() + NUMBER_STRIP * 0.5, 0.004)
		_adopt(number)
		_numbers.append(number)
		var gr := _label("", NAME_CAP * 0.85, GR_INK)
		gr.visible = false
		_adopt(gr)
		_grs.append(gr)
	_names_strip = NameStrip.new()
	_names_strip.wall = self
	_names_strip.name = "Names"
	_names_strip.position = Vector3(x0 + COLUMNS_WIDE * 0.5, BOTTOM + NAME_STRIP * 0.5, 0.0)
	_names_strip.size = Vector2(COLUMNS_WIDE, NAME_STRIP)
	_adopt(_names_strip)

	var title := _label("LEVELS", 0.05, Color(0.95, 0.86, 0.62))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector3(-WIDE * 0.5 + 0.02, BOTTOM + TALL + 0.05, 0.002)
	_adopt(title)
	var how := _label("EACH TRACK AFTER ITS FADER · DRAG A COLUMN FOR ITS GAIN · GR PUSHES IT DOWN FROM THE TOP", 0.026, DIM)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Over the columns it is about.
	how.position = Vector3(columns_left(), BOTTOM + TALL + 0.05, 0.002)
	Lettering.fit(how, COLUMNS_WIDE, how.font_size, 12)
	_adopt(how)
	_foot = _left_label(Vector3(x0, BOTTOM - 0.03, 0.002), 0.03, DIM, COLUMNS_WIDE - 0.27)
	if tracks > shown_count:
		_left_key = _key("◀", "the tracks before these", Vector2(0.08, 0.05), Vector3(x0 + COLUMNS_WIDE - 0.2, BOTTOM - 0.03, 0.0), "EARLIER TRACKS")
		_left_key.pressed.connect(func() -> void: scroll_by(-(shown_count - 1)))
		_right_key = _key("▶", "the tracks after these", Vector2(0.08, 0.05), Vector3(x0 + COLUMNS_WIDE - 0.1, BOTTOM - 0.03, 0.0), "LATER TRACKS")
		_right_key.pressed.connect(func() -> void: scroll_by(shown_count - 1))
	else:
		_left_key = null
		_right_key = null
	_build_master()
	_level.clear()
	_words_clock = 1000.0
	read(0.0)


func _build_master() -> void:
	var mx := master_left()
	var top := BOTTOM + TALL
	var head := _label("MASTER", MASTER_CAP, Color(0.95, 0.86, 0.62))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.position = Vector3(mx, top - 0.03, 0.003)
	_adopt(head)
	# Every line one line, as wide as the section and no wider (`_say_in` fits each as its words
	# change): wrapped, the verdict grew down into the keys and the integrated line ran off the board.
	_short = _left_label(Vector3(mx, top - 0.11, 0.003), BIG_CAP, INK, MASTER_WIDE)
	_integrated = _left_label(Vector3(mx, top - 0.19, 0.003), MASTER_CAP * 0.8, INK, MASTER_WIDE)
	_target_words = _left_label(Vector3(mx + 0.19, top - 0.25, 0.003), MASTER_CAP * 0.72, INK, MASTER_WIDE - 0.19 - 0.17)
	_verdict = _left_label(Vector3(mx, top - 0.325, 0.003), MASTER_CAP * 0.8, INK, MASTER_WIDE)
	_peak = _left_label(Vector3(mx, top - PEAK_ROW + 0.07, 0.003), MASTER_CAP * 0.85, INK, MASTER_WIDE)
	_phase = _left_label(Vector3(mx, top - PHASE_ROW + 0.07, 0.003), MASTER_CAP * 0.8, INK, MASTER_WIDE)
	_say = _left_label(Vector3(mx, top - PHASE_ROW - 0.15, 0.003), MASTER_CAP * 0.62, DIM)
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.width = MASTER_WIDE / PIXEL
	_say.text = "LOUDNESS: ITU-R BS.1770, K-weighted and gated, on the master · short-term 3 s, momentary 0.4 s, integrated since play or RESET · true peak 4x oversampled, approximate"
	_target_key = TargetKey.new()
	_target_key.name = "Target"
	_target_key.wall = self
	_target_key.legend = "TARGET"
	_target_key.says = "press for the next target: streaming −14, club −8, broadcast −23, custom · wheel over it to set custom"
	_target_key.size = Vector2(0.17, 0.06)
	_target_key.position = Vector3(mx + 0.085, top - 0.25, 0.0)
	_target_key.pressed.connect(step_target)
	_adopt(_target_key)
	_reset_key = _key("RESET", "press to start the integrated loudness and the held true peak again", Vector2(0.15, 0.06),
			Vector3(mx + MASTER_WIDE - 0.075, top - 0.25, 0.0))
	_reset_key.pressed.connect(DAW.reset_loudness)
	# The loudness bar, across, under the verdict; the peak and the phase bars under their words.
	var bar_y := top - 0.42
	var slot := _master_slot
	_bank.move_slot(slot, Transform3D(Basis.from_scale(Vector3(MASTER_WIDE, 0.05, 0.0006)), Vector3(mx + MASTER_WIDE * 0.5, bar_y, 0.003)))
	_bank.set_colour(slot, Color(0.03, 0.032, 0.036))
	_bank.move_slot(slot + 3, Transform3D(Basis.from_scale(Vector3(MASTER_WIDE, 0.022, 0.0006)), Vector3(mx + MASTER_WIDE * 0.5, top - PEAK_ROW, 0.003)))
	_bank.set_colour(slot + 3, Color(0.03, 0.032, 0.036))
	_bank.move_slot(slot + 5, Transform3D(Basis.from_scale(Vector3(MASTER_WIDE, 0.022, 0.0006)), Vector3(mx + MASTER_WIDE * 0.5, top - PHASE_ROW, 0.003)))
	_bank.set_colour(slot + 5, Color(0.03, 0.032, 0.036))
	for n in 5:
		var at := float(n) / 4.0
		var tick := _label(["−1", "−0.5", "0", "+0.5", "+1"][n], MASTER_CAP * 0.65, DIM)
		tick.position = Vector3(mx + MASTER_WIDE * at, top - PHASE_ROW - 0.042, 0.003)
		_adopt(tick)
	for n in 5:
		var lufs := lerpf(LUFS_LOW, LUFS_HIGH, float(n) / 4.0)
		var tick := _label(_signed(lufs, 0), MASTER_CAP * 0.65, DIM)
		tick.position = Vector3(mx + MASTER_WIDE * float(n) / 4.0, bar_y - 0.052, 0.003)
		_adopt(tick)


func _label(words: String, cap: float, colour: Color) -> Label3D:
	var l := Label3D.new()
	l.text = words
	l.pixel_size = PIXEL
	l.font_size = roundi(cap / PIXEL)
	l.modulate = colour
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.render_priority = 2
	Lettering.range_to_legibility(l)
	return l


## A line lettered from its left end at `at`; given a `room`, kept within it (`_say_in`).
func _left_label(at: Vector3, cap: float, colour: Color, room := 0.0) -> Label3D:
	var l := _label("", cap, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = at
	if room > 0.0:
		l.set_meta(&"room", room)
		l.set_meta(&"cap", l.font_size)
	_adopt(l)
	return l


## Built into the board, which is FACE times over.
func _adopt(node: Node) -> void:
	if _face != null and node != _face:
		node.set_meta("built", true)
		_face.add_child(node)
	else:
		super(node)


func _key(legend: String, says: String, size: Vector2, at: Vector3, called := "") -> EqWall.WallKey:
	var key := EqWall.WallKey.new()
	var title := "LEVELS  %s" % (called if called != "" else legend)
	key.name = (called if called != "" else legend).capitalize().replace(" ", "")
	key.describe_title = func() -> String: return title
	key.legend = legend
	key.says = says
	key.size = size
	key.position = at
	_adopt(key)
	return key


# --- reading ----------------------------------------------------------------------------------

## The track shown in column `n`, 0 for none.
func track_at(n: int) -> int:
	var order := DAW.state.track_indices()
	return order[first + n] if n >= 0 and first + n < order.size() else 0


## The column showing `track`, or null when the window is elsewhere.
func column_of(track: int) -> Column:
	for c in columns:
		if track_at(c.slot) == track:
			return c
	return null


## Every column and the master read now, `delta` after the last reading.
func read(delta: float) -> void:
	if _bank == null:
		return
	var now := Time.get_ticks_msec()
	var words := _words_clock >= 1.0 / WORDS_HZ
	if words:
		_words_clock = 0.0
	for c in columns:
		_read_column(c, delta, now, words)
	_read_master(words)
	if words:
		var total := DAW.state.track_indices().size()
		var said := "TRACKS %d-%d OF %d · drag or wheel the names to scroll" % [first + 1, first + shown_count, total] \
				if total > shown_count else "%d TRACKS" % total
		_say_in(_foot, said)


func _read_column(c: Column, delta: float, now: int, words: bool) -> void:
	var k := c.slot * 5
	var track := track_at(c.slot)
	var t := DAW.state.track(track, false) if track > 0 else null
	if t == null:
		for i in 5:
			_bank.move_slot(k + i, PinMatrix._hidden())
		c.track = 0
		return
	c.track = track
	var peak := SignalGraph.fader_level(t).x
	var st: Array = _level.get(track, [])
	if st.is_empty():
		st = [-INF, -INF, 0]
		_level[track] = st
	var shown: float = st[0]
	shown = peak if peak >= shown or not is_finite(shown) or delta <= 0.0 else maxf(peak, shown - FALL_DB * delta)
	if c.is_held() and not is_nan(c.held_db):
		shown = c.held_db
	st[0] = shown
	if peak >= float(st[1]) or now > int(st[2]):
		st[1] = peak
		st[2] = now + HOLD_MSEC
	var x := c.position.x
	var wide := _pitch * 0.62
	var foot := scale_foot()
	# The track's own colour, deepened and lit so a column is that track at a glance and not one more
	# white bar: the chips' pastel reads as white once it glows.
	var tint := Materials.chip_colour(t.shown_colour())
	tint.s = maxf(tint.s, 0.6)
	tint.v = maxf(tint.v, 0.85)
	var health := SignalGraph.health(shown)
	var ink := tint
	if health == &"clip":
		ink = RED * 1.5
	elif health == &"hot":
		ink = AMBER * 1.3
	_bank.move_slot(k, Transform3D(Basis.from_scale(Vector3(wide, scale_tall(), 0.0006)), Vector3(x, foot + scale_tall() * 0.5, 0.002)))
	_bank.set_colour(k, Color(0.025, 0.027, 0.03))
	var top := y_of(shown)
	if top - foot > 0.001:
		_bank.move_slot(k + 1, Transform3D(Basis.from_scale(Vector3(wide * 0.9, top - foot, 0.0006)), Vector3(x, (top + foot) * 0.5, 0.004)))
		_bank.set_colour(k + 1, ink)
	else:
		_bank.move_slot(k + 1, PinMatrix._hidden())
	var held: float = st[1]
	if is_finite(held) and held > FLOOR_DB:
		_bank.move_slot(k + 2, Transform3D(Basis.from_scale(Vector3(wide, 0.006, 0.0006)), Vector3(x, y_of(held), 0.005)))
		_bank.set_colour(k + 2, RED * 1.8 if held > SignalGraph.CLIP_DB else Color(1.0, 0.97, 0.9) * 1.4)
	else:
		_bank.move_slot(k + 2, PinMatrix._hidden())
	# The gain reduction, hanging from the top of the scale, pushing the column down.
	var gr := gain_reduction(t)
	var gr_label := _grs[c.slot]
	if not is_nan(gr) and gr < -0.05:
		var long := -gr / db_per_m()
		var roof := foot + scale_tall()
		_bank.move_slot(k + 3, Transform3D(Basis.from_scale(Vector3(wide * 0.9, long, 0.0006)), Vector3(x, roof - long * 0.5, 0.006)))
		_bank.set_colour(k + 3, GR_INK * 1.2)
		if words:
			var said := "GR %s" % _signed(gr)
			if gr_label.text != said:
				gr_label.text = said
			gr_label.visible = true
			gr_label.position = Vector3(x, roof - long - 0.02, 0.007)
	else:
		_bank.move_slot(k + 3, PinMatrix._hidden())
		if gr_label.visible:
			gr_label.visible = false
	# The fader's setting, as a notch on the column's right side.
	var fader := FaderLaw.to_db(t.volume) if t.volume > 0.0 else -INF
	_bank.move_slot(k + 4, Transform3D(Basis.from_scale(Vector3(_pitch * 0.16, 0.01, 0.0006)),
			Vector3(x + wide * 0.5 + _pitch * 0.08, y_of(fader if is_finite(fader) else FLOOR_DB), 0.005)))
	_bank.set_colour(k + 4, Color(0.85, 0.86, 0.9) * (1.2 if c.is_held() else 0.8))
	if words:
		var name := title_of(track)
		if _names[c.slot].text != name:
			_names[c.slot].text = name
			Lettering.fit(_names[c.slot], NAME_STRIP * 0.94, roundi(minf(NAME_CAP, _pitch * 0.62) / PIXEL), 10)
		var number := _signed(held) if is_finite(held) and held > FLOOR_DB else "−∞"
		if _numbers[c.slot].text != number:
			_numbers[c.slot].text = number
			Lettering.fit(_numbers[c.slot], _pitch * 0.95, roundi(NUMBER_CAP / PIXEL), 10)
		_numbers[c.slot].modulate = RED.lightened(0.3) if held > SignalGraph.CLIP_DB else (AMBER if held >= SignalGraph.HOT_DB else INK)


func _read_master(words: bool) -> void:
	var m := DAW.state.master
	var mx := master_left()
	var top := BOTTOM + TALL
	var slot := _master_slot
	var measured := m.loudness_measured
	var lufs := m.lufs_s if measured else -INF
	var share := clampf((lufs - LUFS_LOW) / (LUFS_HIGH - LUFS_LOW), 0.0, 1.0) if is_finite(lufs) else 0.0
	var bar_y := top - 0.42
	var over := lufs - target_db()
	var ink := Color(0.6, 0.85, 0.65) * 1.2
	if is_finite(over) and over > ON_TARGET:
		ink = AMBER * 1.3 if over < 3.0 else RED * 1.4
	if share > 0.001:
		_bank.move_slot(slot + 1, Transform3D(Basis.from_scale(Vector3(MASTER_WIDE * share, 0.04, 0.0006)),
				Vector3(mx + MASTER_WIDE * share * 0.5, bar_y, 0.004)))
		_bank.set_colour(slot + 1, ink)
	else:
		_bank.move_slot(slot + 1, PinMatrix._hidden())
	var at := clampf((target_db() - LUFS_LOW) / (LUFS_HIGH - LUFS_LOW), 0.0, 1.0)
	_bank.move_slot(slot + 2, Transform3D(Basis.from_scale(Vector3(0.006, 0.075, 0.0006)), Vector3(mx + MASTER_WIDE * at, bar_y, 0.006)))
	_bank.set_colour(slot + 2, Color(1, 1, 1) * 1.6)
	# The peak: the true-ish peak measured, else the master's meter.
	var peak := m.true_peak_recent_db if measured else FaderLaw.to_db(maxf(m.vu_l, m.vu_r))
	var pshare := clampf((peak - FLOOR_DB) / (TOP_DB - FLOOR_DB), 0.0, 1.0) if is_finite(peak) else 0.0
	if pshare > 0.001:
		_bank.move_slot(slot + 4, Transform3D(Basis.from_scale(Vector3(MASTER_WIDE * pshare, 0.018, 0.0006)),
				Vector3(mx + MASTER_WIDE * pshare * 0.5, top - PEAK_ROW, 0.004)))
		_bank.set_colour(slot + 4, RED * 1.5 if peak > 0.0 else (AMBER * 1.3 if peak > -1.0 else Color(0.85, 0.86, 0.9)))
	else:
		_bank.move_slot(slot + 4, PinMatrix._hidden())
	# The phase: a needle from −1 (left end) to +1 (right).
	var corr := m.correlation if measured else NAN
	if not is_nan(corr):
		_bank.move_slot(slot + 6, Transform3D(Basis.from_scale(Vector3(0.008, 0.04, 0.0006)),
				Vector3(mx + MASTER_WIDE * (corr + 1.0) * 0.5, top - PHASE_ROW, 0.005)))
		_bank.set_colour(slot + 6, RED * 1.6 if corr < OUT_OF_PHASE else (AMBER * 1.3 if corr < WIDE_UNDER else Color(0.6, 0.85, 0.65) * 1.3))
	else:
		_bank.move_slot(slot + 6, PinMatrix._hidden())
	if not words:
		return
	if measured:
		short_words = "SHORT-TERM %s" % LoudnessMeter.words(m.lufs_s)
		integrated_words = "INTEGRATED %s · MOMENTARY %s · %d:%02d" % [LoudnessMeter.words(m.lufs_i),
				LoudnessMeter.words(m.lufs_m), int(m.loudness_seconds) / 60, int(m.loudness_seconds) % 60]
		verdict_words = verdict(m.lufs_s, target_db(), target_name())
		var tp := m.true_peak_recent_db
		peak_words = "TRUE PEAK ≈ %s dBTP (most %s) %s" % [_signed(tp), _signed(m.true_peak_db),
				"· OVER 0: IT CLIPS" if tp > 0.0 else ("· HOT: under 1 dB of headroom" if tp > -1.0 else "")]
		phase_words = phase_verdict(m.correlation)
	else:
		var reaper := DAW.backend is ReaperBackend
		var can := DAW.backend.measures_loudness()
		short_words = "LOUDNESS NOT MEASURED"
		integrated_words = "Reaper does not report loudness to dawlings: put a loudness meter on its master" if reaper \
				else ("measuring: it starts with the song" if can else "this engine makes no sound to measure (the built-in engine does)")
		verdict_words = ""
		var vu := FaderLaw.to_db(maxf(m.vu_l, m.vu_r))
		peak_words = "PEAK %s (the master's meter, not a true peak)%s" % [SignalGraph.db_words(vu), " · OVER 0: IT CLIPS" if vu > 0.0 else ""]
		phase_words = "PHASE: not measured" + (" on Reaper" if reaper else "")
	_say_in(_short, short_words)
	_say_in(_integrated, integrated_words)
	_say_in(_verdict, verdict_words)
	_verdict.modulate = INK if not (measured and is_finite(over) and over > ON_TARGET) else (AMBER if over < 3.0 else RED.lightened(0.3))
	_say_in(_peak, peak_words)
	_peak.modulate = RED.lightened(0.3) if measured and m.true_peak_recent_db > 0.0 else (AMBER if measured and m.true_peak_recent_db > -1.0 else INK)
	_say_in(_phase, phase_words)
	_phase.modulate = RED.lightened(0.3) if measured and not is_nan(corr) and corr < OUT_OF_PHASE else INK
	_say_in(_target_words, target_name())


func _say_in(label: Label3D, words: String) -> void:
	if label != null and label.text != words:
		label.text = words
		if label.has_meta(&"room"):
			Lettering.fit(label, float(label.get_meta(&"room")), int(label.get_meta(&"cap")), 12)


# --- what the keys and the columns do ---------------------------------------------------------

func step_target() -> void:
	target = (target + 1) % TARGETS.size()
	_words_clock = 1000.0
	read(0.0)


## The wheel over TARGET: CUSTOM's level, 0.5 LU a notch (the key goes to CUSTOM first).
func nudge_target(notches: int, fine: bool) -> bool:
	if TARGETS[target][0] != "CUSTOM":
		target = TARGETS.size() - 1
	custom_db = clampf(custom_db + notches * (0.1 if fine else 0.5), -40.0, 0.0)
	_words_clock = 1000.0
	read(0.0)
	return true


## The window `by` tracks along; whether it moved.
func scroll_by(by: int) -> bool:
	var total := DAW.state.track_indices().size()
	var to := clampi(first + by, 0, maxi(total - shown_count, 0))
	if to == first:
		return false
	first = to
	_level.clear()
	_words_clock = 1000.0
	read(0.0)
	return true


func _column_begin(c: Column, at: Vector3) -> void:
	var t := DAW.state.track(c.track, false)
	c._start = _face.to_local(at)
	c._from = FaderLaw.to_db(t.volume) if t != null and t.volume > 0.0 else -61.0
	c._shown_from = float((_level.get(c.track, [-INF]) as Array)[0])
	if not is_finite(c._shown_from):
		c._shown_from = FLOOR_DB
	c._last = c._from


func _column_move(c: Column, at: Vector3) -> void:
	if c.track <= 0:
		return
	var d := _face.to_local(at) - c._start
	var by := d.y * db_per_m()
	var hand := c.held_by as Interactor
	if hand != null and hand.fine():
		by *= 0.1
	var want := clampf(snappedf(c._from + by, 0.1), -61.0, 12.0)
	if is_equal_approx(want, c._last):
		return
	c._last = want
	DAW.set_track_volume(c.track, 0.0 if want < -60.0 else FaderLaw.to_taper(want))
	c.held_db = c._shown_from + (maxf(want, -60.0) - maxf(c._from, -60.0))


func _column_nudge(c: Column, notches: int, fine: bool) -> bool:
	var t := DAW.state.track(c.track, false)
	if t == null:
		return false
	var db := maxf(FaderLaw.to_db(t.volume) if t.volume > 0.0 else -61.0, -61.0) + notches * (FINE_DB if fine else STEP_DB)
	DAW.set_track_volume(c.track, 0.0 if db < -60.0 else FaderLaw.to_taper(minf(db, 12.0)))
	return true


## A column's card: "2 KICK · fader −3.0 dB · peak −6.2 dBFS · GR −4.1 dB".
func describe(c: Column) -> PackedStringArray:
	var t := DAW.state.track(c.track, false)
	if t == null:
		return PackedStringArray(["LEVELS", "no track here", ""])
	var st: Array = _level.get(c.track, [-INF, -INF, 0])
	var parts := PackedStringArray()
	parts.append("fader %s" % ("−∞ dB" if t.volume <= 0.0 else "%s dB" % _signed(FaderLaw.to_db(t.volume))))
	parts.append("peak %s" % SignalGraph.db_words(float(st[1])))
	var level := SignalGraph.fader_level(t)
	if is_finite(level.y):
		parts.append("RMS %s" % SignalGraph.db_words(level.y))
	var gr := gain_reduction(t)
	if not is_nan(gr) and gr < -0.05:
		parts.append("GR %s dB, pushing it down" % _signed(gr))
	if float(st[1]) > SignalGraph.CLIP_DB:
		parts.append("CLIPPING")
	return PackedStringArray([title_of(c.track), " · ".join(parts),
			"drag up or down for its gain (its fader), one undo step · wheel 0.5 dB, Shift 0.1"])


## A column of the wall: the box a hand or a cursor takes hold of to move the track's fader.
class Column extends ControlAffordance:
	var wall: LevelsWall
	var slot := 0
	var track := 0
	var size := Vector2(0.1, 1.0)
	## The level the column shows while held (dBFS), NAN when it follows the track.
	var held_db := NAN
	var _start := Vector3.ZERO
	var _from := 0.0
	var _shown_from := 0.0
	var _last := 0.0

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		edits_as_one = true
		describe_edit = func() -> String:
			var t := DAW.state.track(track, false)
			return "%s: gain (LEVELS)" % (t.display_name() if t != null else "track")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.02)
		shape.shape = box
		shape.position.z = 0.01
		add_child(shape)

	func _on_grab_begin(at: Vector3) -> void:
		wall._column_begin(self, at)

	func _on_grab_move(at: Vector3) -> void:
		wall._column_move(self, at)

	func _on_grab_end() -> void:
		held_db = NAN

	func _on_nudge(notches: int, fine: bool) -> bool:
		return wall._column_nudge(self, notches, fine)

	func dwell_activates() -> bool:
		return false

	func _default_title() -> String:
		return wall.describe(self)[0]

	func _default_readout() -> String:
		return wall.describe(self)[1]

	func hint() -> String:
		return wall.describe(self)[2]


## The names under the columns: dragged or wheeled, the window scrolls along the tracks.
class NameStrip extends ControlAffordance:
	var wall: LevelsWall
	var size := Vector2(1.0, 0.08)
	var _start := 0.0
	var _from := 0

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, size.y, 0.02)
		shape.shape = box
		shape.position.z = 0.012
		add_child(shape)

	func _on_grab_begin(at: Vector3) -> void:
		_start = wall._face.to_local(at).x
		_from = wall.first

	func _on_grab_move(at: Vector3) -> void:
		var by := -roundi((wall._face.to_local(at).x - _start) / wall._pitch)
		wall.scroll_by(_from + by - wall.first)

	func _on_nudge(notches: int, _fine: bool) -> bool:
		return wall.scroll_by(-notches * 3)

	func personal() -> bool:
		return true

	func _default_title() -> String:
		return "LEVELS · TRACK NAMES"

	func _default_readout() -> String:
		return wall._foot.text if wall._foot != null else ""

	func hint() -> String:
		return "drag or wheel along the names to scroll the tracks"


## TARGET: a press for the next target, the wheel for CUSTOM's level.
class TargetKey extends EqWall.WallKey:
	var wall: LevelsWall

	func _on_nudge(notches: int, fine: bool) -> bool:
		return wall.nudge_target(notches, fine)

	func _default_title() -> String:
		return "LOUDNESS TARGET"

	func _default_readout() -> String:
		return wall.target_name()
