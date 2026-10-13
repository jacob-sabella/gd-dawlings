class_name PatchbaySurface
extends Surface

## The routing bay: where sends are made, moved and pulled out, laid out to be read.
##
## Two columns facing each other across a gap. FROM, on the left, is every track's output; TO, on
## the right, is every track's input; and every send is a cable from a row on the left to a row
## on the right. Signal flows one way, left to right, every time -- so which track feeds which is
## something you see, not something you work out from which row of identical jacks a plug is in.
## Each row is a colour chip and the track's name as large as the row allows, and the jacks sit
## on the inside edge of each column so the cables live in the gap and not over the names.
##
## Every row has one more jack than its busiest row needs, so there is always a free one and no
## two cables share a bore: one jack takes one plug, and four cables into one hole is a picture of
## nothing. The free jack is where a new cable comes from, and where one dropped on the row goes.
##
## What you can do, all with the same press-drag-release a fader uses (PatchPoint, PatchPlug):
##   - drag from a row to a row in the other column: a send
##   - drag a plug to another row in its own column: that send, re-patched
##   - drag a plug off anywhere else: that send, removed
##   - scroll over a plug: that send's level
## Hover a row and its cables stay lit while the rest dim, so one track's routing can be picked
## out of a busy bay.
##
## THE HONEST LIMITATION. Reaper's OSC surface streams send LEVELS but has no message that creates
## or destroys a send; that is only reachable from ReaScript. So against Reaper this bay CHANGES
## routing through the file bridge, and when the bridge is not loaded it says so on its own face
## rather than dropping the gesture. See core/reaper/script_bridge.gd.

const PANEL_WIDTH := 1.1
const PANEL_DEPTH := 0.02
## One column's width, and where its centre is from the middle of the bay. What is left between
## the two columns is the gap the cables run through.
const COLUMN_WIDTH := 0.44
const COLUMN_X := 0.32
## Between neighbouring jacks in a row, and the most jacks a row is given.
const SLOT_PITCH := 0.028
const MAX_SLOTS := 7
## How tall a row is: as tall as fits ROWS_SPAN, within these. 50mm is a name read from across the
## room; 26mm is about the smallest a row stays easy to hit from the seat.
const ROW_MAX := 0.05
const ROW_MIN := 0.026
const ROWS_SPAN := 0.9
## The strip above the rows that says which column is which, and the one below that says what to do.
const HEADER := 0.085
const FOOTER := 0.05
## How far above the panel's lower edge the permanent looms enter the back of the bay.
const LOOM_ENTRY_RISE := 0.068
## How far the cables droop crossing the gap. A cable to the bottom row at the usual droop hung
## below the bay and over the words at its foot.
const CABLE_SAG := 0.05

var _outputs: Dictionary = {}
var _inputs: Dictionary = {}
## Vector2i(source, send index) -> {src, send, dst, out_slot, in_slot, cable, plugs}
var _routes: Dictionary = {}
var _cables: Array[PatchCable] = []
var _plugs: Array[PatchPlug] = []
var _slots := 2
var _pitch := ROW_MAX
var _height := 0.0
## What the bay was last built from, so a send's level moving does not rebuild it.
var _built_key := ""
## The cable being carried, while one is: {from, fixed, cable, hidden, target}.
var _drag: Dictionary = {}


func _ready() -> void:
	surface_kind = &"patchbay"
	if surface_id == &"":
		surface_id = &"patchbay"
	super()
	DAW.track_changed.connect(_on_track_changed)


func _on_track_changed(_index: int, field: StringName) -> void:
	# A level is a level: the plug says it when asked. Only a change to what is patched, or to
	# how a row is labelled, changes the bay.
	# Looked at once a frame rather than per message: a refresh from Reaper is a thousand of
	# these in one go, and the key is every track and every send.
	if field in [&"sends", &"name", &"colour"]:
		_once_this_frame(_check_shape)


func _check_shape() -> void:
	if _shape_key() != _built_key:
		mark_dirty()


