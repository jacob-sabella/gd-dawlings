class_name PatchbaySurface
extends Surface

## The routing bay: every track's sends, as a pin matrix (PinMatrix).
##
## Track outputs down the left, FROM; track inputs across the top, TO. A pin seated where KICK's
## row crosses BASS DI's column is a send from the kick into the bass, and the bar beside it is
## how loud. Signal goes one way, row to column, every time, so which track feeds which is read
## off the grid rather than followed along a cable. A track's own crossing has no socket (it
## cannot send to itself), nor has a crossing whose send would loop a track back into itself;
## pointing at one says why.
##
## What you can do (PinMatrix has the gestures):
##   - press a crossing: a send at 0 dB, or, where there is one, the send pulled out
##   - wheel a seated pin, or drag it up and down: that send's level
##   - wheel the headers or an empty socket, drag the grid, or its bars: scroll; Shift-wheel sideways
## Point at a pin and its row and column light while the rest dims, so one track's routing can be
## picked out of a busy session; point at a name and that one track's line lights.
##
## Levels, always (docs/spatial_loop.md part three, D): each row's header meters its track after
## the fader, each column's what its sends bring in added together, and a seated pin pulses with
## what its send carries -- SignalGraph's figures, measured on the built-in engine, estimated (≈)
## from the track's meter and the send's level on Reaper -- dull while it carries nothing, its card
## saying why ("patched · no signal: KICK is muted"). With the signal glasses on the bay is a
## skyline (PinMatrix.skyline): every send a tower its level tall, whose top is dragged for the
## send's level, and the card reads "KICK → BASS DI · −6.0 dB send · peaking −3.1 dBFS".
##
## Every change goes through DAW like every other: one undo step a press, a guest's press an
## intent the host carries out (`hosting`), the host's own routing rules the only ones
## (DAW.send_refusal). A guest's pin shows as asked for until the host's send arrives.
##
## THE HONEST LIMITATION. Reaper's OSC surface streams send LEVELS but has no message that creates
## or destroys a send; that is only reachable from ReaScript. So against Reaper this bay CHANGES
## routing through the file bridge, and when the bridge is not loaded it says so on its own face
## rather than dropping the press. See core/reaper/script_bridge.gd.

## Something to tell the player, out loud: a send refused, and why.
signal told(text: String)

const PANEL_WIDTH := 1.1
const PANEL_DEPTH := 0.02
## The strip over the matrix that says what the bay is and how it is worked.
const HEADER := 0.075
## The bank caption under the matrix, when the rows are a bank rather than the session.
const CAPTION := 0.045
const MARGIN := 0.03
## The most of the stand the matrix may take: past this many rows the window scrolls.
const MATRIX_AREA := Vector2(PANEL_WIDTH - 2.0 * MARGIN, 0.98)
## How far above the panel's lower edge the permanent looms enter the back of the bay.
const LOOM_ENTRY_RISE := 0.068
## dB per wheel notch or level-drag step, and with the fine modifier.
const STEP_DB := 1.0
const FINE_DB := 0.1
## How long a guest's asked-for pin waits for the host's send before it is let go.
const ASK_MSEC := 4000
## How tall a send at SignalGraph.TOP_DB stands out of the bay in the skyline (m).
const TOWER_MAX := 0.26
## How long a card's graph (for why a pin carries nothing) is kept before it is built again (ms).
const WHY_MSEC := 300

## () -> bool: whether this process carries out its own changes or asks the host to. Wired by
## the studio (StageLink.wire_bay); unset, it is the host.
var hosting: Callable = Callable()

var matrix: PinMatrix
var _height := 0.0
## What the bay was last built from, so a send's level moving does not rebuild it.
var _built_key := ""
## Which track reaches which (MixState.reach), worked out once a shape.
var _reach := {}
## A guest's sends asked for and not yet there: Vector2i(source, destination) -> when.
var _asked := {}
var _why_graph: SignalGraph = null
var _why_at := 0


