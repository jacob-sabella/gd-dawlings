class_name StageTable
extends Surface

## The stereo field as a stage (docs/spatial_loop.md slice 18, idea #1): a table on a trolley
## beside the desk, at desk height, with the tracks standing on it as voices (StageVoice). Across
## the table is pan, left to right as the player sees it; back from the front edge is level, +6 dB
## at the front edge and -40 dB at the back, linear in decibels, and past the back edge is -inf;
## the ring round a voice's foot is its width, 2 cm across for mono to 8 cm for full width.
##
## Its frame: the origin is the middle of the table top, +Y up, +Z toward the player. The front
## edge carries a sloped rail with a tag for each voice (its number and name, what it is set to,
## PAN < > keys and a RESET key), the bank keys at the left end and the SHOW key at the right.
##
## Banked like the console: it shows eight tracks at a time, paged within the cached bank and
## asking the DAW for another bank past its end (ConsoleSurface._go_to_track). Or it shows the
## soloed tracks, or the selected ones (SHOW).
##
## Every write goes through DAW, so a guest's placing is an intent the host carries out, and a
## placing is one edit (StageVoice.edits_as_one): pan, volume and the width the wheel set while it
## was held are one undo step.

## The top, across and deep (m), and how thick it is.
const SIZE := Vector2(1.2, 0.9)
const THICK := 0.04
## The levels the front and back edges stand for, and the decibel lines printed between.
const FRONT_DB := 6.0
const BACK_DB := -40.0
const LINES_DB := [6.0, 0.0, -6.0, -12.0, -20.0, -30.0, -40.0]
## How far either side of the middle hard left and hard right stand (m): short of the edge, so a
## hard-panned voice and its ring are on the table.
const HALF_PAN := 0.54
## Where a voice at -inf stands: on the lip behind the back edge.
const OFF_Z := -SIZE.y * 0.5 - 0.0175
## The ring's radius at no width and at full width (m).
const RING_MIN := 0.02
const RING_MAX := 0.08
## How near the middle a voice is put dead centre, unless fine (m).
const SNAP := 0.01
## Two presses without a drag this close together (s) put a track back: centre, 0 dB, full width.
const DOUBLE_PRESS := 0.35
## Tracks shown at once, and the steps the wheel and the keys take.
const PAGE := 8
const DB_STEP := 0.5
const DB_FINE := 0.1
const PAN_STEP := 0.005
const PAN_WHEEL := 0.025
const WIDTH_STEP := 0.05
const WIDTH_FINE := 0.01
## The rail along the front edge: how deep down its slope, and how far each end is kept for the
## bank keys and the SHOW key.
const RAIL_DEEP := 0.16
const RAIL_END := 0.13
## What SHOW steps through.
const SHOWS := [&"bank", &"soloed", &"selected"]

## What the table is showing: the bank (a page of it), the soloed tracks or the selected ones.
var showing := &"bank"
## Which page of the cached bank the table shows, as the index into its tracks of the first.
var view_offset := 0
## The voices standing on it and the tags for them, by track.
var voices := {}
var tags := {}

var _rail: Node3D
var _range_label: Label3D
var _show_label: Label3D
var _empty_label: Label3D
var _leads := {}
var _presses := {}
var _levels := {}
var _pending_view := -1


func _ready() -> void:
	surface_kind = &"stage"
	if surface_id == &"":
		surface_id = &"stage_table"
	# The top faces up, so on a monitor it is laid back most of the way, leaving the player
	# looking down onto it as they would standing at it.
	screen_pitch_degrees = 70.0
	super()
	DAW.track_changed.connect(_on_track_changed)
	DAW.bank_changed.connect(mark_dirty)
	DAW.project_replaced.connect(mark_dirty)
	_hook_pan_mode()


func _process(delta: float) -> void:
	super(delta)
	if _pending_view >= 0 and not _anything_held():
		var wanted := _pending_view
		_pending_view = -1
		_go_to(wanted)
	# Lit by its meter, which falls at its own pace (VUMeter decays the cache's peaks).
	for track in voices:
		var t := DAW.state.track(track, false)
		if t == null:
			continue
		var was: float = _levels.get(track, 0.0)
		var now := maxf(t.vu_l, t.vu_r)
		var level := now if now > was else lerpf(was, now, clampf(delta * 6.0, 0.0, 1.0))
		_levels[track] = level
		(voices[track] as StageVoice).glow(level)


