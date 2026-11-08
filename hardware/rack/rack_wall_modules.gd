class_name RackWallModules
extends RefCounted

## The modules in the case: blanks, building a module with its faces, knobs and jacks, taking one out or moving
## it, and refreshing faces and curves. Moved out of `hardware/rack/rack_wall.gd` without change of behaviour; the state
## (`module_nodes`, `jacks`, `knobs`) stays on the wall.

var wall: RackWall


func _init(of: RackWall) -> void:
	wall = of


func _clear_modules() -> void:
	if not wall._carry.is_empty():
		var g: Variant = wall._carry.get("ghost")
		if g is Node and is_instance_valid(g):
			(g as Node).queue_free()
		wall._carry.clear()
	for n in wall.module_nodes.values():
		if is_instance_valid(n):
			wall._drop(n)
	wall.module_nodes.clear()
	wall._on_wall.clear()
	wall.jacks.clear()
	wall.knobs.clear()
	wall._pads.clear()
	wall._lamps.clear()
	wall._scopes.clear()
	wall._bands.clear()
	wall._settle_at.clear()
	wall._stream_due.clear()


## A blank plate in every place no module holds, so the case reads as a full rack with room left. Only
## the places that changed are touched: a module put down or lifted fills or frees its own cells.
func _build_blanks() -> void:
	var taken := {}
	for id in wall.patch["modules"]:
		var m: Dictionary = wall.patch["modules"][id]
		for c in RackLayout.width_in(wall.patch, id):
			taken[Vector2i(int(m["at"][0]) + c, int(m["at"][1]))] = true
	for key: String in wall.module_nodes.keys():
		if not key.begins_with("blank/"):
			continue
		var cell := key.trim_prefix("blank/").split("_")
		if taken.has(Vector2i(int(cell[0]), int(cell[1]))):
			if is_instance_valid(wall.module_nodes[key]):
				wall._drop(wall.module_nodes[key])
			wall.module_nodes.erase(key)
	if wall._blank_paint == null:
		wall._blank_paint = StandardMaterial3D.new()
		wall._blank_paint.albedo_color = Color(0.085, 0.085, 0.09)
		wall._blank_paint.metallic = 0.4
		wall._blank_paint.roughness = 0.5
	for row in RackWall.ROWS:
		for col in RackWall.COLS:
			if taken.has(Vector2i(col, row)) or wall.module_nodes.has("blank/%d_%d" % [col, row]):
				continue
			var holder := Node3D.new()
			holder.name = "Blank_%d_%d" % [col, row]
			holder.position = Vector3(wall._x_of(col + 0.5), wall._row_foot(row), 0)
			var plate := MeshInstance3D.new()
			var face := BoxMesh.new()
			face.size = Vector3(RackWall.MODULE_WIDE - 0.003, RackWall.ROW_TALL - 0.004, 0.004)
			plate.mesh = face
			plate.position = Vector3(0, RackWall.ROW_TALL * 0.5, -0.002)
			plate.material_override = wall._blank_paint
			holder.add_child(plate)
			for y in [0.014, RackWall.ROW_TALL - 0.014]:
				var screw := MeshInstance3D.new()
				var disc := CylinderMesh.new()
				disc.top_radius = 0.0045
				disc.bottom_radius = 0.0045
				disc.height = 0.002
				screw.mesh = disc
				screw.rotation_degrees = Vector3(90, 0, 0)
				screw.position = Vector3(0, y, 0.001)
				screw.material_override = Materials.brushed_metal()
				holder.add_child(screw)
			wall._put(holder)
			wall.module_nodes["blank/%d_%d" % [col, row]] = holder


## The modules on the wall made to be the patch's, by the difference: one put in is built, one taken out
## is dropped, one moved is set in its new place. Rebuilding every module for one of them cost a visible
## stall when a module was let go. The ids whose nodes changed.
func _sync_modules() -> Dictionary:
	var changed := {}
	var now: Dictionary = wall.patch["modules"]
	for id: String in wall._on_wall.keys():
		if not now.has(id) or now[id]["type"] != wall._on_wall[id][0] or bool(now[id].get("missing", false)) != wall._on_wall[id][3]:
			_remove_module(id)
			wall._on_wall.erase(id)
			changed[id] = true
	for id: String in now:
		var m: Dictionary = now[id]
		var seen := [String(m["type"]), int(m["at"][0]), int(m["at"][1]), bool(m.get("missing", false))]
		if not wall._on_wall.has(id):
			_build_module(id)
			changed[id] = true
		elif wall._on_wall[id] != seen:
			_move_module(id)
			changed[id] = true
		else:
			continue
		wall._on_wall[id] = seen
	return changed