func _rebuild() -> void:
	_clear_built()
	_outputs.clear()
	_inputs.clear()
	_routes.clear()
	_cables.clear()
	_plugs.clear()
	_drag.clear()
	_built_key = _shape_key()

	var indices := DAW.state.track_indices()
	if indices.is_empty():
		_height = 0.0
		return

	# Which row each track is on, top to bottom, and every send that can be drawn.
	var order := {}
	for r in indices.size():
		order[indices[r]] = r
	var routes := _sends()
	var leaving := {}
	var arriving := {}
	for route in routes:
		if not leaving.has(route["src"]):
			leaving[route["src"]] = []
		leaving[route["src"]].append(route)
		if not arriving.has(route["dst"]):
			arriving[route["dst"]] = []
		arriving[route["dst"]].append(route)
	# Each row's plugs in the order of the row at their far end, so the cables out of one row
	# fan out the way they are going instead of crossing each other on the way.
	var busiest := 0
	for src in leaving:
		var list: Array = leaving[src]
		list.sort_custom(func(a, b): return order[a["dst"]] < order[b["dst"]])
		for i in list.size():
			list[i]["out_slot"] = mini(i, MAX_SLOTS - 1)
		busiest = maxi(busiest, list.size())
	for dst in arriving:
		var list: Array = arriving[dst]
		list.sort_custom(func(a, b): return order[a["src"]] < order[b["src"]])
		for i in list.size():
			list[i]["in_slot"] = mini(i, MAX_SLOTS - 1)
		busiest = maxi(busiest, list.size())
	_slots = clampi(busiest + 1, 2, MAX_SLOTS)

	_pitch = clampf(ROWS_SPAN / float(indices.size()), ROW_MIN, ROW_MAX)
	_height = HEADER + _pitch * indices.size() + FOOTER

	# The origin is the middle of the panel's TOP edge: a bigger session grows the bay downward,
	# the way a rack fills, and the top row stays where you last read it.
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var box := BoxMesh.new()
	box.size = Vector3(PANEL_WIDTH, _height, PANEL_DEPTH)
	panel.mesh = box
	panel.position = Vector3(0, -_height * 0.5, -PANEL_DEPTH * 0.5)
	panel.material_override = Materials.chassis()
	_adopt(panel)

	_lettering()

	# Before the rows and in its final place, because a socket claims its slot in the bank by
	# converting its own world transform into the bank's. Null when the authored jack will not
	# resolve, in which case every row draws its own and the bay still works.
	var socket_bank := MeshBank.of(PatchPoint.MESH_PATH, Materials.brushed_metal(),
			{"bore": Materials.recess()})
	if socket_bank != null:
		socket_bank.name = "JackSockets"
		_adopt(socket_bank)

	for r in indices.size():
		var index: int = indices[r]
		var t := DAW.state.track(index)
		for kind in [PatchPoint.Kind.OUTPUT, PatchPoint.Kind.INPUT]:
			var row := PatchPoint.create(index, kind, t.display_name())
			row.colour = t.shown_colour()
			row.size = Vector2(COLUMN_WIDTH, _pitch)
			row.banded = r % 2 == 1
			row.socket_bank = socket_bank
			var out := row.outward()
			for k in _slots:
				row.jack_xs.append(out * (-(COLUMN_WIDTH * 0.5 - 0.025) + k * SLOT_PITCH))
			var ends: Dictionary = leaving if kind == PatchPoint.Kind.OUTPUT else arriving
			row.used = (ends[index] as Array).size() if ends.has(index) else 0
			row.position = Vector3(out * COLUMN_X, -HEADER - _pitch * (r + 0.5), 0)
			row.drag_began.connect(_on_drag_began)
			row.drag_moved.connect(_on_drag_moved)
			row.drag_finished.connect(_on_drag_finished)
			row.hover_changed.connect(_on_hover.bind(row))
			_adopt(row)
			if kind == PatchPoint.Kind.OUTPUT:
				_outputs[index] = row
			else:
				_inputs[index] = row

	if socket_bank != null:
		socket_bank.commit()

	for route in routes:
		_routes[Vector2i(route["src"], route["send"])] = route
		route["plugs"] = []
		for end in [PatchPoint.Kind.OUTPUT, PatchPoint.Kind.INPUT]:
			var row: PatchPoint = _outputs[route["src"]] if end == PatchPoint.Kind.OUTPUT \
					else _inputs[route["dst"]]
			var slot: int = route["out_slot"] if end == PatchPoint.Kind.OUTPUT else route["in_slot"]
			var plug := PatchPlug.create(route["src"], route["send"], route["dst"], end)
			plug.row = row
			plug.position = row.position + Vector3(row.jack_xs[slot], 0, PatchPoint.JACK_Z)
			plug.drag_began.connect(_on_drag_began)
			plug.drag_moved.connect(_on_drag_moved)
			plug.drag_finished.connect(_on_drag_finished)
			plug.hover_changed.connect(_on_hover.bind(plug))
			_adopt(plug)
			_plugs.append(plug)
			route["plugs"].append(plug)

	# Cables are laid once the rows have their final world transforms, which is after this
	# returns and the bay is placed.
	call_deferred("_draw_cables")