# --- the arithmetic of the table ------------------------------------------------------------

## Where on the table a track at `pan` and `db` stands (the table's frame, at a voice's height).
static func spot_of(pan: float, db: float) -> Vector3:
	return Vector3((clampf(pan, 0.0, 1.0) - 0.5) * 2.0 * HALF_PAN, StageVoice.LIFT, z_of_db(db))


## How far toward the player (m) a level stands: the front edge at FRONT_DB, the back at BACK_DB,
## anything louder at the front edge and -inf on the lip behind the back.
static func z_of_db(db: float) -> float:
	if db == -INF or db < BACK_DB - 0.001:
		return OFF_Z
	var f := (clampf(db, BACK_DB, FRONT_DB) - BACK_DB) / (FRONT_DB - BACK_DB)
	return lerpf(-SIZE.y * 0.5, SIZE.y * 0.5, f)


## The level a place on the table stands for: -inf past the back edge.
static func db_of_z(z: float) -> float:
	if z < -SIZE.y * 0.5:
		return -INF
	var f := (minf(z, SIZE.y * 0.5) + SIZE.y * 0.5) / SIZE.y
	return lerpf(BACK_DB, FRONT_DB, f)


static func pan_of_x(x: float) -> float:
	return clampf(0.5 + x / (2.0 * HALF_PAN), 0.0, 1.0)


static func db_of_volume(taper: float) -> float:
	return FaderLaw.to_db(taper)


## The ring's radius for a width, and the width for a radius.
static func ring_of(width: float) -> float:
	return lerpf(RING_MIN, RING_MAX, clampf(width, 0.0, 1.0))


static func width_of(radius: float) -> float:
	return clampf((radius - RING_MIN) / (RING_MAX - RING_MIN), 0.0, 1.0)


## A track's number in the project, as the console and the timeline number it.
static func number_of(track: int) -> int:
	return DAW.state.bank_offset + track


## "pan 20 L", "pan C".
static func pan_words(pan: float) -> String:
	var off := roundi((pan - 0.5) * 200.0)
	if off == 0:
		return "pan C"
	return "pan %d %s" % [absi(off), "L" if off < 0 else "R"]


static func db_words(taper: float) -> String:
	var db := FaderLaw.to_db(taper)
	if db == -INF:
		return "-inf dB"
	return "%+.1f dB" % db if db > 0.05 else "%.1f dB" % db


# --- what it shows --------------------------------------------------------------------------

## The tracks on the table, in order: a page of the bank, or the soloed or selected tracks (at
## most a page of them).
func shown_tracks() -> Array:
	var indices := DAW.state.track_indices()
	if showing == &"bank":
		view_offset = clampi(view_offset, 0, maxi(0, indices.size() - 1))
		view_offset -= view_offset % PAGE
		return indices.slice(view_offset, mini(view_offset + PAGE, indices.size()))
	var out := []
	for i in indices:
		var t: MixState.TrackState = DAW.state.tracks[i]
		if (t.solo if showing == &"soloed" else t.selected):
			out.append(i)
			if out.size() == PAGE:
				break
	return out


## "9-16 OF 40": which tracks the bank keys have the table on.
func range_text() -> String:
	var shown := shown_tracks() if showing == &"bank" else DAW.state.track_indices().slice(view_offset, view_offset + PAGE)
	if shown.is_empty():
		return "NO TRACKS"
	var total := DAW.state.project_track_count
	if total <= 0:
		total = DAW.state.bank_offset + DAW.state.tracks.size()
	return "%d-%d OF %d" % [number_of(shown[0]), number_of(shown[-1]), total]


## The next page (way 1) or the one before (-1). Held until no hand is on the table, as the
## console's bank keys are: a voice never changes which track it is under a hand.
func page(way: int) -> void:
	showing = &"bank"
	var wanted := DAW.state.bank_offset + view_offset + way * PAGE
	if wanted < 0:
		return
	if _anything_held():
		_pending_view = wanted
		return
	_go_to(wanted)


## Show the page beginning at project track `offset` (0 first), asking the DAW for another bank
## when it is not in the one cached.
func _go_to(offset: int) -> void:
	var cached := DAW.state.tracks.size()
	var local := offset - DAW.state.bank_offset
	if local < 0 or local >= cached:
		if DAW.state.project_track_count > 0 and offset >= DAW.state.project_track_count:
			return
		view_offset = 0
		DAW.set_track_bank(offset)
		return
	view_offset = local
	mark_dirty()