func _remove_module(id: String) -> void:
	if not wall._carry.is_empty() and wall._carry["id"] == id:
		var g: Variant = wall._carry.get("ghost")
		if g is Node and is_instance_valid(g):
			(g as Node).queue_free()
		wall._carry.clear()
	var holder: Variant = wall.module_nodes.get(id)
	if holder is Node and is_instance_valid(holder):
		wall._drop(holder as Node)
	wall.module_nodes.erase(id)
	wall.module_nodes.erase(id + "/x")
	for d: Dictionary in [wall.jacks, wall.knobs, wall._settle_at, wall._stream_due]:
		for key: String in d.keys():
			if key.begins_with(id + "."):
				d.erase(key)
	for d: Dictionary in [wall._pads, wall._lamps, wall._scopes, wall._bands]:
		d.erase(id)


## A module set in the cell the patch now has for it. The one a hand is carrying stays under the hand,
## and goes home to the new place when let go.
func _move_module(id: String) -> void:
	var m: Dictionary = wall.patch["modules"][id]
	var holder: Node3D = wall.module_nodes.get(id)
	if holder == null or not is_instance_valid(holder):
		return
	var col := int(m["at"][0])
	var row := int(m["at"][1])
	var to := Vector3(wall._x_of(col + RackLayout.width_in(wall.patch, id) * 0.5), wall._row_foot(row), 0)
	if not wall._carry.is_empty() and wall._carry["id"] == id:
		wall._carry["home"] = to
	else:
		holder.position = to
	var plate := holder.get_node_or_null("Plate") as MeshInstance3D
	if plate != null:
		(plate.material_override as StandardMaterial3D).albedo_color = RackSkin.face(String(m["type"]), (col + row) % 2 == 1)