func _ready() -> void:
	surface_kind = &"patchbay"
	if surface_id == &"":
		surface_id = &"patchbay"
	super()
	matrix = PinMatrix.new()
	matrix.name = "Matrix"
	matrix.row_head = 0.22
	matrix.col_head = 0.15
	matrix.row_pitch = Vector2(0.032, 0.05)
	matrix.col_pitch = Vector2(0.034, 0.06)
	matrix.area = MATRIX_AREA
	matrix.bar = 0.03
	matrix.gap = 0.008
	matrix.foot = 0.045
	matrix.px = 0.0003
	matrix.name_cap = 0.022
	matrix.chip = 0.016
	matrix.row_word = "FROM"
	matrix.col_word = "TO"
	matrix.pin_at = _pin_at
	matrix.toggle = _toggle
	matrix.level = _level
	matrix.describe = _describe
	matrix.describe_line = _describe_line
	matrix.row_meter = _row_meter
	matrix.col_meter = _col_meter
	matrix.pin_meter = _pin_meter
	matrix.level_db = _level_db
	matrix.set_level_db = _set_level_db
	matrix.tower_max = TOWER_MAX
	add_child(matrix)
	DAW.track_changed.connect(_on_track_changed)


func _on_track_changed(_index: int, field: StringName) -> void:
	# Looked at once a frame rather than per message: a refresh from Reaper is a thousand of
	# these in one go, and the key is every track and every send.
	if field in [&"sends", &"name", &"colour", &"folder_depth"]:
		_once_this_frame(_check_shape)


## A patch made or pulled, a name or colour changed: the bay again. Only a level: the pins again.
func _check_shape() -> void:
	if _shape_key() != _built_key:
		mark_dirty()
	elif matrix != null:
		matrix.refresh()


func _rebuild() -> void:
	_clear_built()
	_built_key = _shape_key()
	_reach = DAW.state.reach()
	var now := Time.get_ticks_msec()
	for key in _asked.keys():
		if now - int(_asked[key]) > ASK_MSEC or not _sends_between(key.x, key.y).is_empty():
			_asked.erase(key)

	var lines: Array = []
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		lines.append({"key": index, "name": t.display_name(), "colour": t.shown_colour()})
	if lines.is_empty():
		_height = 0.0
		matrix.visible = false
		matrix.set_lines([], [])
		return
	matrix.visible = true
	matrix.set_lines(lines, lines.duplicate())

	var caption := DAW.state.bank_caption()
	var size := matrix.size()
	_height = HEADER + size.y + (CAPTION if caption != "" else MARGIN * 0.5)
	# The origin is the middle of the panel's TOP edge: a bigger session grows the bay downward,
	# the way a rack fills, and the top row stays where you last read it.
	matrix.position = Vector3(-size.x * 0.5, -HEADER, 0.0)

	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var box := BoxMesh.new()
	box.size = Vector3(PANEL_WIDTH, _height, PANEL_DEPTH)
	panel.mesh = box
	panel.position = Vector3(0, -_height * 0.5, -PANEL_DEPTH * 0.5)
	panel.material_override = Materials.chassis()
	_adopt(panel)
	_lettering(caption)


func _lettering(caption: String) -> void:
	var half := PANEL_WIDTH * 0.5
	_print("ROUTING", Vector3(-half + MARGIN, -0.03, 0.001), 80, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.95, 0.93, 0.88))
	_print("TRACK SENDS  ·  FROM A ROW INTO A COLUMN", Vector3(-half + MARGIN, -0.058, 0.001), 34,
			HORIZONTAL_ALIGNMENT_LEFT, Color(0.62, 0.63, 0.66))

	# The head of the bay says how to use it -- or, against a Reaper that cannot be patched from
	# here, says so, so a press that does nothing is never the first anyone hears of it.
	var words := "PRESS A CROSSING TO PATCH OR UNPATCH  ·  WHEEL A PIN FOR LEVEL  ·  DRAG OR WHEEL THE NAMES TO SCROLL"
	var tint := Color(0.62, 0.63, 0.66)
	if not DAW.can(DAWBackend.Capability.ROUTING):
		words = "READ ONLY: PATCHING NEEDS THE DAWLINGS BRIDGE LOADED IN REAPER"
		tint = Color(0.86, 0.66, 0.38)
	var how := _print(words, Vector3(half - MARGIN, -0.04, 0.001), 34, HORIZONTAL_ALIGNMENT_RIGHT, tint)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.width = (PANEL_WIDTH * 0.62) / how.pixel_size
	Lettering.fit(how, PANEL_WIDTH * 0.62, 34)

	# Says so when these rows are a BANK rather than the session: a bay is read as every track
	# there is, and the one thing you cannot do with a row that was never drawn is miss it.
	if caption != "":
		_print(caption, Vector3(0, -_height + CAPTION * 0.5, 0.001), 36,
				HORIZONTAL_ALIGNMENT_CENTER, Color(0.86, 0.66, 0.38))