## SHOW: the bank, then the soloed tracks, then the selected ones.
func step_show() -> void:
	showing = SHOWS[(SHOWS.find(showing) + 1) % SHOWS.size()]
	mark_dirty()


## A new DAW (or the same one back) may want a ring now, or no longer: rebuilt, and told when
## Reaper's pan mode had to change for a width.
func _on_connection_changed() -> void:
	super()
	_hook_pan_mode()


func _hook_pan_mode() -> void:
	var reaper := DAW.backend as ReaperBackend
	if reaper != null and not reaper.pan_mode_set.is_connected(_on_pan_mode_set):
		reaper.pan_mode_set.connect(_on_pan_mode_set)


## Reaper's balance panner has no width, so the first width on a track sets it to stereo pan.
## Said once, here, and on the voice's card from then on (hint_of).
func _on_pan_mode_set(index: int) -> void:
	Session.notice.emit("%s: pan mode set to stereo pan, so it can have a width." % title_of(index))


func _on_track_changed(index: int, field: StringName) -> void:
	# Which tracks a soloed or selected table shows is the shape of it.
	if showing != &"bank" and (field == &"solo" or field == &"selected"):
		mark_dirty()
	if voices.has(index):
		(voices[index] as StageVoice).refresh()
	if tags.has(index):
		(tags[index] as Tag).refresh()
	if field == &"name" or field == &"colour":
		_refresh_range()


# --- placing --------------------------------------------------------------------------------

## A voice of `track` is being put at `want` (the table's frame, x across and z toward the
## player): pan and volume are written for it, only where they changed, and where it landed
## comes back. Dead centre within SNAP unless `fine`; at the front edge at most; past the back
## edge, -inf on the lip.
func place(track: int, want: Vector2, fine: bool) -> Vector2:
	var t := DAW.state.track(track, false)
	var x := clampf(want.x, -HALF_PAN, HALF_PAN)
	if not fine and absf(x) < SNAP:
		x = 0.0
	var z := minf(want.y, SIZE.y * 0.5)
	var db := db_of_z(z)
	if db == -INF:
		z = OFF_Z
	if t == null:
		return Vector2(x, z)
	var pan := pan_of_x(x)
	var taper := FaderLaw.to_taper(db)
	if absf(pan - t.pan) > 0.0001:
		DAW.set_track_pan(track, pan)
	if absf(taper - t.volume) > 0.00001:
		DAW.set_track_volume(track, taper)
	return Vector2(x, z)


## The wheel over a voice: half a decibel a notch, a tenth fine; down off -40 is -inf, and up from
## -inf is -40. Not past the front edge's +6 by the wheel, though a louder track keeps its level.
func nudge_volume(track: int, notches: int, fine: bool) -> bool:
	var t := DAW.state.track(track, false)
	if t == null:
		return false
	var db := FaderLaw.to_db(t.volume)
	var to: float
	if db == -INF:
		if notches < 0:
			return true
		to = BACK_DB
	else:
		to = db + notches * (DB_FINE if fine else DB_STEP)
		if notches > 0:
			to = minf(to, maxf(db, FRONT_DB))
		if to < BACK_DB - 0.001:
			to = -INF
	var taper := FaderLaw.to_taper(to)
	if absf(taper - t.volume) > 0.00001:
		DAW.set_track_volume(track, taper)
	return true


## The wheel while a voice is held: its width, five percent a notch, one fine.
func nudge_width(track: int, notches: int, fine: bool) -> bool:
	var t := DAW.state.track(track, false)
	if t == null or not DAW.can(DAWBackend.Capability.WIDTH):
		return false
	var w := clampf(t.width + notches * (WIDTH_FINE if fine else WIDTH_STEP), 0.0, 1.0)
	if absf(w - t.width) > 0.0001:
		DAW.set_track_width(track, w)
	return true


## PAN < > on a tag: `by` of the pan's travel (PAN_STEP is a percent of it as the console counts).
func nudge_pan(track: int, by: float) -> bool:
	var t := DAW.state.track(track, false)
	if t == null:
		return false
	var pan := clampf(t.pan + by, 0.0, 1.0)
	if absf(pan - t.pan) > 0.0001:
		DAW.set_track_pan(track, pan)
	return true