func _build_module(id: String) -> void:
	var m: Dictionary = wall.patch["modules"][id]
	var type: String = m["type"]
	# A module no mod here provides is a plate naming the mod (RackGaps), in its place.
	var absent: bool = m.get("missing", false)
	var spec := {"title": RackGaps.plate_title(wall.patch, id), "knobs": [], "ins": [], "outs": []} if absent else RackCatalogue.spec(type)
	var w := RackLayout.width_in(wall.patch, id)
	var col := int(m["at"][0])
	var row := int(m["at"][1])
	var holder := Node3D.new()
	holder.name = "Module_%s" % id
	holder.position = Vector3(wall._x_of(col + w * 0.5), wall._row_foot(row), 0)
	var wide := RackWall.MODULE_WIDE * w
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var face := BoxMesh.new()
	face.size = Vector3(wide - 0.003, RackWall.ROW_TALL - 0.004, 0.004)
	plate.mesh = face
	plate.position = Vector3(0, RackWall.ROW_TALL * 0.5, -0.002)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = RackSkin.face(type, (col + row) % 2 == 1)
	paint.roughness = 0.6
	plate.material_override = paint
	holder.add_child(plate)
	var title: String = spec["title"]
	holder.add_child(wall._letter(title, RackWall.TITLE_CAP, Vector3(0, RackWall.ROW_TALL - 0.03, 0.001), Color(1.0, 0.96, 0.84), wide - 0.05))
	var tint := _tint_of(type)
	var print_strip := RackSkin.print_pattern(type, wide - 0.016, 0.012)
	if print_strip != null:
		print_strip.position = Vector3(0, RackWall.ROW_TALL - 0.064, 0.0006)
		holder.add_child(print_strip)
	var tag := RackGaps.plate_note(wall.patch, id) if absent else RackSkin.tagline(type)
	if tag != "":
		var tag_label := wall._letter(tag, RackWall.LETTER_CAP * 0.66, Vector3(0, 0.015, 0.001), tint.lerp(Color(1, 1, 1), 0.5), wide - 0.01)
		holder.add_child(tag_label)
	var band := MeshInstance3D.new()
	band.name = "Band"
	var strip := BoxMesh.new()
	strip.size = Vector3(wide - 0.01, 0.005, 0.001)
	band.mesh = strip
	band.position = Vector3(0, RackWall.ROW_TALL - 0.045, 0.0005)
	var colour := StandardMaterial3D.new()
	colour.albedo_color = tint
	colour.emission = tint
	band.material_override = colour
	wall._bands[id] = colour
	holder.add_child(band)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lamp"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.005
	disc.bottom_radius = 0.005
	disc.height = 0.003
	lamp.mesh = disc
	lamp.rotation_degrees = Vector3(90, 0, 0)
	lamp.position = Vector3(-wide * 0.5 + 0.012, RackWall.ROW_TALL - 0.026, 0.002)
	lamp.material_override = wall._lamp_cold
	holder.add_child(lamp)
	wall._lamps[id] = lamp
	if type != RackPatch.OUT_MODULE:
		var gone := wall._key("x", Vector2(0.02, 0.02), Vector3(wide * 0.5 - 0.014, RackWall.ROW_TALL - 0.026, 0.0),
				"take %s out of the case, and its cables with it" % title, func() -> void: wall.edit_asked.emit("remove", [id]))
		holder.add_child(gone)
		wall.module_nodes[id + "/x"] = gone
	# The grip along the title, clear of the take-out key: drag the module about the case.
	var grip := RackHandle.new()
	grip.name = "Grip"
	grip.module_id = id
	grip.module_title = title
	grip.size = Vector2(wide - 0.05, 0.034)
	grip.position = Vector3(-0.008, RackWall.ROW_TALL - 0.026, 0.0)
	grip.drag_began.connect(wall._on_grip_began)
	grip.drag_moved.connect(wall._on_grip_moved)
	grip.drag_finished.connect(wall._on_grip_finished)
	holder.add_child(grip)
	# Knobs, down from under the title, a row of 2*w.
	var per := 2 * w
	var ks: Array = spec["knobs"]
	for n in ks.size():
		var r := n / per
		var inrow := mini(per, ks.size() - r * per)
		var c := n % per
		var at := Vector3((c - (inrow - 1) * 0.5) * RackWall.KNOB_PITCH, RackWall.ROW_TALL - 0.1 - r * RackWall.KNOB_ROW, 0.0)
		_build_knob(holder, id, ks[n], at)
	if type == "builtin.scope":
		var screen := ScopeScreen.new()
		screen.size = Vector2(wide - 0.03, 0.2)
		screen.tint = _tint_of(type)
		screen.position = Vector3(0, 0.24, 0.003)
		holder.add_child(screen)
		wall._scopes[id] = screen
	_build_second_face(holder, id, type, spec, w, wide, tint)
	# Jacks, up from the foot: inputs, then outputs (pale), per rows of 2*w.
	var paths: Array = []
	for port in spec["ins"]:
		paths.append([port, false])
	for port in spec["outs"]:
		paths.append([port, true])
	for n in paths.size():
		var r := n / per
		var inrow := mini(per, paths.size() - r * per)
		var c := n % per
		var path := "%s.%s" % [id, paths[n][0]]
		var j := RackJack.make(path, paths[n][1], title)
		j.position = Vector3((c - (inrow - 1) * 0.5) * RackWall.KNOB_PITCH, 0.05 + r * RackWall.JACK_ROW, 0.0)
		j.drag_began.connect(wall.dragging._on_drag_began)
		j.drag_moved.connect(wall.dragging._on_drag_moved)
		j.drag_finished.connect(wall.dragging._on_drag_finished)
		holder.add_child(j)
		wall.jacks[wall._jack_key(path, paths[n][1])] = j
	wall._put(holder)
	wall.module_nodes[id] = holder


## The free band of the panel between the knobs and the jacks, which a module's second face fills: an
## orb pad on two of its knobs, or for a sequencer its steps as bars to paint.
func _build_second_face(holder: Node3D, id: String, type: String, spec: Dictionary, w: int, wide: float, tint: Color) -> void:
	var per := 2 * w
	var krows := maxi(1, ceili(float((spec["knobs"] as Array).size()) / per))
	var jacks_n: int = (spec["ins"] as Array).size() + (spec["outs"] as Array).size()
	var jrows := maxi(1, ceili(float(jacks_n) / per))
	var top := 0.05 + (jrows - 1) * RackWall.JACK_ROW + 0.035
	var bottom := RackWall.ROW_TALL - 0.1 - (krows - 1) * RackWall.KNOB_ROW - 0.03
	var band := bottom - top
	if type == "builtin.seq":
		var bars := RackBars.new()
		bars.name = "Steps"
		bars.count = 16
		bars.wide = wide - 0.02
		bars.tall = minf(0.15, band - 0.02)
		bars.tint = tint.lightened(0.25)
		bars.position = Vector3(0, top + 0.01, 0.0)
		var keys: Array = []
		for n in 16:
			keys.append("s%d" % (n + 1))
		holder.add_child(bars)
		for n in 16:
			bars.set_step(n, RackPatch.knob_of(wall.patch, id, keys[n]))
		bars.painted.connect(func(step: int, v: float) -> void: _face_to(id, keys[step], v))
		bars.released.connect(func(steps: Array) -> void: _face_done(id, steps.map(func(n: int) -> String: return keys[n])))
		wall._pads[id] = {"node": bars, "keys": keys}
		return
	var ids := wall.pad_knobs(type)
	if ids.is_empty():
		return
	var size := minf(minf(wide - 0.024, band - 0.012), 0.09)
	if size < 0.045:
		return
	if RackCatalogue.knob(type, ids[0]).is_empty() or RackCatalogue.knob(type, ids[1]).is_empty():
		return
	var pad := RackPad.new()
	pad.name = "Orb"
	pad.size = size
	pad.tint = tint.lightened(0.3)
	pad.position = Vector3(0, top + band * 0.5, 0.0)
	holder.add_child(pad)
	pad.set_xy(RackPatch.knob_of(wall.patch, id, ids[0]), RackPatch.knob_of(wall.patch, id, ids[1]))
	wall._pads[id] = {"node": pad, "keys": ids, "type": type}
	_refresh_curve(id)
	pad.moved.connect(func(x: float, y: float) -> void:
		_face_to(id, ids[0], x)
		_face_to(id, ids[1], y)
		_refresh_curve(id, {ids[0]: x, ids[1]: y}))
	pad.released.connect(func(_x: float, _y: float) -> void: _face_done(id, ids))


