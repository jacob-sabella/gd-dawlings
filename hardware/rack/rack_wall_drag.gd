class_name RackWallDrag
extends RefCounted

## What a hand does on the rack: turning a knob, carrying a module by its grip, and dragging a cable from a
## jack. Each turns into an ask the studio puts to the room (`edit_asked`, `knob_set`). Moved out of
## `hardware/rack/rack_wall.gd` without change of behaviour.

var wall: RackWall


func _init(of: RackWall) -> void:
	wall = of


func _on_knob_turned(id: String, k: String, v: float) -> void:
	if not is_instance_valid(wall):
		return
	wall.knob_turning.emit(id, k, v)
	var key := "%s.%s" % [id, k]
	var now := int(wall.clock.call())
	if now - int(wall._streamed_at.get(key, -100000)) >= RackWall.STREAM_GAP_MSEC:
		wall._streamed_at[key] = now
		wall._stream_due.erase(key)
		wall.knob_streamed.emit(id, k, v)
	else:
		wall._stream_due[key] = [id, k, v]


## The cell (column, row) whose module of `w` columns has its middle under `local`, a point of the panel.
func _cell_under(local: Vector3, w: int) -> Vector2i:
	var col := roundi((local.x + RackWall.WIDE * 0.5) / RackWall.MODULE_WIDE - w * 0.5)
	var up := (local.y - RackWall.PALETTE_TALL) / (RackWall.ROW_TALL + RackWall.ROW_GAP)
	var row := RackWall.ROWS - 1 - clampi(floori(up), 0, RackWall.ROWS - 1)
	return Vector2i(clampi(col, 0, RackWall.COLS - w), row)


func _on_grip_began(from: RackHandle, at: Vector3) -> void:
	if not is_instance_valid(wall):
		return
	var holder: Node3D = wall.module_nodes.get(from.module_id)
	if holder == null:
		return
	var local: Vector3 = wall.panel.to_local(at)
	var type := RackPatch.type_of(wall.patch, from.module_id)
	var ghost := MeshInstance3D.new()
	ghost.name = "MoveGhost"
	var box := BoxMesh.new()
	var w := RackLayout.width_in(wall.patch, from.module_id)
	box.size = Vector3(RackWall.MODULE_WIDE * w - 0.003, RackWall.ROW_TALL - 0.004, 0.006)
	ghost.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.material_override = m
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.panel.add_child(ghost)
	wall._carry = {"id": from.module_id, "holder": holder, "ghost": ghost, "w": w, "type": type,
			"grab": holder.position - Vector3(local.x, local.y, 0.0), "home": holder.position, "cell": Vector2i(-1, -1), "relaid": 0}
	_carry_to(local)


func _on_grip_moved(from: RackHandle, at: Vector3) -> void:
	if not is_instance_valid(wall):
		return
	if wall._carry.is_empty() or wall._carry["id"] != from.module_id:
		return
	_carry_to(wall.panel.to_local(at))


## The module lifted to follow the hand, and the cell it would settle in outlined: green where it fits.
func _carry_to(local: Vector3) -> void:
	var holder: Node3D = wall._carry["holder"]
	var w: int = wall._carry["w"]
	var lifted: Vector3 = local + (wall._carry["grab"] as Vector3)
	holder.position = Vector3(lifted.x, lifted.y, 0.05)
	var cell := _cell_under(Vector3(lifted.x, lifted.y + RackWall.ROW_TALL * 0.5, 0.0), w)
	var fits := RackLayout.fits(wall.patch, String(wall._carry["type"]), cell, String(wall._carry["id"]))
	var ghost: MeshInstance3D = wall._carry["ghost"]
	ghost.position = Vector3(wall._x_of(cell.x + w * 0.5), wall._row_foot(cell.y) + RackWall.ROW_TALL * 0.5, 0.004)
	(ghost.material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.5, 0.22) if fits else Color(1.0, 0.3, 0.25, 0.2)
	wall._carry["cell"] = cell
	wall._carry["fits"] = fits
	# Its cables follow, as often as the wall can afford to lay them again.
	wall._carry["relaid"] = int(wall._carry["relaid"]) + 1
	if int(wall._carry["relaid"]) % 4 == 0:
		wall.shown._lay_cables({String(wall._carry["id"]): true})


func _on_grip_finished(from: RackHandle, _at: Vector3) -> void:
	if not is_instance_valid(wall):
		return
	if wall._carry.is_empty() or wall._carry["id"] != from.module_id:
		return
	var holder: Node3D = wall._carry["holder"]
	var ghost: MeshInstance3D = wall._carry["ghost"]
	var cell: Vector2i = wall._carry["cell"]
	var id: String = wall._carry["id"]
	var home: Vector3 = wall._carry["home"]
	var fits: bool = wall._carry.get("fits", false)
	var here: Array = wall.patch["modules"][id]["at"]
	wall._carry.clear()
	if is_instance_valid(ghost):
		ghost.queue_free()
	if is_instance_valid(holder):
		holder.position = home
	# Its cables back to where it stands, whatever the answer to the ask is (a refusal changes nothing).
	wall.shown._lay_cables({id: true})
	if fits and (cell.x != int(here[0]) or cell.y != int(here[1])):
		Foley.play(holder, Foley.plug_seat(), -6.0)
		wall.edit_asked.emit("move", [id, cell.x, cell.y])