## A press with no drag: the second within DOUBLE_PRESS puts the track back. After the voice's
## let-go has closed its own edit, so the reset is an edit of its own ("Bass: reset").
func pressed(track: int) -> void:
	var now := Time.get_ticks_msec()
	if _presses.has(track) and now - int(_presses[track]) <= int(DOUBLE_PRESS * 1000.0):
		_presses.erase(track)
		reset.call_deferred(track)
		return
	_presses[track] = now


func forget_press(track: int) -> void:
	_presses.erase(track)


## Centre, 0 dB and full width, as one undo step: a double press, Backspace, or RESET.
func reset(track: int) -> void:
	var t := DAW.state.track(track, false)
	if t == null:
		return
	DAW.open_edit("%s: reset" % t.display_name())
	if absf(t.pan - 0.5) > 0.0001:
		DAW.set_track_pan(track, 0.5)
	var unity := FaderLaw.to_taper(0.0)
	if absf(t.volume - unity) > 0.00001:
		DAW.set_track_volume(track, unity)
	if DAW.can(DAWBackend.Capability.WIDTH) and t.width < 0.9999:
		DAW.set_track_width(track, 1.0)
	DAW.close_edit()


## Backspace on a desktop: the track of whatever on the table is under the cursor, put back.
## False when it is nothing of the table's.
func reset_under(control: Node) -> bool:
	if control == null or not is_instance_valid(control) or not is_ancestor_of(control):
		return false
	var n := control
	while n != null and n != self:
		if n.has_meta(&"stage_track"):
			reset(int(n.get_meta(&"stage_track")))
			return true
		n = n.get_parent()
	return false


# --- what the cards say ---------------------------------------------------------------------

## "3 BASS".
func title_of(track: int) -> String:
	var t := DAW.state.track(track, false)
	var name := t.display_name() if t != null else "Track %d" % track
	return "%d %s" % [number_of(track), name.to_upper()]


## "pan 20 L · -4.2 dB · width 60%", and MUTE or SOLO in words.
func readout_of(track: int) -> String:
	var t := DAW.state.track(track, false)
	if t == null:
		return ""
	var parts := [pan_words(t.pan), db_words(t.volume)]
	if DAW.can(DAWBackend.Capability.WIDTH):
		parts.append("width %d%%" % roundi(t.width * 100.0))
	if t.mute:
		parts.append("MUTE")
	if t.solo:
		parts.append("SOLO")
	return " · ".join(parts)


func hint_of(track: int) -> String:
	var lines := ["drag: across is pan, back is quieter, off the back is -inf  ·  wheel 0.5 dB, Shift 0.1"]
	if DAW.can(DAWBackend.Capability.WIDTH):
		lines.append("wheel while held: width  ·  drag the ring: width  ·  double-click, Backspace or RESET: back to centre")
	else:
		lines.append("no width ring: this DAW cannot set a track's width  ·  double-click, Backspace or RESET: back to centre")
	if DAW.backend is ReaperBackend and (DAW.backend as ReaperBackend).stereo_panned.has(track):
		lines.append("pan mode set to stereo pan, for the width")
	return "\n".join(lines)


# --- building it ----------------------------------------------------------------------------

func _rebuild() -> void:
	_clear_built()
	voices.clear()
	tags.clear()
	_leads.clear()
	_levels.clear()
	_build_top()
	_build_rail()
	var shown := shown_tracks()
	var slot := (SIZE.x - 2.0 * RAIL_END) / PAGE
	for n in shown.size():
		var track: int = shown[n]
		var tag := Tag.new()
		tag.name = "Tag%d" % track
		tag.table = self
		tag.track = track
		tag.position = Vector3(-SIZE.x * 0.5 + RAIL_END + slot * (n + 0.5), 0, 0.004)
		tag.width = slot - 0.006
		tag.set_meta(&"stage_track", track)
		_rail.add_child(tag)
		tags[track] = tag
		var lead := MeshInstance3D.new()
		lead.name = "Lead%d" % track
		var line := BoxMesh.new()
		line.size = Vector3(0.0012, 0.0006, 1.0)
		lead.mesh = line
		lead.material_override = Materials.legend()
		lead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_adopt(lead)
		_leads[track] = lead
	for track in shown:
		var voice := StageVoice.new()
		voice.name = "Voice%d" % track
		voice.table = self
		voice.track = track
		voice.set_meta(&"stage_track", track)
		_adopt(voice)
		voices[track] = voice
	_empty_label.visible = shown.is_empty()
	_empty_label.text = {&"bank": "NO TRACKS", &"soloed": "NO TRACK SOLOED", &"selected": "NO TRACK SELECTED"}[showing]
	_refresh_range()