func _lettering() -> void:
	var half := PANEL_WIDTH * 0.5
	_print("FROM", Vector3(-half + 0.03, -0.034, 0.001), 86, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.95, 0.93, 0.88))
	_print("TRACK OUTPUTS", Vector3(-half + 0.03, -0.066, 0.001), 40, HORIZONTAL_ALIGNMENT_LEFT,
			Color(0.62, 0.63, 0.66))
	_print("TO", Vector3(half - 0.03, -0.034, 0.001), 86, HORIZONTAL_ALIGNMENT_RIGHT,
			Color(0.95, 0.93, 0.88))
	_print("SENDS INTO", Vector3(half - 0.03, -0.066, 0.001), 40, HORIZONTAL_ALIGNMENT_RIGHT,
			Color(0.62, 0.63, 0.66))
	_print("→", Vector3(0, -0.036, 0.001), 110, HORIZONTAL_ALIGNMENT_CENTER,
			Color(0.75, 0.70, 0.55))

	# The head of the bay says how to use it -- or, against a Reaper that cannot be patched from
	# here, says so, so a drag that does nothing is never the first anyone hears of it. At the
	# head, not the foot: cables into the bottom rows hang over the foot.
	var words := "DRAG A ROW ACROSS TO PATCH  ·  PULL A PLUG OFF TO UNPLUG  ·  SCROLL A PLUG FOR LEVEL"
	var tint := Color(0.62, 0.63, 0.66)
	if not DAW.can(DAWBackend.Capability.ROUTING):
		words = "READ ONLY: PATCHING NEEDS THE DAWLINGS BRIDGE LOADED IN REAPER"
		tint = Color(0.86, 0.66, 0.38)
	var how := _print(words, Vector3(0, -0.068, 0.001), 34, HORIZONTAL_ALIGNMENT_CENTER, tint)
	Lettering.fit(how, PANEL_WIDTH - 0.5, 34)

	# Says so when these rows are a BANK rather than the session: a bay is read as every track
	# there is, and the one thing you cannot do with a row that was never drawn is miss it.
	var caption := DAW.state.bank_caption()
	if caption != "":
		_print(caption, Vector3(0, -_height + FOOTER * 0.5, 0.001), 36,
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


## Every send this bay can draw: from a track it shows to another track it shows.
func _sends() -> Array:
	var out := []
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		var keys: Array = t.sends.keys()
		keys.sort()
		for k in keys:
			var dst := (t.sends[k] as MixState.SendState).resolve(DAW.state)
			if dst < 0 or dst == index or not DAW.state.tracks.has(dst):
				continue
			out.append({"src": index, "send": int(k), "dst": dst, "out_slot": 0, "in_slot": 0})
	return out


func _shape_key() -> String:
	var parts := PackedStringArray()
	for index in DAW.state.track_indices():
		var t := DAW.state.track(index)
		parts.append("%d:%s:%s" % [index, t.display_name(), t.shown_colour().to_html(false)])
	for route in _sends():
		parts.append("%d.%d>%d" % [route["src"], route["send"], route["dst"]])
	return "|".join(parts)


func _draw_cables() -> void:
	for cable in _cables:
		if is_instance_valid(cable):
			cable.queue_free()
	_cables.clear()
	if not is_inside_tree():
		return
	for key in _routes:
		var route: Dictionary = _routes[key]
		if not _outputs.has(route["src"]) or not _inputs.has(route["dst"]):
			continue
		var from_row: PatchPoint = _outputs[route["src"]]
		var to_row: PatchPoint = _inputs[route["dst"]]
		# Seeded from the pair, so a cable keeps its own slack and bow across rebuilds.
		var cable := PatchCable.create(from_row.jack_transform(route["out_slot"]),
				to_row.jack_transform(route["in_slot"]), from_row.colour,
				hash(Vector2i(route["src"], route["dst"])))
		cable.sag_ratio = CABLE_SAG
		_adopt(cable)
		_cables.append(cable)
		route["cable"] = cable


# --- carrying a cable ---------------------------------------------------------------------

func _on_drag_began(from: ControlAffordance, at: Vector3) -> void:
	_light_all(PatchPoint.Light.PLAIN, false)
	var fixed: Transform3D
	var tint: Color
	var hidden: PatchCable = null
	if from is PatchPlug:
		# The cable comes out of THIS end and stays in the other.
		var plug := from as PatchPlug
		var route: Dictionary = _routes.get(Vector2i(plug.source, plug.send_index), {})
		if route.is_empty():
			return
		var other: PatchPoint = _inputs[route["dst"]] if plug.end == PatchPoint.Kind.OUTPUT \
				else _outputs[route["src"]]
		fixed = other.jack_transform(route["in_slot"] if plug.end == PatchPoint.Kind.OUTPUT
				else route["out_slot"])
		tint = (_outputs[route["src"]] as PatchPoint).colour
		hidden = route.get("cable")
		if hidden != null and is_instance_valid(hidden):
			hidden.visible = false
		Foley.play(plug, Foley.plug_seat(), -8.0, 0.8)
	else:
		var row := from as PatchPoint
		fixed = row.jack_transform(row.free_slot())
		tint = row.colour
	var cable := PatchCable.create(fixed, _loose_end(at), tint, from.get_instance_id())
	cable.name = "CarriedCable"
	cable.sag_ratio = CABLE_SAG
	_adopt(cable)
	_drag = {"from": from, "fixed": fixed, "cable": cable, "hidden": hidden, "target": null}
	for row in _candidates(from):
		row.set_light(PatchPoint.Light.CANDIDATE)


func _on_drag_moved(from: ControlAffordance, at: Vector3, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from, over)
	var before: PatchPoint = _drag["target"]
	if before != target:
		if before != null:
			before.set_light(PatchPoint.Light.CANDIDATE)
		if target != null:
			target.set_light(PatchPoint.Light.TARGET)
		_drag["target"] = target
	# Over somewhere it can go, the plug jumps to the jack it would go in: that is the answer to
	# "what happens if I let go now", given before you do.
	var cable: PatchCable = _drag["cable"]
	cable.to_xform = target.jack_transform(target.free_slot()) if target != null else _loose_end(at)
	cable.rebuild()


func _on_drag_finished(from: ControlAffordance, over: ControlAffordance) -> void:
	if _drag.is_empty() or _drag["from"] != from:
		return
	var target := _target_for(from, over)
	var carried: PatchCable = _drag["cable"]
	if is_instance_valid(carried):
		carried.queue_free()
	var hidden: PatchCable = _drag["hidden"]
	if hidden != null and is_instance_valid(hidden):
		hidden.visible = true
	_drag.clear()
	_light_all(PatchPoint.Light.PLAIN, false)

	if from is PatchPoint:
		var row := from as PatchPoint
		if target == null:
			return
		var src := row.track_index if row.kind == PatchPoint.Kind.OUTPUT else target.track_index
		var dst := target.track_index if row.kind == PatchPoint.Kind.OUTPUT else row.track_index
		if _patch(src, dst):
			Foley.play(target, Foley.plug_seat(), -6.0)
		return

	var plug := from as PatchPlug
	if target != null:
		# Re-patched: the old send out, and one from the end that stayed to the row it went to.
		var src := plug.source if plug.end == PatchPoint.Kind.INPUT else target.track_index
		var dst := target.track_index if plug.end == PatchPoint.Kind.INPUT else plug.dest
		if _unpatch(plug.source, plug.send_index) and _patch(src, dst):
			Foley.play(target, Foley.plug_seat(), -6.0)
		return
	# Let go where it came from -- on its own plug or its own row -- and nothing has changed.
	if over == plug or over == plug.row:
		return
	_unpatch(plug.source, plug.send_index)


## The rows a cable carried from `from` could be let go on.
func _candidates(from: ControlAffordance) -> Array[PatchPoint]:
	var out: Array[PatchPoint] = []
	if from is PatchPoint:
		var row := from as PatchPoint
		var others: Dictionary = _inputs if row.kind == PatchPoint.Kind.OUTPUT else _outputs
		for index in others:
			var src: int = row.track_index if row.kind == PatchPoint.Kind.OUTPUT else index
			var dst: int = index if row.kind == PatchPoint.Kind.OUTPUT else row.track_index
			if src != dst and not _patched(src, dst):
				out.append(others[index])
	elif from is PatchPlug:
		var plug := from as PatchPlug
		var same: Dictionary = _outputs if plug.end == PatchPoint.Kind.OUTPUT else _inputs
		for index in same:
			var src: int = index if plug.end == PatchPoint.Kind.OUTPUT else plug.source
			var dst: int = plug.dest if plug.end == PatchPoint.Kind.OUTPUT else index
			if src != dst and not _patched(src, dst):
				out.append(same[index])
	return out


func _target_for(from: ControlAffordance, over: ControlAffordance) -> PatchPoint:
	var row: PatchPoint = null
	if over is PatchPoint:
		row = over
	elif over is PatchPlug:
		row = (over as PatchPlug).row
	if row == null or not row in _candidates(from):
		return null
	return row


## Where the end of a carried cable hangs when it is over nothing: at the pointer, a little proud
## of the panel, pointing in, as a plug you are about to push home.
func _loose_end(at: Vector3) -> Transform3D:
	var basis := global_transform.basis.orthonormalized()
	return Transform3D(basis, at + basis.z * 0.03)


func _patched(src: int, dst: int) -> bool:
	for key in _routes:
		if _routes[key]["src"] == src and _routes[key]["dst"] == dst:
			return true
	return false


## Through DAW like every change. Asked first whether routing can be changed at all, because the
## answer to the call itself is not the whole story: a guest's is an intent the host carries out,
## so "sent" is as much as it can know, and the host refusing is said by the host.
func _patch(src: int, dst: int) -> bool:
	if src == dst or _patched(src, dst) or not _can_route():
		return false
	DAW.create_send(src, dst)
	mark_dirty()
	return true


func _unpatch(src: int, send_index: int) -> bool:
	if not _can_route():
		return false
	DAW.remove_send(src, send_index)
	mark_dirty()
	return true


func _can_route() -> bool:
	if DAW.can(DAWBackend.Capability.ROUTING):
		return true
	# Said out loud, for the reason in the class note.
	push_warning("Patchbay: routing cannot be changed from here. The ReaScript bridge is not loaded in Reaper, and OSC has no message for making or removing a send.")
	return false


# --- picking one track out --------------------------------------------------------------------

func _on_hover(on: bool, node: ControlAffordance) -> void:
	if not _drag.is_empty() or not is_instance_valid(node):
		return
	_light_all(PatchPoint.Light.PLAIN, false)
	if not on:
		return
	var lit := []
	for key in _routes:
		var route: Dictionary = _routes[key]
		var mine := false
		if node is PatchPlug:
			mine = (node as PatchPlug).source == route["src"] \
					and (node as PatchPlug).send_index == route["send"]
		elif node is PatchPoint:
			var row := node as PatchPoint
			mine = route["src" if row.kind == PatchPoint.Kind.OUTPUT else "dst"] == row.track_index
		if mine:
			lit.append(route)
	if node is PatchPoint:
		(node as PatchPoint).set_light(PatchPoint.Light.EMPHASIS)
	if lit.is_empty():
		return
	for cable in _cables:
		if is_instance_valid(cable):
			cable.dimmed = true
	for route in lit:
		var cable: PatchCable = route.get("cable")
		if cable != null and is_instance_valid(cable):
			cable.dimmed = false
		(_outputs[route["src"]] as PatchPoint).set_light(PatchPoint.Light.EMPHASIS)
		(_inputs[route["dst"]] as PatchPoint).set_light(PatchPoint.Light.EMPHASIS)


func _light_all(how: int, dim: bool) -> void:
	for row in _outputs.values() + _inputs.values():
		if is_instance_valid(row):
			(row as PatchPoint).set_light(how)
	for cable in _cables:
		if is_instance_valid(cable):
			cable.dimmed = dim


# --- measurements -----------------------------------------------------------------------------

## The panel's height, which grows with the session; zero before the first build.
func panel_height() -> float:
	return _height


## How many jacks each row has right now.
func slots() -> int:
	return _slots


## Where a permanent loom enters the back of the bay, at a fraction (-1..1) across it.
func loom_entry(fraction: float) -> Vector3:
	if _height <= 0.0:
		return Vector3.ZERO
	var half := PANEL_WIDTH * 0.5 - 0.06
	return Vector3(clampf(fraction, -1.0, 1.0) * half, -_height + LOOM_ENTRY_RISE, -PANEL_DEPTH)


func output_row(track_index: int) -> PatchPoint:
	return _outputs.get(track_index)


func input_row(track_index: int) -> PatchPoint:
	return _inputs.get(track_index)


func plugs_of(src: int, send_index: int) -> Array:
	var route: Dictionary = _routes.get(Vector2i(src, send_index), {})
	return route.get("plugs", [])


func cable_count() -> int:
	return _cables.size()