func _print(text: String, at: Vector3, size: int, align: int, tint: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.0003
	label.font_size = size
	label.horizontal_alignment = align
	label.modulate = tint
	label.position = at
	Lettering.range_to_legibility(label)
	_adopt(label)
	return label


func _shape_key() -> String:
	var parts := PackedStringArray()
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		parts.append("%d:%s:%s:%d" % [index, t.display_name(), t.shown_colour().to_html(false), t.folder_depth])
		var keys: Array = t.sends.keys()
		keys.sort()
		for k in keys:
			var sd := t.sends[k] as MixState.SendState
			parts.append("%d.%d>%d%s" % [index, k, sd.resolve(DAW.state), "k" if sd.key else ""])
	parts.append("routing" if DAW.can(DAWBackend.Capability.ROUTING) else "read-only")
	return "|".join(parts)


# --- the crossings ----------------------------------------------------------------------------

## The sends from `src` into `dst`, by their place in `src`'s list: its ordinary send first, then
## any key send (a sidechain).
func _sends_between(src: int, dst: int) -> Array:
	var t := DAW.state.track(src, false)
	if t == null:
		return []
	var plain: Array = []
	var keyed: Array = []
	var keys: Array = t.sends.keys()
	keys.sort()
	for k in keys:
		var sd := t.sends[k] as MixState.SendState
		if sd.resolve(DAW.state) == dst:
			(keyed if sd.key else plain).append(int(k))
	return plain + keyed


func _blocked(src: int, dst: int) -> bool:
	return src == dst or (_reach.get(dst, {}) as Dictionary).has(src)


func _pin_at(src: int, dst: int) -> Dictionary:
	var t := DAW.state.track(src, false)
	var tint := t.shown_colour() if t != null else Color.GRAY
	var sends := _sends_between(src, dst)
	if not sends.is_empty():
		var first := DAW.state.send(src, sends[0], false)
		return {"on": true, "level": first.volume if first != null else 0.0, "tint": tint}
	if _blocked(src, dst):
		return {"blocked": true, "tint": tint}
	return {"on": false, "tint": tint, "pending": _asked.has(Vector2i(src, dst))}


## A press: the send made, or every send at the crossing pulled out in one undo step. Returns what
## to say, which is a refusal when there is one.
func _toggle(src: int, dst: int) -> String:
	if not DAW.can(DAWBackend.Capability.ROUTING):
		# Said out loud, for the reason in the class note.
		push_warning("Patchbay: routing cannot be changed from here. The ReaScript bridge is not loaded in Reaper, and OSC has no message for making or removing a send.")
		return _say("Read only: patching needs the dawlings bridge loaded in Reaper.")
	var sends := _sends_between(src, dst)
	var pin := matrix.pin_for(src, dst)
	if sends.is_empty():
		var why := DAW.send_refusal(src, dst)
		if not why.is_empty():
			return _say(why)
		DAW.create_send(src, dst)
		if hosting.is_valid() and not bool(hosting.call()):
			_asked[Vector2i(src, dst)] = Time.get_ticks_msec()
		if pin != null:
			Foley.play(pin, Foley.plug_seat(), -6.0)
	else:
		if sends.size() > 1:
			DAW.open_edit("%s → %s: unpatch" % [_name_of(src), _name_of(dst)])
		# From the last: a send's place is its number, and pulling one renumbers those after it.
		sends.sort()
		sends.reverse()
		for k in sends:
			DAW.remove_send(src, k)
		if sends.size() > 1:
			DAW.close_edit()
		if pin != null:
			Foley.play(pin, Foley.plug_seat(), -8.0, 0.8)
	mark_dirty()
	return ""


func _say(text: String) -> String:
	told.emit(text)
	return text


## A seated pin's level, `notches` steps of STEP_DB (FINE_DB fine): its ordinary send's, or its
## sidechain's where that is all there is.
func _level(src: int, dst: int, notches: int, fine: bool) -> bool:
	var sends := _sends_between(src, dst)
	if sends.is_empty():
		return false
	var s := DAW.state.send(src, sends[0], false)
	if s == null:
		return false
	# From the bottom of the table when it is off, or a send at -inf could never be turned up.
	var db := maxf(FaderLaw.to_db(s.volume), -61.0) + notches * (FINE_DB if fine else STEP_DB)
	DAW.set_send_volume(src, sends[0], 0.0 if db < -60.0 else FaderLaw.to_taper(db))
	return true


# --- levels (docs/spatial_loop.md part three, D and E) ------------------------------------------

func _row_meter(src: int) -> Vector3:
	var t := DAW.state.track(src, false)
	return SignalGraph.fader_level(t) if t != null else Vector3(-INF, NAN, SignalGraph.UNKNOWN)


func _col_meter(dst: int) -> Vector3:
	return SignalGraph.arrival_level(DAW.state, dst)


## What the crossing's send carries: its ordinary send's, or its sidechain's where that is all.
func _pin_meter(src: int, dst: int) -> Vector3:
	var t := DAW.state.track(src, false)
	if t == null:
		return Vector3(-INF, 0.0, SignalGraph.UNKNOWN)
	for k in t.sends:
		var sd := t.sends[k] as MixState.SendState
		if not sd.key and sd.resolve(DAW.state) == dst:
			return SignalGraph.send_level(t, int(k))
	for k in t.sends:
		if (t.sends[k] as MixState.SendState).resolve(DAW.state) == dst:
			return SignalGraph.send_level(t, int(k))
	return Vector3(-INF, 0.0, SignalGraph.UNKNOWN)


func _level_db(src: int, dst: int) -> float:
	var sends := _sends_between(src, dst)
	var s := DAW.state.send(src, sends[0], false) if not sends.is_empty() else null
	return FaderLaw.to_db(s.volume) if s != null and s.volume > 0.0 else -INF


## A tower's drag: the crossing's send to `db` (under -60 is off).
func _set_level_db(src: int, dst: int, db: float) -> bool:
	var sends := _sends_between(src, dst)
	if sends.is_empty():
		return false
	DAW.set_send_volume(src, sends[0], 0.0 if db < -60.0 else FaderLaw.to_taper(db))
	return true


## Why a patched send carries nothing, in words: its own stop, a stop on the way to it (muted,
## soloed out, the fader down, a plugin silent, nothing to play), the transport, or nothing playing.
func why_silent(src: int, dst: int) -> String:
	var now := Time.get_ticks_msec()
	if _why_graph == null or now - _why_at > WHY_MSEC:
		_why_graph = SignalGraph.build(DAW.state)
		_why_at = now
	var sends := _sends_between(src, dst)
	if sends.is_empty():
		return ""
	var send := _why_graph.stage(SignalGraph.send_id(src, sends[0]))
	if send != null and send.halt != &"":
		return send.why
	var tr := _why_graph.trace(SignalGraph.play_id(src))
	for st: SignalGraph.Stage in tr.stages:
		if st.halt != &"" and (st.track == src or tr.reason == SignalGraph.FOLDER_MUTED):
			# A send leaves from the fader, so a stop past it (the folder, the master) is no stop here.
			if st.kind == SignalGraph.Kind.FADER and st.halt == SignalGraph.NO_ROUTE:
				break
			return "%s: %s" % [_name_of(src), st.why] if st.track == src else tr.words
		if st.kind == SignalGraph.Kind.FADER:
			break
	if not DAW.state.playing:
		return "the transport is stopped"
	return "nothing on %s is sounding just now" % _name_of(src)


func _describe(src: int, dst: int) -> PackedStringArray:
	var title := "%s  →  %s" % [_name_of(src), _name_of(dst)]
	var sends := _sends_between(src, dst)
	var can := DAW.can(DAWBackend.Capability.ROUTING)
	if src == dst:
		return PackedStringArray([title, "no send: a track cannot send to itself", ""])
	if sends.is_empty():
		if _blocked(src, dst):
			return PackedStringArray([title, "no send: it would loop", DAW.send_refusal(src, dst)])
		var said := "not patched · asked the host" if _asked.has(Vector2i(src, dst)) else "not patched"
		return PackedStringArray([title, said,
				"click to patch a send at 0 dB" if can else "read only: patching needs the dawlings bridge in Reaper"])
	var words := PackedStringArray()
	for k in sends:
		var s := DAW.state.send(src, k, false)
		var db := FaderLaw.to_db(s.volume) if s != null else -INF
		var level := "−∞ dB" if db < -60.0 else "%s%.1f dB" % ["+" if db > 0.0 else ("−" if db < 0.0 else ""), absf(db)]
		words.append(("%s sidechain" if s != null and s.key else "%s send") % level)
	# What it carries: "peaking −3.1 dBFS", or that it is patched and silent, and why.
	var carried := _pin_meter(src, dst)
	if carried.z != SignalGraph.UNKNOWN and is_finite(carried.x) and carried.x > SignalGraph.FLOOR_DB:
		var peak := "peaking %s" % SignalGraph.db_words(carried.x, carried.z)
		if carried.x > SignalGraph.CLIP_DB:
			peak = "CLIPPING: " + peak
		elif carried.x >= SignalGraph.HOT_DB:
			peak = "HOT: " + peak
		words.append(peak)
	else:
		words.append("patched · no signal: %s" % why_silent(src, dst))
	var hint := "click to pull the pin out · wheel, or drag up and down, for level" if can \
			else "read only: wheel for level; patching needs the dawlings bridge in Reaper"
	if matrix != null and matrix.skyline:
		hint = "drag the tower's top up or down, or pull it out, for the send's level · " + hint
	return PackedStringArray([title, " · ".join(words), hint])


func _describe_line(line: Dictionary, is_row: bool) -> PackedStringArray:
	var index: int = line["key"]
	var count := 0
	if is_row:
		var t := DAW.state.track(index, false)
		if t != null:
			for k in t.sends:
				if (t.sends[k] as MixState.SendState).resolve(DAW.state) > 0:
					count += 1
	else:
		for other in DAW.state.track_indices():
			count += _sends_between(other, index).size()
	var said := "not patched"
	if count > 0:
		said = ("sends to %d" % count) if is_row else ("%d sending in" % count)
	if not is_row and count > 1:
		# A return fed by several: whether the sum goes over where no one send does, said.
		var sum := SignalGraph.arrival_level(DAW.state, index)
		var loudest := -INF
		for other in DAW.state.track_indices():
			for k in _sends_between(other, index):
				loudest = maxf(loudest, SignalGraph.send_level(DAW.state.track(other), k).x)
		if sum.x > SignalGraph.CLIP_DB and loudest <= SignalGraph.CLIP_DB:
			said += " · OVER 0 dBFS TOGETHER (+%.1f dB), though no one send is" % sum.x
	return PackedStringArray(["%s  %s" % [_name_of(index), "OUT" if is_row else "IN"], said,
			"its %s lights · drag or wheel here to scroll" % ("row" if is_row else "column")])


static func _name_of(index: int) -> String:
	if not DAW.state.tracks.has(index):
		return "?"
	return DAW.state.track(index).display_name().to_upper()


# --- measurements -----------------------------------------------------------------------------

## The panel's height, which grows with the session up to MATRIX_AREA; zero before the first build.
func panel_height() -> float:
	return _height


## Where a permanent loom enters the back of the bay, at a fraction (-1..1) across it.
func loom_entry(fraction: float) -> Vector3:
	if _height <= 0.0:
		return Vector3.ZERO
	var half := PANEL_WIDTH * 0.5 - 0.06
	return Vector3(clampf(fraction, -1.0, 1.0) * half, -_height + LOOM_ENTRY_RISE, -PANEL_DEPTH)


## The pin at `src`'s row and `dst`'s column, when the window shows it.
func pin_for(src: int, dst: int) -> PinMatrix.Pin:
	return matrix.pin_for(src, dst) if matrix != null else null


## How many sends the bay shows seated.
func seated_count() -> int:
	var n := 0
	for index in DAW.state.track_indices():
		for other in DAW.state.track_indices():
			if not _sends_between(index, other).is_empty():
				n += 1
	return n