## The leader from a voice's tag, along the table to its foot: which ball is which track, read
## without colour.
func lead(voice: StageVoice) -> void:
	var line: MeshInstance3D = _leads.get(voice.track)
	var tag: Tag = tags.get(voice.track)
	if line == null or tag == null:
		return
	var from := Vector3(tag.position.x, 0.0007, SIZE.y * 0.5 - 0.004)
	var to := Vector3(voice.position.x, 0.0007, voice.position.z)
	var length := from.distance_to(to)
	if length < 0.001:
		line.visible = false
		return
	line.visible = true
	var b := Basis.looking_at(to - from, Vector3.UP)
	line.transform = Transform3D(b * Basis.from_scale(Vector3(1, 1, length)), (from + to) * 0.5)


func _refresh_range() -> void:
	if _range_label == null:
		return
	_range_label.text = range_text() if showing == &"bank" else ("%d SOLOED" % voices.size() if showing == &"soloed" else "%d SELECTED" % voices.size())
	_show_label.text = "SHOW\n%s" % String(showing).to_upper()


static var _baize: StandardMaterial3D


## The top's finish: dark and matte, so the voices and the lines are what is seen.
static func baize() -> StandardMaterial3D:
	if _baize == null:
		_baize = StandardMaterial3D.new()
		_baize.albedo_color = Color(0.075, 0.08, 0.095)
		_baize.roughness = 0.95
	return _baize


func _build_top() -> void:
	var top := MeshInstance3D.new()
	top.name = "Top"
	var slab := BoxMesh.new()
	slab.size = Vector3(SIZE.x, THICK, SIZE.y)
	top.mesh = slab
	top.position = Vector3(0, -THICK * 0.5, 0)
	top.material_override = baize()
	_adopt(top)
	# The lip behind the back edge, where a voice at -inf stands.
	var lip := MeshInstance3D.new()
	lip.name = "Lip"
	var lip_mesh := BoxMesh.new()
	lip_mesh.size = Vector3(SIZE.x, THICK, 0.035)
	lip.mesh = lip_mesh
	lip.position = Vector3(0, -THICK * 0.5 - 0.004, OFF_Z)
	lip.material_override = Materials.chassis()
	_adopt(lip)
	_flat_label("-inf", 40, Vector3(-SIZE.x * 0.5 + 0.03, 0.0002, OFF_Z), HORIZONTAL_ALIGNMENT_LEFT)
	_flat_label("-inf", 40, Vector3(SIZE.x * 0.5 - 0.03, 0.0002, OFF_Z), HORIZONTAL_ALIGNMENT_RIGHT)
	# The decibel lines across, 0 dB the strongest.
	for db in LINES_DB:
		var z := z_of_db(db)
		var line := MeshInstance3D.new()
		var bar := BoxMesh.new()
		bar.size = Vector3(SIZE.x - 0.14, 0.0008, 0.003 if db == 0.0 else 0.0012)
		line.mesh = bar
		line.position = Vector3(0, 0.0004, z)
		line.material_override = Materials.legend()
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_adopt(line)
		var words := "0 dB" if db == 0.0 else "%+d" % int(db)
		_flat_label(words, 44, Vector3(-SIZE.x * 0.5 + 0.012, 0.0005, z), HORIZONTAL_ALIGNMENT_LEFT)
		_flat_label(words, 44, Vector3(SIZE.x * 0.5 - 0.012, 0.0005, z), HORIZONTAL_ALIGNMENT_RIGHT)
	# The middle, front to back, and L C R along the front, with the half-way marks.
	var centre := MeshInstance3D.new()
	var spine := BoxMesh.new()
	spine.size = Vector3(0.0018, 0.0008, SIZE.y)
	centre.mesh = spine
	centre.position = Vector3(0, 0.0004, 0)
	centre.material_override = Materials.legend()
	_adopt(centre)
	for mark in [[-HALF_PAN, "L"], [-HALF_PAN * 0.5, "50 L"], [0.0, "C"], [HALF_PAN * 0.5, "50 R"], [HALF_PAN, "R"]]:
		_flat_label(mark[1], 56 if (mark[1] as String).length() == 1 else 36,
				Vector3(mark[0], 0.0005, SIZE.y * 0.5 - 0.035), HORIZONTAL_ALIGNMENT_CENTER)
	_flat_label("ACROSS IS PAN  ·  BACK IS QUIETER  ·  THE RING IS WIDTH", 34,
			Vector3(0, 0.0005, -SIZE.y * 0.5 + 0.03), HORIZONTAL_ALIGNMENT_CENTER)
	_empty_label = _flat_label("", 60, Vector3(0, 0.0005, 0.1), HORIZONTAL_ALIGNMENT_CENTER)