func _on_drag_began(from: ModularJack, at: Vector3) -> void:
	if not is_instance_valid(wall):
		return
	var path := String(from.jack)
	var fixed: Transform3D = from.plug_transform()
	var tint := wall.modules._tint_of(RackPatch.type_of(wall.patch, path.get_slice(".", 0)))
	var lifted_from := ""
	var hidden: PatchCable = null
	if not from.output:
		# An input with cables gives up the newest: its plug comes out of here.
		for i in range(wall.patch["cables"].size() - 1, -1, -1):
			if wall.patch["cables"][i][1] == path:
				lifted_from = wall.patch["cables"][i][0]
				break
		if lifted_from != "" and wall.jacks.has(wall._jack_key(lifted_from, true)):
			fixed = (wall.jacks[wall._jack_key(lifted_from, true)] as RackJack).plug_transform()
			tint = wall.modules._tint_of(RackPatch.type_of(wall.patch, lifted_from.get_slice(".", 0)))
			hidden = _cable_between(lifted_from, path)
			if hidden != null:
				hidden.visible = false
	var carried := PatchCable.create(fixed, _loose_end(at), tint, from.get_instance_id())
	carried.name = "CarriedCable"
	carried.sag_ratio = RackWall.CABLE_SAG
	wall.add_child(carried)
	wall._drag = {"from": from, "lifted": lifted_from, "cable": carried, "hidden": hidden, "target": null}
	for j in _candidates(from, lifted_from):
		j.set_light(ModularJack.Light.CANDIDATE)


func _cable_between(a: String, b: String) -> PatchCable:
	for c in wall.cables:
		if is_instance_valid(c) and (c.get_meta(&"cable") as Array) == [a, b]:
			return c
	return null


func _on_drag_moved(from: ModularJack, at: Vector3, over: ControlAffordance) -> void:
	if not is_instance_valid(wall):
		return
	if wall._drag.is_empty() or wall._drag["from"] != from:
		return
	var target := _target_for(from, over)
	var before: RackJack = wall._drag["target"]
	if before != target:
		if before != null:
			before.set_light(ModularJack.Light.CANDIDATE)
		if target != null:
			target.set_light(ModularJack.Light.TARGET)
		wall._drag["target"] = target
	var cable: PatchCable = wall._drag["cable"]
	cable.to_xform = target.plug_transform() if target != null else _loose_end(at)
	cable.rebuild()


func _on_drag_finished(from: ModularJack, over: ControlAffordance) -> void:
	if not is_instance_valid(wall):
		return
	if wall._drag.is_empty() or wall._drag["from"] != from:
		return
	var target := _target_for(from, over)
	var lifted: String = wall._drag["lifted"]
	var carried: PatchCable = wall._drag["cable"]
	if is_instance_valid(carried):
		carried.queue_free()
	var hidden: PatchCable = wall._drag["hidden"]
	if hidden != null and is_instance_valid(hidden):
		hidden.visible = true
	wall._drag.clear()
	for j: RackJack in wall.jacks.values():
		j.set_light(ModularJack.Light.PLAIN)
	if lifted != "":
		if over == from:
			return
		wall.edit_asked.emit("pull_one", [lifted, String(from.jack)])
		if target != null:
			wall.edit_asked.emit("cable", [lifted, String(target.jack)])
			Foley.play(target, Foley.plug_seat(), -6.0)
		return
	if target == null:
		return
	var source := from if from.output else target
	var sink := target if from.output else from
	wall.edit_asked.emit("cable", [String(source.jack), String(sink.jack)])
	Foley.play(target, Foley.plug_seat(), -6.0)


## The jacks a cable carried from `from` could be let go on: from an output, every input of another
## module; from an input, every output of another module.
func _candidates(from: RackJack, lifted: String) -> Array[RackJack]:
	var out: Array[RackJack] = []
	var mine := String(from.jack).get_slice(".", 0)
	for j: RackJack in wall.jacks.values():
		if j == from or String(j.jack).get_slice(".", 0) == mine and lifted == "":
			continue
		if lifted != "":
			if not j.output and String(j.jack).get_slice(".", 0) != lifted.get_slice(".", 0):
				out.append(j)
		elif j.output != from.output:
			out.append(j)
	return out


func _target_for(from: RackJack, over: ControlAffordance) -> RackJack:
	var j := over as RackJack
	if j == null or j == from:
		return null
	return j if _candidates(from, wall._drag.get("lifted", "")).has(j) else null


func _loose_end(at: Vector3) -> Transform3D:
	var basis := wall.global_transform.basis.orthonormalized()
	return Transform3D(basis, at + basis.z * 0.03)