## A knob set from a module's second face: the knob on the wall goes there, and the turn is streamed
## to the room as a knob's own would be.
func _face_to(id: String, k: String, v: float) -> void:
	var node: Knob = wall.knobs.get("%s.%s" % [id, k])
	if node != null:
		node.apply_remote(v)
	wall.dragging._on_knob_turned(id, k, v)


## Let go: the knobs it moved are asked for once more, at rest, when the echoes of the stream have passed.
func _face_done(id: String, keys: Array) -> void:
	var now := int(wall.clock.call())
	for k in keys:
		wall._settle_at["%s.%s" % [id, k]] = now + roundi(RackWall.SETTLE * 1000.0)


## The shape a module's knobs make (an envelope, a filter's response), drawn on its pad. `over` holds
## knob positions that are newer than the patch's, as while an orb is being dragged.
func _refresh_curve(id: String, over := {}) -> void:
	var f: Dictionary = wall._pads.get(id, {})
	if not (f.get("node") is RackPad):
		return
	var type: String = f.get("type", "")
	var values := {}
	for k in RackCatalogue.knob_ids(type):
		var pos: float = over[k] if over.has(k) else RackPatch.knob_of(wall.patch, id, k)
		values[k] = RackCatalogue.real(RackCatalogue.knob(type, k), pos)
	var c := RackCurves.of(type, values)
	if c.size() > 1:
		(f["node"] as RackPad).set_curve(c)


## The second faces take their knobs' values, where a hand is not on them.
func _refresh_faces(only := "") -> void:
	for id: String in wall._pads:
		if only != "" and id != only:
			continue
		var f: Dictionary = wall._pads[id]
		var node: Node = f["node"]
		if not is_instance_valid(node):
			continue
		if node is RackPad:
			(node as RackPad).set_xy(RackPatch.knob_of(wall.patch, id, f["keys"][0]), RackPatch.knob_of(wall.patch, id, f["keys"][1]))
			_refresh_curve(id)
		elif node is RackBars and not (node as RackBars).is_held():
			for n in 16:
				(node as RackBars).set_step(n, RackPatch.knob_of(wall.patch, id, f["keys"][n]))


func _build_knob(holder: Node3D, id: String, k: Dictionary, at: Vector3) -> void:
	var key := "%s.%s" % [id, k["id"]]
	var knob := Knob.new()
	knob.name = "Knob_%s" % key.replace(".", "_")
	knob.position = at + Vector3(0, 0.008, 0.008)
	knob.value = RackPatch.knob_of(wall.patch, id, k["id"])
	var title := "%s  %s" % [RackCatalogue.spec(RackPatch.type_of(wall.patch, id))["title"], k["label"]]
	knob.describe_title = func() -> String: return "RACK  %s" % title
	knob.describe_value = func(v: float) -> String: return RackCatalogue.readout(k, v)
	knob.turned.connect(func(v: float) -> void: wall.dragging._on_knob_turned(id, k["id"], v))
	knob.value_committed.connect(func(_v: float) -> void: wall._settle_at[key] = int(wall.clock.call()) + roundi(RackWall.SETTLE * 1000.0))
	holder.add_child(knob)
	wall.knobs[key] = knob
	var label := String(k["label"])
	holder.add_child(wall._letter(label.substr(0, 6), RackWall.LETTER_CAP * 0.9, at + Vector3(0, -0.022, 0.001), Color(0.95, 0.93, 0.88), RackWall.KNOB_PITCH - 0.004))


func _tint_of(type: String) -> Color:
	return RackSkin.accent(type)