## Lettering printed on the top, read from the front.
func _flat_label(words: String, size: int, at: Vector3, align: HorizontalAlignment) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = 0.0004
	label.modulate = Color(0.74, 0.76, 0.8)
	label.horizontal_alignment = align
	label.rotation = Vector3(-PI * 0.5, 0, 0)
	label.position = at
	label.double_sided = false
	Lettering.range_to_legibility(label)
	_adopt(label)
	return label


## The rail along the front edge, sloped down toward the player like a desk's lip: the tags, and
## the keys at either end.
func _build_rail() -> void:
	_rail = Node3D.new()
	_rail.name = "Rail"
	# Its +Z up and toward the player, 35 degrees down from the top; its +Y up the slope.
	var b := Basis(Vector3.RIGHT, deg_to_rad(-55.0))
	_rail.transform = Transform3D(b, Vector3(0, 0, SIZE.y * 0.5) - b.y * RAIL_DEEP * 0.5)
	_adopt(_rail)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x, RAIL_DEEP, 0.012)
	plate.mesh = box
	plate.position = Vector3(0, 0, -0.006)
	plate.material_override = Materials.master_plate()
	_rail.add_child(plate)
	var left := -SIZE.x * 0.5 + RAIL_END * 0.5
	var right := SIZE.x * 0.5 - RAIL_END * 0.5
	_rail_label("BANK", 40, Vector3(left, 0.058, 0.001))
	_range_label = _rail_label("", 34, Vector3(left, 0.03, 0.001))
	var earlier := _key("<", Vector3(left - 0.02, -0.01, 0.004))
	earlier.describe_title = func() -> String: return "STAGE  EARLIER TRACKS"
	earlier.describe_value = func(_v: float) -> String: return range_text()
	earlier.says = "the eight tracks before these"
	earlier.pressed.connect(page.bind(-1))
	var later := _key(">", Vector3(left + 0.02, -0.01, 0.004))
	later.describe_title = func() -> String: return "STAGE  LATER TRACKS"
	later.describe_value = func(_v: float) -> String: return range_text()
	later.says = "the eight tracks after these"
	later.pressed.connect(page.bind(1))
	_show_label = _rail_label("", 34, Vector3(right, 0.04, 0.001))
	var shows := _key("SHOW", Vector3(right, -0.01, 0.004))
	shows.describe_title = func() -> String: return "STAGE  SHOW"
	shows.describe_value = func(_v: float) -> String: return String(showing).to_upper()
	shows.says = "the bank, the soloed tracks or the selected ones"
	shows.lit = showing != &"bank"
	shows.pressed.connect(step_show)
	_rail_label("STAGE TABLE", 30, Vector3(right, -0.05, 0.001))


func _rail_label(words: String, size: int, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = 0.0004
	label.modulate = Color(0.8, 0.82, 0.86)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = at
	Lettering.range_to_legibility(label)
	_rail.add_child(label)
	return label


func _key(glyph: String, at: Vector3, parent: Node3D = null) -> TableKey:
	var key := TableKey.new()
	key.position = at
	key.glyph = glyph
	(parent if parent != null else _rail).add_child(key)
	return key


## A key on the table's rail: a desk button with its legend on its face, which says what it does
## on the hover card and may take the wheel.
class TableKey extends PanelButton:
	var glyph := ""
	## What it does, for the card.
	var says := ""
	## (notches: int, fine: bool) -> bool, for a key the wheel works too (PAN < >).
	var wheel: Callable = Callable()
	var dwells := true

	func _ready() -> void:
		led_colour = Color(0.45, 0.68, 0.95)
		hit_pad = Vector2(1.6, 2.0)
		super()
		var face := Label3D.new()
		face.text = glyph
		face.font_size = 26 if glyph.length() > 1 else 40
		face.pixel_size = 0.0003
		face.position = Vector3(0, 0, 0.0045)
		face.modulate = Color(0.92, 0.93, 0.95)
		Lettering.range_to_legibility(face)
		Lettering.fit(face, PanelButton.SIZE.x * 0.95, face.font_size, 12)
		add_child(face)

	func _on_nudge(notches: int, fine: bool) -> bool:
		return wheel.call(notches, fine) if wheel.is_valid() else false

	func dwell_activates() -> bool:
		return dwells

	func _default_readout() -> String:
		return ""

	func hint() -> String:
		return says


## A voice's tag on the rail: its number and name, a chip of its colour, what it is set to and
## whether it is muted or soloed in words, PAN < > keys and RESET.
class Tag extends Node3D:
	var table: StageTable
	var track := 0
	var width := 0.11
	var _name: Label3D
	var _state: Label3D
	var _readout: Label3D
	var _chip: MeshInstance3D

	func _ready() -> void:
		_name = _label(40, Vector3(0, 0.055, 0.001))
		_state = _label(30, Vector3(0, 0.036, 0.001))
		_readout = _label(26, Vector3(0, 0.019, 0.001))
		_chip = MeshInstance3D.new()
		var chip := BoxMesh.new()
		chip.size = Vector3(width * 0.8, 0.003, 0.002)
		_chip.mesh = chip
		_chip.position = Vector3(0, 0.072, 0.001)
		add_child(_chip)
		var left := table._key("<", Vector3(-0.03, -0.012, 0.0), self)
		left.describe_title = func() -> String: return "%s  PAN LEFT" % table.title_of(track)
		left.describe_value = func(_v: float) -> String: return table.readout_of(track)
		left.says = "a percent left a press  ·  wheel 5% a notch, Shift 1%"
		left.pressed.connect(func(): table.nudge_pan(track, -StageTable.PAN_STEP))
		left.wheel = _wheel_pan
		left.set_meta(&"stage_track", track)
		var right := table._key(">", Vector3(0.03, -0.012, 0.0), self)
		right.describe_title = func() -> String: return "%s  PAN RIGHT" % table.title_of(track)
		right.describe_value = func(_v: float) -> String: return table.readout_of(track)
		right.says = "a percent right a press  ·  wheel 5% a notch, Shift 1%"
		right.pressed.connect(func(): table.nudge_pan(track, StageTable.PAN_STEP))
		right.wheel = _wheel_pan
		right.set_meta(&"stage_track", track)
		var pan := _label(26, Vector3(0, -0.012, 0.001))
		pan.text = "PAN"
		var reset := table._key("RESET", Vector3(0, -0.048, 0.0), self)
		reset.describe_title = func() -> String: return "%s  RESET" % table.title_of(track)
		reset.describe_value = func(_v: float) -> String: return table.readout_of(track)
		reset.says = "back to centre, 0 dB and full width (one undo step)"
		reset.dwells = false
		reset.pressed.connect(func(): table.reset(track))
		reset.set_meta(&"stage_track", track)
		refresh()

	func _wheel_pan(notches: int, fine: bool) -> bool:
		return table.nudge_pan(track, notches * (StageTable.PAN_STEP * 2.0 if fine else StageTable.PAN_WHEEL))

	func _label(size: int, at: Vector3) -> Label3D:
		var label := Label3D.new()
		label.font_size = size
		label.pixel_size = 0.0003
		label.modulate = Color(0.86, 0.88, 0.92)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = at
		Lettering.range_to_legibility(label)
		add_child(label)
		return label

	func refresh() -> void:
		var t := DAW.state.track(track, false)
		if t == null or _name == null:
			return
		_name.text = table.title_of(track)
		Lettering.fit(_name, width, 40, 18)
		var words := []
		if t.mute:
			words.append("MUTE")
		if t.solo:
			words.append("SOLO")
		_state.text = "  ".join(words)
		var shown := [StageTable.pan_words(t.pan), StageTable.db_words(t.volume)]
		if DAW.can(DAWBackend.Capability.WIDTH):
			shown.append("%d%%" % roundi(t.width * 100.0))
		_readout.text = "  ".join(shown)
		Lettering.fit(_readout, width, 26, 12)
		_chip.material_override = Materials.track_glow(t.shown_colour())
